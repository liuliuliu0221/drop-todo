import Foundation

protocol TaskServicing: Sendable {
    func start() async throws -> StoreLoadOutcome
    func create(_ input: CreateTaskInput) async throws -> TaskRecord
    func update(id: UUID, changes: TaskChanges) async throws
    func complete(id: UUID, at: Date) async throws -> CompletionSnapshot
    func cancel(id: UUID) async throws
    func expireDueTasks(
        at: Date,
        excluding protectedTaskIDs: Set<UUID>
    ) async throws -> [ExpirationSnapshot]
    func recall(id: UUID, newDeadline: Date, at: Date) async throws -> TaskRecord
    func burn(id: UUID) async throws
    func clearCompleted() async throws
    func clearAll() async throws
    func tasks(status: TaskStatus?) async throws -> [TaskRecord]
}

actor TaskService: TaskServicing {
    private static let maximumTitleLength = 100
    private static let minimumDeadlineLeadTime: TimeInterval = 60

    private let store: TaskStore
    private let nowProvider: any NowProviding
    private var recordsByID: [UUID: TaskRecord] = [:]
    private var isStarted = false
    private var isMutationInFlight = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(store: TaskStore, nowProvider: any NowProviding = SystemNowProvider()) {
        self.store = store
        self.nowProvider = nowProvider
    }

    func start() async throws -> StoreLoadOutcome {
        await acquireMutation()
        defer { releaseMutation() }

        let outcome = try await store.load()
        let envelope = try await store.snapshot()
        recordsByID = Dictionary(uniqueKeysWithValues: envelope.tasks.map { ($0.id, $0) })
        isStarted = true
        return outcome
    }

    func create(_ input: CreateTaskInput) async throws -> TaskRecord {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        let now = nowProvider.now()
        let title = try validatedTitle(input.title)
        try validateDeadline(input.deadline, relativeTo: now)

        let record = TaskRecord(
            id: UUID(),
            title: title,
            deadline: input.deadline,
            tag: input.tag,
            urgency: input.urgency,
            status: .active,
            createdAt: now,
            visualStartAt: now,
            completedAt: nil,
            ruinedAt: nil,
            recalledAt: nil,
            recalledFromID: nil
        )
        var next = recordsByID
        next[record.id] = record
        try await persist(next, at: now)
        return record
    }

    func update(id: UUID, changes: TaskChanges) async throws {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        let now = nowProvider.now()
        var record = try activeRecord(id: id)

        if let title = changes.title {
            record.title = try validatedTitle(title)
        }
        if let deadline = changes.deadline {
            try validateDeadline(deadline, relativeTo: now)
            record.deadline = deadline
        }
        switch changes.tag {
        case .unchanged:
            break
        case let .set(tag):
            record.tag = tag
        }
        if let urgency = changes.urgency {
            record.urgency = urgency
        }

        var next = recordsByID
        next[id] = record
        try await persist(next, at: now)
    }

    func complete(id: UUID, at: Date) async throws -> CompletionSnapshot {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        var record = try activeRecord(id: id)
        record.status = .completed
        record.completedAt = at

        var next = recordsByID
        next[id] = record
        try await persist(next, at: at)
        return CompletionSnapshot(
            taskID: id,
            completedAt: at,
            tag: record.tag,
            urgency: record.urgency
        )
    }

    func cancel(id: UUID) async throws {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        _ = try activeRecord(id: id)
        var next = recordsByID
        next.removeValue(forKey: id)
        try await persist(next, at: nowProvider.now())
    }

    func expireDueTasks(
        at: Date,
        excluding protectedTaskIDs: Set<UUID> = []
    ) async throws -> [ExpirationSnapshot] {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        var next = recordsByID
        var snapshots: [ExpirationSnapshot] = []

        for var record in next.values where record.status == .active
            && record.deadline <= at
            && !protectedTaskIDs.contains(record.id) {
            record.status = .ruined
            record.ruinedAt = at
            next[record.id] = record
            snapshots.append(
                ExpirationSnapshot(taskID: record.id, deadline: record.deadline, ruinedAt: at)
            )
        }
        guard !snapshots.isEmpty else { return [] }

        try await persist(next, at: at)
        return snapshots.sorted { $0.deadline < $1.deadline }
    }

    func clearCompleted() async throws {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        let next = recordsByID.filter { $0.value.status != .completed }
        guard next.count != recordsByID.count else { return }
        try await persist(next, at: nowProvider.now())
    }

    func clearAll() async throws {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        guard !recordsByID.isEmpty else { return }
        let now = nowProvider.now()
        try await store.clearAll(savedAt: now)
        recordsByID = [:]
    }

    func recall(id: UUID, newDeadline: Date, at: Date) async throws -> TaskRecord {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        try validateDeadline(newDeadline, relativeTo: at)
        guard var original = recordsByID[id] else {
            throw TaskDomainError.taskNotFound(id)
        }
        guard original.status == .ruined else {
            throw TaskDomainError.invalidStatus(expected: .ruined, actual: original.status)
        }

        original.status = .recalled
        original.recalledAt = at
        let recalled = TaskRecord(
            id: UUID(),
            title: original.title,
            deadline: newDeadline,
            tag: original.tag,
            urgency: original.urgency,
            status: .active,
            createdAt: at,
            visualStartAt: at,
            completedAt: nil,
            ruinedAt: nil,
            recalledAt: nil,
            recalledFromID: original.id
        )

        var next = recordsByID
        next[original.id] = original
        next[recalled.id] = recalled
        try await persist(next, at: at)
        return recalled
    }

    func burn(id: UUID) async throws {
        await acquireMutation()
        defer { releaseMutation() }

        try ensureStarted()
        guard let original = recordsByID[id] else {
            throw TaskDomainError.taskNotFound(id)
        }
        guard original.status == .ruined else {
            throw TaskDomainError.invalidStatus(expected: .ruined, actual: original.status)
        }

        var next = recordsByID
        next.removeValue(forKey: id)
        for (taskID, var record) in next where record.recalledFromID == id {
            record.recalledFromID = nil
            next[taskID] = record
        }
        try await persist(next, at: nowProvider.now())
    }

    func tasks(status: TaskStatus? = nil) async throws -> [TaskRecord] {
        try ensureStarted()
        return recordsByID.values
            .filter { status == nil || $0.status == status }
            .sorted {
                if $0.status == .completed, $1.status == .completed {
                    let left = $0.completedAt ?? .distantPast
                    let right = $1.completedAt ?? .distantPast
                    if left == right {
                        return $0.createdAt > $1.createdAt
                    }
                    return left > right
                }
                if $0.status == .ruined, $1.status == .ruined {
                    if $0.deadline == $1.deadline {
                        return $0.createdAt > $1.createdAt
                    }
                    return $0.deadline > $1.deadline
                }
                if $0.deadline == $1.deadline {
                    return $0.createdAt < $1.createdAt
                }
                return $0.deadline < $1.deadline
            }
    }

    private func ensureStarted() throws {
        guard isStarted else { throw TaskDomainError.serviceNotStarted }
    }

    private func activeRecord(id: UUID) throws -> TaskRecord {
        guard let record = recordsByID[id] else { throw TaskDomainError.taskNotFound(id) }
        guard record.status == .active else {
            throw TaskDomainError.invalidStatus(expected: .active, actual: record.status)
        }
        return record
    }

    private func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TaskDomainError.titleEmpty }
        guard trimmed.count <= Self.maximumTitleLength else {
            throw TaskDomainError.titleTooLong(maximum: Self.maximumTitleLength)
        }
        return trimmed
    }

    private func validateDeadline(_ deadline: Date, relativeTo now: Date) throws {
        let minimum = now.addingTimeInterval(Self.minimumDeadlineLeadTime)
        guard deadline >= minimum else {
            throw TaskDomainError.deadlineTooSoon(minimum: minimum)
        }
    }

    private func persist(_ next: [UUID: TaskRecord], at date: Date) async throws {
        _ = try await store.save(tasks: Array(next.values), savedAt: date)
        recordsByID = next
    }

    /// Actor methods are reentrant across `await`. Keep the complete read-modify-save
    /// transaction exclusive so a later mutation cannot derive from stale memory.
    private func acquireMutation() async {
        if !isMutationInFlight {
            isMutationInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            mutationWaiters.append(continuation)
        }
    }

    private func releaseMutation() {
        guard !mutationWaiters.isEmpty else {
            isMutationInFlight = false
            return
        }
        let next = mutationWaiters.removeFirst()
        next.resume()
    }
}

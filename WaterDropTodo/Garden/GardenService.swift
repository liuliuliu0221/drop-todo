import Foundation

enum GardenServiceError: Error, Sendable, Equatable, LocalizedError {
    case notStarted
    case tooManyPendingEvents

    var errorDescription: String? {
        switch self {
        case .notStarted:
            "花园服务尚未启动。"
        case .tooManyPendingEvents:
            "待处理的完成动画过多，请稍后重试。"
        }
    }
}

actor GardenService {
    private let store: GardenStore
    private var state = GardenState.empty()
    private var isStarted = false

    init(store: GardenStore) {
        self.store = store
    }

    @discardableResult
    func start(taskStatuses: [UUID: TaskStatus]) async throws -> GardenSnapshot {
        _ = try await store.load()
        state = try await store.snapshot()
        isStarted = true
        try await reconcilePendingEvents(taskStatuses: taskStatuses)
        return snapshot()
    }

    func prepare(
        taskID: UUID,
        completedAt: Date,
        impactNormalizedX: Double,
        preparedAt: Date = Date()
    ) async throws -> PendingGardenEvent {
        try ensureStarted()
        if let existing = state.pendingEvents.first(where: { $0.taskID == taskID }) {
            return existing
        }
        guard state.pendingEvents.count < GardenConstants.maximumPendingEvents else {
            throw GardenServiceError.tooManyPendingEvents
        }

        let plan = GardenDistribution.makePlan(
            taskID: taskID,
            completedAt: completedAt,
            impactNormalizedX: impactNormalizedX,
            cells: state.cells
        )
        let event = PendingGardenEvent(
            taskID: taskID,
            completedAt: completedAt,
            impactNormalizedX: min(max(impactNormalizedX, 0), 1),
            randomSeed: plan.randomSeed,
            landingPositions: plan.landingPositions,
            cellDeltas: plan.cellDeltas,
            preparedAt: preparedAt
        )
        var next = state
        next.pendingEvents.append(event)
        next.savedAt = preparedAt
        try await store.save(next)
        state = next
        return event
    }

    func commit(taskID: UUID, at date: Date = Date()) async throws -> GardenCommitResult {
        try ensureStarted()
        guard let eventIndex = state.pendingEvents.firstIndex(where: { $0.taskID == taskID }) else {
            return GardenCommitResult(
                snapshot: snapshot(),
                landingPositions: [],
                changedCellIndices: []
            )
        }

        let event = state.pendingEvents[eventIndex]
        var next = state
        var changed = Set<Int>()
        for delta in event.cellDeltas {
            guard next.cells.indices.contains(delta.cellIndex) else { continue }
            let existing = UInt32(next.cells[delta.cellIndex].density)
            let increased = min(UInt32(UInt16.max), existing + UInt32(delta.amount))
            next.cells[delta.cellIndex].density = UInt16(increased)
            next.cells[delta.cellIndex].lastWateredAt = date
            changed.insert(delta.cellIndex)
        }
        next.pendingEvents.remove(at: eventIndex)
        next.totalCompletions += 1
        next.savedAt = date
        try await store.save(next)
        state = next
        return GardenCommitResult(
            snapshot: snapshot(),
            landingPositions: event.landingPositions,
            changedCellIndices: changed
        )
    }

    func cancel(taskID: UUID, at date: Date = Date()) async throws {
        try ensureStarted()
        guard state.pendingEvents.contains(where: { $0.taskID == taskID }) else { return }
        var next = state
        next.pendingEvents.removeAll { $0.taskID == taskID }
        next.savedAt = date
        try await store.save(next)
        state = next
    }

    func clearAll(at date: Date = Date()) async throws -> GardenSnapshot {
        try ensureStarted()
        try await store.clearAll(at: date)
        state = try await store.snapshot()
        return snapshot()
    }

    func currentSnapshot() throws -> GardenSnapshot {
        try ensureStarted()
        return snapshot()
    }

    private func reconcilePendingEvents(taskStatuses: [UUID: TaskStatus]) async throws {
        guard !state.pendingEvents.isEmpty else { return }
        let pendingTaskIDs = state.pendingEvents.map(\.taskID)
        for taskID in pendingTaskIDs {
            if taskStatuses[taskID] == .completed {
                _ = try await commit(taskID: taskID)
            } else {
                try await cancel(taskID: taskID)
            }
        }
    }

    private func snapshot() -> GardenSnapshot {
        GardenSnapshot(totalCompletions: state.totalCompletions, cells: state.cells)
    }

    private func ensureStarted() throws {
        guard isStarted else { throw GardenServiceError.notStarted }
    }
}

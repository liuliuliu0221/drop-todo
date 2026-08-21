import Foundation

enum HoverCardPhase: Sendable, Equatable {
    case idle
    case hoverPending
    case presented
    case pinned
    case graceExpired
}

struct HoverCardSession: Sendable, Equatable {
    static let presentationDelay: TimeInterval = 0.15
    static let dismissalDelay: TimeInterval = 0.25
    static let maximumProtectionDuration: TimeInterval = 60

    private(set) var phase: HoverCardPhase = .idle
    private(set) var task: TaskRecord?
    private(set) var frozenRemainingTime: TimeInterval = 0
    private(set) var protectionEndsAt: Date?
    private(set) var isProtectionActive = false

    var taskID: UUID? { task?.id }
    var isPresented: Bool {
        phase == .presented || phase == .pinned || phase == .graceExpired
    }
    var isPinned: Bool { phase == .pinned }
    var isCompletionEnabled: Bool {
        isPresented && phase != .graceExpired && task?.status == .active
    }
    var protectedTaskIDs: Set<UUID> {
        guard isProtectionActive, let taskID else { return [] }
        return [taskID]
    }

    mutating func begin(task: TaskRecord, now: Date) {
        self.task = task
        phase = .hoverPending
        frozenRemainingTime = max(task.deadline.timeIntervalSince(now), 0)
        protectionEndsAt = now.addingTimeInterval(Self.maximumProtectionDuration)
        isProtectionActive = task.status == .active && task.deadline > now
    }

    mutating func present() {
        guard phase == .hoverPending else { return }
        phase = .presented
    }

    mutating func pin() {
        guard task != nil, phase != .graceExpired else { return }
        phase = .pinned
    }

    mutating func updateTask(_ task: TaskRecord) {
        guard task.id == taskID else { return }
        self.task = task
    }

    mutating func protectionTimerFired(now: Date) {
        guard let task, isProtectionActive else { return }
        if now >= task.deadline {
            phase = .graceExpired
        } else {
            isProtectionActive = false
        }
    }

    mutating func close() {
        self = HoverCardSession()
    }
}

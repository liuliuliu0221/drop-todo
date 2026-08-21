import Foundation

enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case active
    case ruined
    case completed
    case recalled
}

enum Urgency: Int, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
}

enum TaskTag: String, Codable, Sendable, CaseIterable {
    case work
    case life
    case inspiration
}

struct TaskRecord: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    var deadline: Date
    var tag: TaskTag?
    var urgency: Urgency
    var status: TaskStatus
    var createdAt: Date
    var visualStartAt: Date
    var completedAt: Date?
    var ruinedAt: Date?
    var recalledAt: Date?
    var recalledFromID: UUID?
}

struct CreateTaskInput: Sendable, Equatable {
    var title: String
    var deadline: Date
    var tag: TaskTag?
    var urgency: Urgency = .medium
}

enum TaskTagChange: Sendable, Equatable {
    case unchanged
    case set(TaskTag?)
}

struct TaskChanges: Sendable, Equatable {
    var title: String?
    var deadline: Date?
    var tag: TaskTagChange
    var urgency: Urgency?

    init(
        title: String? = nil,
        deadline: Date? = nil,
        tag: TaskTagChange = .unchanged,
        urgency: Urgency? = nil
    ) {
        self.title = title
        self.deadline = deadline
        self.tag = tag
        self.urgency = urgency
    }
}

struct CompletionSnapshot: Sendable, Equatable {
    let taskID: UUID
    let completedAt: Date
    let tag: TaskTag?
    let urgency: Urgency
}

struct ExpirationSnapshot: Sendable, Equatable {
    let taskID: UUID
    let deadline: Date
    let ruinedAt: Date
}

enum TaskDomainError: Error, Sendable, Equatable, LocalizedError {
    case serviceNotStarted
    case taskNotFound(UUID)
    case titleEmpty
    case titleTooLong(maximum: Int)
    case deadlineTooSoon(minimum: Date)
    case invalidStatus(expected: TaskStatus, actual: TaskStatus)

    var errorDescription: String? {
        switch self {
        case .serviceNotStarted:
            "任务服务尚未完成启动。"
        case let .taskNotFound(id):
            "未找到任务 \(id.uuidString)。"
        case .titleEmpty:
            "任务名称不能为空。"
        case let .titleTooLong(maximum):
            "任务名称不能超过 \(maximum) 个字符。"
        case .deadlineTooSoon:
            "截止时间至少需要晚于当前时间 1 分钟。"
        case let .invalidStatus(expected, actual):
            "任务状态无效：需要 \(expected.rawValue)，当前为 \(actual.rawValue)。"
        }
    }
}

protocol NowProviding: Sendable {
    func now() -> Date
}

struct SystemNowProvider: NowProviding {
    func now() -> Date { Date() }
}

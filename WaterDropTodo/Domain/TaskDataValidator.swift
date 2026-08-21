import Foundation

enum TaskDataValidationError: Error, Sendable, Equatable, LocalizedError {
    case duplicateID(UUID)
    case invalidTitle(UUID)
    case missingLifecycleDate(taskID: UUID, status: TaskStatus)
    case invalidLifecycleDates(taskID: UUID, status: TaskStatus)
    case selfRecall(UUID)
    case danglingRecall(taskID: UUID, missingParentID: UUID)

    var errorDescription: String? {
        switch self {
        case let .duplicateID(id):
            "任务数据包含重复 ID：\(id.uuidString)。"
        case let .invalidTitle(id):
            "任务名称数据无效：\(id.uuidString)。"
        case let .missingLifecycleDate(id, status):
            "任务 \(id.uuidString) 缺少 \(status.rawValue) 状态时间。"
        case let .invalidLifecycleDates(id, status):
            "任务 \(id.uuidString) 的 \(status.rawValue) 状态时间互相冲突。"
        case let .selfRecall(id):
            "任务不能召回自自身：\(id.uuidString)。"
        case let .danglingRecall(id, parentID):
            "任务 \(id.uuidString) 的召回来源 \(parentID.uuidString) 不存在。"
        }
    }
}

enum TaskDataValidator {
    static func validate(_ records: [TaskRecord]) throws {
        var ids = Set<UUID>()
        for record in records {
            guard ids.insert(record.id).inserted else {
                throw TaskDataValidationError.duplicateID(record.id)
            }
            let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 100 else {
                throw TaskDataValidationError.invalidTitle(record.id)
            }
            try validateLifecycle(record)
            if record.recalledFromID == record.id {
                throw TaskDataValidationError.selfRecall(record.id)
            }
        }

        for record in records {
            if let parentID = record.recalledFromID, !ids.contains(parentID) {
                throw TaskDataValidationError.danglingRecall(
                    taskID: record.id,
                    missingParentID: parentID
                )
            }
        }
    }

    private static func validateLifecycle(_ record: TaskRecord) throws {
        switch record.status {
        case .active:
            guard record.completedAt == nil,
                  record.ruinedAt == nil,
                  record.recalledAt == nil else {
                throw TaskDataValidationError.invalidLifecycleDates(
                    taskID: record.id,
                    status: record.status
                )
            }
        case .completed:
            guard record.completedAt != nil else {
                throw TaskDataValidationError.missingLifecycleDate(
                    taskID: record.id,
                    status: record.status
                )
            }
            guard record.ruinedAt == nil, record.recalledAt == nil else {
                throw TaskDataValidationError.invalidLifecycleDates(
                    taskID: record.id,
                    status: record.status
                )
            }
        case .ruined:
            guard record.ruinedAt != nil else {
                throw TaskDataValidationError.missingLifecycleDate(
                    taskID: record.id,
                    status: record.status
                )
            }
            guard record.completedAt == nil, record.recalledAt == nil else {
                throw TaskDataValidationError.invalidLifecycleDates(
                    taskID: record.id,
                    status: record.status
                )
            }
        case .recalled:
            guard record.recalledAt != nil else {
                throw TaskDataValidationError.missingLifecycleDate(
                    taskID: record.id,
                    status: record.status
                )
            }
            guard record.completedAt == nil else {
                throw TaskDataValidationError.invalidLifecycleDates(
                    taskID: record.id,
                    status: record.status
                )
            }
        }
    }
}

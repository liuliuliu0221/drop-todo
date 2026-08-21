import Foundation
import Testing
@testable import WaterDropTodo

struct TaskDataValidatorTests {
    @Test func rejectsDuplicateIDsBeforeDictionaryConstruction() throws {
        let record = makeRecord()
        #expect(throws: TaskDataValidationError.duplicateID(record.id)) {
            try TaskDataValidator.validate([record, record])
        }
    }

    @Test func requiresLifecycleTimestampForTerminalStatus() throws {
        var record = makeRecord()
        record.status = .completed
        #expect(throws: TaskDataValidationError.missingLifecycleDate(
            taskID: record.id,
            status: .completed
        )) {
            try TaskDataValidator.validate([record])
        }
    }

    @Test func rejectsDanglingAndSelfRecallLinks() throws {
        var dangling = makeRecord()
        let missing = UUID()
        dangling.recalledFromID = missing
        #expect(throws: TaskDataValidationError.danglingRecall(
            taskID: dangling.id,
            missingParentID: missing
        )) {
            try TaskDataValidator.validate([dangling])
        }

        var selfLinked = makeRecord()
        selfLinked.recalledFromID = selfLinked.id
        #expect(throws: TaskDataValidationError.selfRecall(selfLinked.id)) {
            try TaskDataValidator.validate([selfLinked])
        }
    }

    private func makeRecord() -> TaskRecord {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return TaskRecord(
            id: UUID(),
            title: "有效任务",
            deadline: now.addingTimeInterval(600),
            tag: .work,
            urgency: .medium,
            status: .active,
            createdAt: now,
            visualStartAt: now,
            completedAt: nil,
            ruinedAt: nil,
            recalledAt: nil,
            recalledFromID: nil
        )
    }
}

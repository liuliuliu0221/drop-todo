import Foundation
import Testing
@testable import WaterDropTodo

struct TimeEngineTests {
    @Test func nextDeadlineIgnoresPastAndNonActiveTasks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = record(deadline: now.addingTimeInterval(-1), status: .active)
        let completed = record(deadline: now.addingTimeInterval(10), status: .completed)
        let later = record(deadline: now.addingTimeInterval(300), status: .active)
        let nearest = record(deadline: now.addingTimeInterval(120), status: .active)

        #expect(TimeEngine.nextDeadline(in: [past, completed, later, nearest], after: now) == nearest.deadline)
    }

    @Test func nextDeadlineReturnsNilWithoutFutureActiveTask() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(
            TimeEngine.nextDeadline(
                in: [record(deadline: now, status: .ruined)],
                after: now
            ) == nil
        )
    }

    @Test func nextDeadlineIgnoresProtectedTask() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let protected = record(deadline: now.addingTimeInterval(60), status: .active)
        let next = record(deadline: now.addingTimeInterval(120), status: .active)

        #expect(
            TimeEngine.nextDeadline(
                in: [protected, next],
                after: now,
                excluding: [protected.id]
            ) == next.deadline
        )
    }

    private func record(deadline: Date, status: TaskStatus) -> TaskRecord {
        TaskRecord(
            id: UUID(),
            title: "时间测试",
            deadline: deadline,
            tag: nil,
            urgency: .medium,
            status: status,
            createdAt: deadline.addingTimeInterval(-600),
            visualStartAt: deadline.addingTimeInterval(-600),
            completedAt: status == .completed ? deadline : nil,
            ruinedAt: status == .ruined ? deadline : nil,
            recalledAt: nil,
            recalledFromID: nil
        )
    }
}

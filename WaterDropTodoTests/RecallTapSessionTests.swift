import Foundation
import Testing
@testable import WaterDropTodo

struct RecallTapSessionTests {
    @Test func tenConsecutiveTapsReachRecallThreshold() {
        var session = RecallTapSession()
        let taskID = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<10 {
            session.registerTap(taskID: taskID, at: start.addingTimeInterval(Double(index) * 0.5))
        }
        #expect(session.taskID == taskID)
        #expect(session.clickCount == 10)
    }

    @Test func timeoutOrDifferentTaskResetsProgress() {
        var session = RecallTapSession()
        let first = UUID()
        let second = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        session.registerTap(taskID: first, at: start)
        session.registerTap(taskID: first, at: start.addingTimeInterval(1.01))
        #expect(session.clickCount == 1)
        session.registerTap(taskID: second, at: start.addingTimeInterval(1.2))
        #expect(session.taskID == second)
        #expect(session.clickCount == 1)
    }
}

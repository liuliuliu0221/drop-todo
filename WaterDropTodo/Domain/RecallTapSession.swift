import Foundation

struct RecallTapSession: Sendable, Equatable {
    static let requiredTapCount = 10
    static let maximumTapGap: TimeInterval = 1

    private(set) var taskID: UUID?
    private(set) var clickCount = 0
    private(set) var lastClickInstant: Date?

    @discardableResult
    mutating func registerTap(taskID: UUID, at instant: Date) -> Int {
        let continuesSession = self.taskID == taskID
            && lastClickInstant.map { instant.timeIntervalSince($0) <= Self.maximumTapGap } == true
        if !continuesSession {
            self.taskID = taskID
            clickCount = 0
        }
        clickCount = min(Self.requiredTapCount, clickCount + 1)
        lastClickInstant = instant
        return clickCount
    }

    mutating func reset() {
        taskID = nil
        clickCount = 0
        lastClickInstant = nil
    }
}

import Foundation
import Testing
@testable import WaterDropTodo

struct HoverCardSessionTests {
    @Test func hoverFreezesCountdownAndProtectsTheTask() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = record(deadline: now.addingTimeInterval(90))
        var session = HoverCardSession()

        session.begin(task: task, now: now)

        #expect(session.phase == .hoverPending)
        #expect(session.frozenRemainingTime == 90)
        #expect(session.protectedTaskIDs == [task.id])
        #expect(session.protectionEndsAt == now.addingTimeInterval(60))
    }

    @Test func presentationCanBePinnedAndCloseReleasesProtection() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = record(deadline: now.addingTimeInterval(90))
        var session = HoverCardSession()

        session.begin(task: task, now: now)
        session.present()
        #expect(session.phase == .presented)
        session.pin()
        #expect(session.phase == .pinned)
        #expect(session.isCompletionEnabled)

        session.close()
        #expect(session.phase == .idle)
        #expect(session.protectedTaskIDs.isEmpty)
    }

    @Test func protectionEndsAfterSixtySecondsWhenDeadlineIsStillFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var session = HoverCardSession()
        session.begin(task: record(deadline: now.addingTimeInterval(300)), now: now)
        session.present()

        session.protectionTimerFired(now: now.addingTimeInterval(60))

        #expect(session.phase == .presented)
        #expect(session.protectedTaskIDs.isEmpty)
        #expect(session.isCompletionEnabled)
    }

    @Test func overdueTaskEntersGraceExpiredUntilTheCardCloses() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = record(deadline: now.addingTimeInterval(30))
        var session = HoverCardSession()
        session.begin(task: task, now: now)
        session.present()

        session.protectionTimerFired(now: now.addingTimeInterval(60))

        #expect(session.phase == .graceExpired)
        #expect(session.protectedTaskIDs == [task.id])
        #expect(!session.isCompletionEnabled)
        session.close()
        #expect(session.protectedTaskIDs.isEmpty)
    }

    @Test func timingConstantsMatchTheInteractionContract() {
        #expect(HoverCardSession.presentationDelay == 0.15)
        #expect(HoverCardSession.dismissalDelay == 0.25)
        #expect(HoverCardSession.maximumProtectionDuration == 60)
    }

    private func record(deadline: Date) -> TaskRecord {
        TaskRecord(
            id: UUID(),
            title: "悬停任务",
            deadline: deadline,
            tag: .work,
            urgency: .medium,
            status: .active,
            createdAt: deadline.addingTimeInterval(-600),
            visualStartAt: deadline.addingTimeInterval(-600),
            completedAt: nil,
            ruinedAt: nil,
            recalledAt: nil,
            recalledFromID: nil
        )
    }
}

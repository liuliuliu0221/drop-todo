import CoreGraphics
import Foundation
import Testing
@testable import WaterDropTodo

struct NotchLayoutTests {
    private let engine = NotchLayoutEngine()
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func remainingTimeColorProgressUsesSevenFixedBands() {
        let cases: [(TimeInterval, Float)] = [
            (24 * 60 * 60 + 1, 0.02),
            (24 * 60 * 60, 0.10),
            (12 * 60 * 60 + 1, 0.10),
            (12 * 60 * 60, 0.20),
            (6 * 60 * 60 + 1, 0.20),
            (6 * 60 * 60, 0.32),
            (3 * 60 * 60 + 1, 0.32),
            (3 * 60 * 60, 0.46),
            (60 * 60 + 1, 0.46),
            (60 * 60, 0.62),
            (30 * 60 + 1, 0.62),
            (30 * 60, 0.82),
            (0, 0.82),
            (-1, 0.82)
        ]

        for (remainingTime, expectedProgress) in cases {
            #expect(NotchLayoutEngine.remainingTimeColorProgress(
                deadline: now.addingTimeInterval(remainingTime),
                now: now
            ) == expectedProgress)
        }
    }

    @Test func importanceDoesNotAffectPositionOrColorProgress() {
        let taskID = deterministicID(0)
        let low = makeTask(
            id: taskID,
            urgency: .low,
            start: now.addingTimeInterval(-50),
            deadline: now.addingTimeInterval(50)
        )
        let high = makeTask(
            id: taskID,
            urgency: .high,
            start: now.addingTimeInterval(-50),
            deadline: now.addingTimeInterval(50)
        )
        let lowItem = engine.snapshot(tasks: [low], now: now, contentWidth: 178).items.first
        let highItem = engine.snapshot(tasks: [high], now: now, contentWidth: 178).items.first

        #expect(lowItem?.resolvedX == highItem?.resolvedX)
        #expect(lowItem?.colorProgress == 0.82)
        #expect(highItem?.colorProgress == 0.82)
        #expect(lowItem?.importance == .low)
        #expect(highItem?.importance == .high)
    }

    @Test func startTimeDoesNotAffectColorProgress() {
        let taskID = deterministicID(0)
        let recent = makeTask(
            id: taskID,
            start: now.addingTimeInterval(-60),
            deadline: now.addingTimeInterval(2 * 60 * 60)
        )
        let old = makeTask(
            id: taskID,
            start: now.addingTimeInterval(-30 * 24 * 60 * 60),
            deadline: now.addingTimeInterval(2 * 60 * 60)
        )

        let recentColor = engine.snapshot(
            tasks: [recent],
            now: now,
            contentWidth: 178
        ).items.first?.colorProgress
        let oldColor = engine.snapshot(
            tasks: [old],
            now: now,
            contentWidth: 178
        ).items.first?.colorProgress
        #expect(recentColor == 0.46)
        #expect(oldColor == recentColor)
    }

    @Test func earlierDeadlinesAreNeverLighterAcrossAllBands() {
        let remainingTimes: [TimeInterval] = [
            48 * 60 * 60,
            18 * 60 * 60,
            8 * 60 * 60,
            4 * 60 * 60,
            2 * 60 * 60,
            45 * 60,
            15 * 60
        ]
        let tasks = remainingTimes.enumerated().map { index, remainingTime in
            makeTask(
                id: deterministicID(index),
                start: now.addingTimeInterval(-Double(index + 1) * 10_000),
                deadline: now.addingTimeInterval(remainingTime)
            )
        }

        let snapshot = engine.snapshot(tasks: tasks, now: now, contentWidth: 178)
        let colors = snapshot.items.map(\.colorProgress)
        #expect(colors == [0.02, 0.10, 0.20, 0.32, 0.46, 0.62, 0.82])
        for pair in zip(colors, colors.dropFirst()) {
            #expect(pair.0 <= pair.1)
        }
    }

    @Test func supportsRequiredVisibleTaskCountsAndCapsAtEight() {
        for count in [0, 1, 3, 5, 8, 9] {
            let tasks = (0..<count).map { index in
                makeTask(
                    id: deterministicID(index),
                    start: now.addingTimeInterval(-60),
                    deadline: now.addingTimeInterval(Double(index + 1) * 60)
                )
            }
            let snapshot = engine.snapshot(tasks: tasks, now: now, contentWidth: 178)
            #expect(snapshot.items.count == min(count, 8))
        }
    }

    @Test func nineTasksSelectTheEightEarliestDeadlines() {
        let tasks = (0..<9).map { index in
            makeTask(
                id: deterministicID(index),
                start: now,
                deadline: now.addingTimeInterval(Double(9 - index) * 60)
            )
        }
        let latestID = deterministicID(0)
        let snapshot = engine.snapshot(tasks: Array(tasks.reversed()), now: now, contentWidth: 178)

        #expect(snapshot.items.count == 8)
        #expect(!snapshot.items.contains { $0.id == latestID })
    }

    @Test func earlierDeadlineIsAlwaysFartherRight() {
        let earliest = makeTask(
            id: deterministicID(0),
            urgency: .low,
            start: now,
            deadline: now.addingTimeInterval(60)
        )
        let middle = makeTask(
            id: deterministicID(1),
            urgency: .high,
            start: now,
            deadline: now.addingTimeInterval(120)
        )
        let latest = makeTask(
            id: deterministicID(2),
            urgency: .high,
            start: now.addingTimeInterval(-10_000),
            deadline: now.addingTimeInterval(180)
        )
        let snapshot = engine.snapshot(
            tasks: [earliest, latest, middle],
            now: now,
            contentWidth: 178
        )

        #expect(snapshot.items.map(\.id) == [latest.id, middle.id, earliest.id])
        let positions = snapshot.items.map(\.resolvedX)
        #expect(positions[0] < positions[1])
        #expect(positions[1] < positions[2])
        let colors = snapshot.items.map(\.colorProgress)
        #expect(colors[0] <= colors[1])
        #expect(colors[1] <= colors[2])
    }

    @Test func hoveredTaskKeepsItsIdentityWhenItWouldLeaveTheFirstEight() {
        let tasks = (0..<9).map { index in
            makeTask(
                id: deterministicID(index),
                start: now,
                deadline: now.addingTimeInterval(Double(index + 1) * 60)
            )
        }
        let fixedID = deterministicID(8)
        let snapshot = engine.snapshot(
            tasks: tasks,
            now: now,
            contentWidth: 178,
            fixedTaskIDs: [fixedID]
        )

        #expect(snapshot.items.count == 8)
        #expect(snapshot.items.contains { $0.id == fixedID })
        #expect(!snapshot.items.contains { $0.id == deterministicID(7) })
    }

    @Test func eightDropletsStayInsideBoundsWithMinimumSpacing() {
        let tasks = (0..<8).map { index in
            makeTask(
                id: deterministicID(index),
                urgency: .high,
                start: now.addingTimeInterval(-99),
                deadline: now.addingTimeInterval(1)
            )
        }
        let snapshot = engine.snapshot(tasks: tasks, now: now, contentWidth: 178)
        let positions = snapshot.items.map(\.resolvedX)

        #expect(positions.allSatisfy { (12...166).contains($0) })
        for pair in zip(positions, positions.dropFirst()) {
            #expect(pair.1 - pair.0 >= NotchLayoutEngine.minimumSpacing)
        }
    }

    @Test func fourDropletsUseStableNonUniformSpacing() {
        let tasks = (0..<4).map { index in
            makeTask(
                id: deterministicID(index),
                start: now,
                deadline: now.addingTimeInterval(Double(index + 1) * 60)
            )
        }

        let first = engine.snapshot(tasks: tasks, now: now, contentWidth: 178)
        let second = engine.snapshot(tasks: tasks, now: now.addingTimeInterval(1), contentWidth: 178)
        let positions = first.items.map(\.resolvedX)
        let gaps = zip(positions, positions.dropFirst()).map { $1 - $0 }

        #expect(first.items.map(\.resolvedX) == second.items.map(\.resolvedX))
        #expect(Set(gaps.map { Int(($0 * 100).rounded()) }).count > 1)
        #expect(gaps.allSatisfy { $0 >= NotchLayoutEngine.minimumSpacing })
    }

    @Test func sameDeadlineLayoutIsDeterministicAndPreservesIdentity() {
        let tasks = (0..<5).map { index in
            makeTask(
                id: deterministicID(index),
                urgency: index.isMultiple(of: 2) ? .low : .high,
                start: now.addingTimeInterval(-100),
                deadline: now.addingTimeInterval(100)
            )
        }

        let forward = engine.snapshot(tasks: tasks, now: now, contentWidth: 178)
        let reverse = engine.snapshot(tasks: Array(tasks.reversed()), now: now, contentWidth: 178)
        #expect(forward.items == reverse.items)
    }

    @Test func inactiveTasksNeverEnterTheNotchSnapshot() {
        var ruined = makeTask(start: now, deadline: now.addingTimeInterval(60))
        ruined.status = .ruined
        let active = makeTask(
            id: deterministicID(1),
            start: now,
            deadline: now.addingTimeInterval(120)
        )

        let snapshot = engine.snapshot(tasks: [ruined, active], now: now, contentWidth: 178)
        #expect(snapshot.items.map(\.id) == [active.id])
    }

    @Test func liquidThemeUsesAdaptiveRadiusAndImportanceLengthOnly() {
        let theme = LiquidTheme.notch

        #expect(theme.radius(forDropletCount: 1) == 0.065)
        #expect(theme.radius(forDropletCount: 3) == 0.065)
        #expect(theme.radius(forDropletCount: 4) == 0.057)
        #expect(theme.radius(forDropletCount: 5) == 0.057)
        #expect(theme.radius(forDropletCount: 6) == 0.050)
        #expect(theme.radius(forDropletCount: 8) == 0.050)
        #expect(theme.hoverScale == 1.25)
        #expect(theme.halfLength(for: .low) == 0.028)
        #expect(theme.halfLength(for: .medium) == 0.0505)
        #expect(theme.halfLength(for: .high) == 0.070)
        #expect(theme.halfLength(for: .medium) - theme.halfLength(for: .low) > 0.022)
        #expect(theme.halfLength(for: .high) - theme.halfLength(for: .medium) > 0.019)
    }

    @Test func allImportanceLengthsShareTheSameSurfaceAttachment() {
        let theme = LiquidTheme.notch
        let importanceLevels: [Urgency] = [.low, .medium, .high]
        let attachmentPoints = importanceLevels.map { importance in
            let halfLength = theme.halfLength(for: importance)
            return theme.centerY(forHalfLength: halfLength) - halfLength
        }

        #expect(abs(attachmentPoints[0] - attachmentPoints[1]) < 0.0001)
        #expect(abs(attachmentPoints[1] - attachmentPoints[2]) < 0.0001)
        #expect(theme.centerY(forHalfLength: theme.highImportanceHalfLength) == theme.dropletY)
    }

    private func makeTask(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        urgency: Urgency = .low,
        start: Date,
        deadline: Date
    ) -> TaskRecord {
        TaskRecord(
            id: id,
            title: "布局测试",
            deadline: deadline,
            tag: .work,
            urgency: urgency,
            status: .active,
            createdAt: start,
            visualStartAt: start,
            completedAt: nil,
            ruinedAt: nil,
            recalledAt: nil,
            recalledFromID: nil
        )
    }

    private func deterministicID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
    }
}

import CoreGraphics
import Foundation

struct NotchLayoutItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let deadline: Date
    let colorProgress: Float
    let importance: Urgency
    let idealX: CGFloat
    let resolvedX: CGFloat
}

struct NotchLayoutSnapshot: Sendable, Equatable {
    let generatedAt: Date
    let contentWidth: CGFloat
    let items: [NotchLayoutItem]

    static func empty(at date: Date, contentWidth: CGFloat) -> Self {
        Self(generatedAt: date, contentWidth: contentWidth, items: [])
    }
}

struct NotchLayoutEngine: Sendable {
    static let maximumVisibleTasks = 8
    static let hitTargetWidth: CGFloat = 24
    static let minimumSpacing: CGFloat = 19

    func snapshot(
        tasks: [TaskRecord],
        now: Date,
        contentWidth: CGFloat,
        fixedTaskIDs: Set<UUID> = []
    ) -> NotchLayoutSnapshot {
        let width = max(contentWidth, Self.hitTargetWidth)
        let minimumX = Self.hitTargetWidth / 2
        let maximumX = width - Self.hitTargetWidth / 2
        let sortedActiveTasks = tasks
            .filter { $0.status == .active }
            .sorted(by: taskSelectionOrder)
        let fixedTasks = sortedActiveTasks.filter { fixedTaskIDs.contains($0.id) }
        let regularTasks = sortedActiveTasks.filter { !fixedTaskIDs.contains($0.id) }
        let selectedTasks = Array(fixedTasks.prefix(Self.maximumVisibleTasks))
            + Array(regularTasks.prefix(Self.maximumVisibleTasks - min(fixedTasks.count, Self.maximumVisibleTasks)))
        let visibleTasks = selectedTasks.sorted(by: layoutPositionOrder)
        let positions = Self.stableDeadlinePositions(
            tasks: visibleTasks,
            minimumX: minimumX,
            maximumX: maximumX
        )

        let items = zip(visibleTasks, positions).map { task, position in
            let colorProgress = Self.remainingTimeColorProgress(
                deadline: task.deadline,
                now: now
            )
            return NotchLayoutItem(
                id: task.id,
                deadline: task.deadline,
                colorProgress: colorProgress,
                importance: task.urgency,
                idealX: position,
                resolvedX: position
            )
        }
        return NotchLayoutSnapshot(generatedAt: now, contentWidth: width, items: items)
    }

    static func remainingTimeColorProgress(deadline: Date, now: Date) -> Float {
        switch deadline.timeIntervalSince(now) {
        case ...(30 * 60): 0.82
        case ...(60 * 60): 0.62
        case ...(3 * 60 * 60): 0.46
        case ...(6 * 60 * 60): 0.32
        case ...(12 * 60 * 60): 0.20
        case ...(24 * 60 * 60): 0.10
        default: 0.02
        }
    }

    static func stableDeadlinePositions(
        tasks: [TaskRecord],
        minimumX: CGFloat,
        maximumX: CGFloat
    ) -> [CGFloat] {
        let count = tasks.count
        guard count > 0 else { return [] }
        guard count > 1 else { return [(minimumX + maximumX) / 2] }

        let range = max(maximumX - minimumX, 0)
        let gapCount = count - 1
        let minimumGap = min(Self.minimumSpacing, range / CGFloat(gapCount))
        let freeSpace = max(range - minimumGap * CGFloat(gapCount), 0)

        // UUID-derived weights keep the layout visually irregular without changing
        // on every one-second color refresh. Internal gaps receive more weight than
        // the edge margins so the droplets continue to use the notch width well.
        var weights: [CGFloat] = []
        weights.reserveCapacity(count + 1)
        weights.append(0.25 + 0.35 * stableUnitValue(for: tasks[0].id, salt: 0))
        for index in 1..<count {
            let salt = UInt64(index) &* 0x9E37_79B9_7F4A_7C15
            weights.append(0.45 + 1.10 * stableUnitValue(for: tasks[index].id, salt: salt))
        }
        weights.append(0.25 + 0.35 * stableUnitValue(for: tasks[count - 1].id, salt: UInt64.max))

        let totalWeight = weights.reduce(0, +)
        var cursor = minimumX + freeSpace * weights[0] / totalWeight
        var positions = [cursor]
        positions.reserveCapacity(count)
        for index in 1..<count {
            cursor += minimumGap + freeSpace * weights[index] / totalWeight
            positions.append(cursor)
        }
        return positions
    }

    private static func stableUnitValue(for id: UUID, salt: UInt64) -> CGFloat {
        var hash: UInt64 = 1_469_598_103_934_665_603 ^ salt
        var uuid = id.uuid
        withUnsafeBytes(of: &uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 1_099_511_628_211
            }
        }
        hash ^= hash >> 33
        hash = hash &* 0xFF51_AFD7_ED55_8CCD
        hash ^= hash >> 33
        return CGFloat(hash % 10_000) / 9_999
    }

    private func taskSelectionOrder(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        if lhs.deadline != rhs.deadline { return lhs.deadline < rhs.deadline }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func layoutPositionOrder(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        if lhs.deadline != rhs.deadline { return lhs.deadline > rhs.deadline }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

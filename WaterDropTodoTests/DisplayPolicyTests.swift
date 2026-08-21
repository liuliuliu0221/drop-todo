import CoreGraphics
import Foundation
import Testing
@testable import WaterDropTodo

struct DisplayPolicyTests {
    private let policy = DisplayPolicy()

    @Test func singleNotchDisplayIsVisible() {
        let snapshot = DisplaySnapshot(displayCount: 1, hasNotch: true, isMirrored: false)
        #expect(policy.visibility(for: snapshot) == .visible)
    }

    @Test func noNotchIsUnsupported() {
        let snapshot = DisplaySnapshot(displayCount: 1, hasNotch: false, isMirrored: false)
        #expect(policy.visibility(for: snapshot) == .unsupportedNoNotch)
    }

    @Test func multipleDisplaysPauseNotchWindows() {
        let snapshot = DisplaySnapshot(displayCount: 2, hasNotch: true, isMirrored: false)
        #expect(policy.visibility(for: snapshot) == .multipleDisplays)
    }

    @Test func mirroringTakesPriorityOverDisplayCount() {
        let snapshot = DisplaySnapshot(displayCount: 2, hasNotch: true, isMirrored: true)
        #expect(policy.visibility(for: snapshot) == .mirroredDisplay)
    }

    @Test func fullscreenPreferenceHidesNotchWindows() {
        let snapshot = DisplaySnapshot(displayCount: 1, hasNotch: true, isMirrored: false)
        #expect(policy.visibility(for: snapshot, hideInFullscreen: true) == .hiddenByFullscreenPreference)
    }

    @Test func nearestHitTargetUsesCenterDistance() {
        let left = DropletHitTarget(
            id: UUID(),
            index: 0,
            frame: CGRect(x: 0, y: 0, width: 20, height: 20)
        )
        let right = DropletHitTarget(
            id: UUID(),
            index: 1,
            frame: CGRect(x: 16, y: 0, width: 20, height: 20)
        )

        let selected = HitTestCoordinator.nearestTarget(
            to: CGPoint(x: 22, y: 10),
            among: [left, right]
        )
        #expect(selected?.id == right.id)
    }

    @Test func overlappingHitTargetsAreSplitAtTheCenterMidpoint() {
        let left = DropletHitTarget(
            id: UUID(),
            index: 0,
            frame: CGRect(x: 0, y: 0, width: 25, height: 25)
        )
        let right = DropletHitTarget(
            id: UUID(),
            index: 1,
            frame: CGRect(x: 19, y: 0, width: 25, height: 25)
        )

        let resolved = HitTestCoordinator.disambiguatedTargets([left, right])

        #expect(resolved.count == 2)
        #expect(resolved[0].frame.maxX == resolved[1].frame.minX)
        #expect(resolved[0].frame.maxX == 22)
    }
}

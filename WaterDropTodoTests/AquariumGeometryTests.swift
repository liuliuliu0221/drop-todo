import CoreGraphics
import Testing
@testable import WaterDropTodo

struct AquariumGeometryTests {
    @Test func defaultFrameUsesRequiredSizeAndBottomRightInset() {
        let visible = CGRect(x: 0, y: 24, width: 1_440, height: 876)
        let frame = AquariumPlacementGeometry.defaultFrame(in: visible)

        #expect(frame.size == CGSize(width: 180, height: 110))
        #expect(frame.maxX == visible.maxX - 16)
        #expect(frame.minY == visible.minY + 16)
    }

    @Test func normalizedPlacementRoundTripsAcrossVisibleFrames() {
        let firstScreen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = CGRect(x: 510, y: 230, width: 180, height: 110)
        let normalized = AquariumPlacementGeometry.normalizedOrigin(
            of: frame,
            in: firstScreen
        )
        let secondScreen = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let restored = AquariumPlacementGeometry.frame(
            normalizedOrigin: normalized,
            in: secondScreen
        )

        let restoredNormalized = AquariumPlacementGeometry.normalizedOrigin(
            of: restored,
            in: secondScreen
        )
        #expect(abs(restoredNormalized.x - normalized.x) < 0.0001)
        #expect(abs(restoredNormalized.y - normalized.y) < 0.0001)
    }

    @Test func clampingKeepsAquariumInsideVisibleFrame() {
        let visible = CGRect(x: 100, y: 50, width: 800, height: 600)
        let outside = CGRect(x: 850, y: -100, width: 180, height: 110)
        let result = AquariumPlacementGeometry.clamped(outside, to: visible)

        #expect(result.maxX <= visible.maxX)
        #expect(result.minY >= visible.minY)
    }

    @Test func transitionPolicyRespectsVisibilityAndReduceMotion() {
        #expect(TransitionAnimationPolicy.mode(aquariumIsVisible: true, reduceMotion: false) == .travel)
        #expect(TransitionAnimationPolicy.mode(aquariumIsVisible: false, reduceMotion: false) == .fadeAtSource)
        #expect(TransitionAnimationPolicy.mode(aquariumIsVisible: true, reduceMotion: true) == .fadeAtSource)
    }
}

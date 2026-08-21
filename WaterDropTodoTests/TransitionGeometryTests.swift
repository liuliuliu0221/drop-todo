import CoreGraphics
import Testing
@testable import WaterDropTodo

struct TransitionGeometryTests {
    @Test func routeInterpolatesAlongStraightLine() {
        let route = TransitionRoute(
            start: CGPoint(x: 10, y: 20),
            target: CGPoint(x: 110, y: 220)
        )

        #expect(route.point(at: 0) == CGPoint(x: 10, y: 20))
        #expect(route.point(at: 0.5) == CGPoint(x: 60, y: 120))
        #expect(route.point(at: 1) == CGPoint(x: 110, y: 220))
    }

    @Test func routeClampsProgress() {
        let route = TransitionRoute(start: .zero, target: CGPoint(x: 10, y: 10))
        #expect(route.point(at: -1) == .zero)
        #expect(route.point(at: 2) == CGPoint(x: 10, y: 10))
    }

    @Test func screenToOverlayConversionHandlesNonZeroOriginAndScale() {
        let space = TransitionCoordinateSpace(
            overlayFrame: CGRect(x: -1440, y: 0, width: 3168, height: 1117),
            backingScale: 2
        )
        let local = space.localPoint(fromScreenPoint: CGPoint(x: -100.24, y: 300.26))

        #expect(local == CGPoint(x: 1340, y: 300.5))
    }

    @Test func pixelAlignmentKeepsEndpointErrorWithinHalfPixelPerAxis() {
        let space = TransitionCoordinateSpace(
            overlayFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            backingScale: 2
        )
        let expected = CGPoint(x: 1635.26, y: 92.24)
        let rendered = space.localPoint(fromScreenPoint: expected)
        let error = space.endpointError(
            renderedLocalPoint: rendered,
            expectedScreenPoint: expected
        )

        #expect(error <= 0.36)
    }

    @Test func transitionPolicyUsesReducedMotionFallback() {
        #expect(TransitionAnimationPolicy.mode(reduceMotion: false) == .travel)
        #expect(TransitionAnimationPolicy.mode(reduceMotion: true) == .fadeAtSource)
    }
}

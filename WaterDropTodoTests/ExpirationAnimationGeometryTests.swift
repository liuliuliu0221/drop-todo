import CoreGraphics
import Testing
@testable import WaterDropTodo

struct ExpirationAnimationGeometryTests {
    @Test func animationStretchesBeforeFallingBelowScreen() {
        let source = CGPoint(x: 100, y: 900)
        let start = ExpirationAnimationGeometry.frame(source: source, bottomY: -32, progress: 0)
        let stretched = ExpirationAnimationGeometry.frame(source: source, bottomY: -32, progress: 0.4)
        let end = ExpirationAnimationGeometry.frame(source: source, bottomY: -32, progress: 1)

        #expect(start.point == source)
        #expect(stretched.height > start.height)
        #expect(end.point.y == -32)
        #expect(end.alpha == 0)
    }
}

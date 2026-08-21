import CoreGraphics
import Testing
@testable import WaterDropTodo

struct CompletionGardenAnimationTests {
    @Test func completedDropletFallsVerticallyAndAccelerates() {
        let source = CGPoint(x: 400, y: 800)
        let impact = CGPoint(x: 400, y: 20)
        let start = CompletionFallGeometry.frame(source: source, impact: impact, progress: 0)
        let quarter = CompletionFallGeometry.frame(source: source, impact: impact, progress: 0.25)
        let halfway = CompletionFallGeometry.frame(source: source, impact: impact, progress: 0.5)
        let end = CompletionFallGeometry.frame(source: source, impact: impact, progress: 1)

        #expect(start.point == source)
        #expect(end.point == impact)
        #expect(quarter.point.x == source.x)
        #expect(halfway.point.x == source.x)
        #expect(source.y - quarter.point.y < quarter.point.y - halfway.point.y)
        #expect(halfway.height > start.height)
    }

    @Test func splashTrajectoryStartsAndEndsOnGroundAndArcsUpward() {
        let trajectory = SplashParticleTrajectory(
            start: CGPoint(x: 500, y: 20),
            target: CGPoint(x: 800, y: 20),
            arcHeight: 60,
            radius: 3
        )

        #expect(trajectory.point(at: 0) == trajectory.start)
        #expect(trajectory.point(at: 1) == trajectory.target)
        #expect(trajectory.point(at: 0.5) == CGPoint(x: 650, y: 80))
    }

    @Test func geometryClampsProgress() {
        let source = CGPoint(x: 0, y: 100)
        let impact = CGPoint(x: 0, y: 0)
        #expect(CompletionFallGeometry.frame(source: source, impact: impact, progress: -1).point == source)
        #expect(CompletionFallGeometry.frame(source: source, impact: impact, progress: 2).point == impact)
    }

    @Test func gardenAndImpactUsePhysicalScreenBottomInsteadOfDockSafeArea() {
        let screenFrame = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let gardenFrame = GardenScreenGeometry.panelFrame(for: screenFrame)
        let impact = CompletionFallGeometry.impactPoint(screenFrame: screenFrame, normalizedX: 0.25)

        #expect(gardenFrame == CGRect(x: -1440, y: 0, width: 1440, height: 64))
        #expect(impact == CGPoint(x: 360, y: 3))
    }

    @Test func pointerPushesNearbyGrassAwayAndIgnoresDistantOrEmptyCells() {
        let pointer = CGPoint(x: 100, y: 14)
        let grassOnRight = GardenPointerInteraction.targetSway(
            cellCenterX: 112,
            pointer: pointer,
            hasGrass: true
        )
        let grassOnLeft = GardenPointerInteraction.targetSway(
            cellCenterX: 88,
            pointer: pointer,
            hasGrass: true
        )

        #expect(grassOnRight > 0)
        #expect(grassOnLeft < 0)
        #expect(GardenPointerInteraction.targetSway(
            cellCenterX: 160,
            pointer: pointer,
            hasGrass: true
        ) == 0)
        #expect(GardenPointerInteraction.targetSway(
            cellCenterX: 112,
            pointer: pointer,
            hasGrass: false
        ) == 0)
        #expect(GardenPointerInteraction.targetSway(
            cellCenterX: 112,
            pointer: CGPoint(x: 100, y: 48),
            hasGrass: true
        ) == 0)
    }
}

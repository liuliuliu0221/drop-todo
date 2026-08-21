import Foundation
import Testing
@testable import WaterDropTodo

struct GardenDistributionTests {
    @Test func sameCompletionProducesStableLandingPlan() {
        let taskID = UUID(uuidString: "7F6BE6B8-44EF-4BFD-A9E9-5B384FEA7F21")!
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cells = GardenState.empty().cells

        let first = GardenDistribution.makePlan(
            taskID: taskID,
            completedAt: completedAt,
            impactNormalizedX: 0.5,
            cells: cells
        )
        let second = GardenDistribution.makePlan(
            taskID: taskID,
            completedAt: completedAt,
            impactNormalizedX: 0.5,
            cells: cells
        )

        #expect(first == second)
        #expect(
            (GardenConstants.minimumLandingCount...GardenConstants.maximumLandingCount)
                .contains(first.landingPositions.count)
        )
        #expect(first.landingPositions.allSatisfy { (0...1).contains($0) })
        #expect(first.cellDeltas.allSatisfy {
            (0..<GardenConstants.cellCount).contains($0.cellIndex) && $0.amount > 0
        })
    }

    @Test func impactPositionIsClampedToScreenBounds() {
        let cells = GardenState.empty().cells
        let plan = GardenDistribution.makePlan(
            taskID: UUID(uuidString: "131D5B18-31CB-4075-BF23-92519971A6D6")!,
            completedAt: Date(timeIntervalSince1970: 1_800_000_100),
            impactNormalizedX: 4,
            cells: cells
        )

        #expect(plan.landingPositions.allSatisfy { (0...1).contains($0) })
    }

    @Test func sparseSamplingFavorsTheOnlyEmptyCell() {
        var cells = GardenState.empty().cells
        for index in cells.indices { cells[index].density = .max }
        let emptyIndex = 37
        cells[emptyIndex].density = 0

        let plan = GardenDistribution.makePlan(
            taskID: UUID(uuidString: "F51B4499-9D14-47D1-A99A-FB62A2C2A76B")!,
            completedAt: Date(timeIntervalSince1970: 1_800_000_200),
            impactNormalizedX: 0.5,
            cells: cells
        )
        let last = plan.landingPositions.last ?? -1
        let selectedIndex = min(
            Int(last * Double(GardenConstants.cellCount)),
            GardenConstants.cellCount - 1
        )

        #expect(selectedIndex == emptyIndex)
    }

    @Test func snapshotMeasuresCoverageAndMaximumGap() {
        var cells = GardenState.empty().cells
        cells[0].density = 1
        cells[3].density = 1
        let snapshot = GardenSnapshot(totalCompletions: 2, cells: cells)

        #expect(snapshot.coverageFraction == 2.0 / Double(GardenConstants.cellCount))
        #expect(snapshot.maximumEmptyRun == GardenConstants.cellCount - 4)
    }

    @Test func fiveHundredCompletionsConvergeToAContinuousDenseEdge() {
        var cells = GardenState.empty().cells
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<500 {
            let taskID = UUID(
                uuidString: String(format: "00000000-0000-0000-0000-%012llX", index + 1)
            )!
            let plan = GardenDistribution.makePlan(
                taskID: taskID,
                completedAt: start.addingTimeInterval(Double(index)),
                impactNormalizedX: 0.5,
                cells: cells
            )
            for delta in plan.cellDeltas {
                cells[delta.cellIndex].density = min(
                    .max,
                    cells[delta.cellIndex].density &+ delta.amount
                )
            }
        }

        let snapshot = GardenSnapshot(totalCompletions: 500, cells: cells)
        #expect(snapshot.coverageFraction >= 0.95)
        #expect(snapshot.maximumEmptyRun <= 2)
    }

    @Test func visibleGrassDensityIsBoundedAndHeightIndependent() {
        #expect(GardenRenderingMetrics.visibleBladeCount(density: 0) == 0)
        #expect(GardenRenderingMetrics.visibleBladeCount(density: 1) == 2)
        #expect(GardenRenderingMetrics.visibleBladeCount(density: 2) == 4)
        #expect(GardenRenderingMetrics.visibleBladeCount(density: 100) == 24)
        #expect(GardenConstants.growthAnimationFrameCount == 90)
    }

    @Test func rareFlowersUseTwoPercentProbabilityAndOnlyApprovedStyles() {
        #expect(GardenFlowerTraits.style(probabilityRoll: 0.019_999, styleRoll: 0) == .fivePetal)
        #expect(GardenFlowerTraits.style(probabilityRoll: 0.019_999, styleRoll: 0.25) == .daisy)
        #expect(GardenFlowerTraits.style(probabilityRoll: 0.019_999, styleRoll: 0.50) == .bell)
        #expect(GardenFlowerTraits.style(probabilityRoll: 0.019_999, styleRoll: 0.75) == .dandelion)
        #expect(GardenFlowerTraits.style(probabilityRoll: 0.02, styleRoll: 0) == nil)

        let allowed = Set(GardenFlowerStyle.allCases)
        let flowers = (0..<10_000).compactMap {
            GardenFlowerTraits.style(cellSeed: UInt64($0 + 1), bladeIndex: $0 % 24)
        }
        #expect((150...250).contains(flowers.count))
        #expect(flowers.allSatisfy(allowed.contains))
    }
}

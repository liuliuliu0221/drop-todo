import Foundation

struct GardenLandingPlan: Sendable, Equatable {
    let randomSeed: UInt64
    let landingPositions: [Double]
    let cellDeltas: [CellDensityDelta]
}

struct GardenRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }
}

enum GardenDistribution {
    static func seed(taskID: UUID, completedAt: Date) -> UInt64 {
        var hash: UInt64 = 0xCBF29CE484222325
        for byte in taskID.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001B3
        }
        hash ^= completedAt.timeIntervalSince1970.bitPattern
        hash &*= 0x100000001B3
        return GardenSeedMixer.mix(hash)
    }

    static func makePlan(
        taskID: UUID,
        completedAt: Date,
        impactNormalizedX: Double,
        cells: [GardenCell]
    ) -> GardenLandingPlan {
        let randomSeed = seed(taskID: taskID, completedAt: completedAt)
        var random = GardenRandomNumberGenerator(seed: randomSeed)
        let impact = min(max(impactNormalizedX, 0), 1)
        let particleCount = GardenConstants.minimumLandingCount
            + random.nextInt(
                upperBound: GardenConstants.maximumLandingCount
                    - GardenConstants.minimumLandingCount
                    + 1
            )
        var positions: [Double] = []
        positions.reserveCapacity(particleCount)

        for index in 0..<particleCount {
            let position: Double
            if index == particleCount - 1 {
                position = sparsePosition(cells: cells, random: &random)
            } else {
                let category = random.nextUnitInterval()
                if category < 0.65 {
                    let centeredNoise = random.nextUnitInterval()
                        + random.nextUnitInterval()
                        + random.nextUnitInterval() - 1.5
                    position = impact + centeredNoise * 0.18
                } else if category < 0.90 {
                    let direction = random.nextUnitInterval() < 0.5 ? -1.0 : 1.0
                    position = impact + direction * (0.12 + random.nextUnitInterval() * 0.28)
                } else {
                    position = sparsePosition(cells: cells, random: &random)
                }
            }
            positions.append(min(max(position, 0), 1))
        }

        var deltaByCell: [Int: UInt16] = [:]
        for position in positions {
            let index = min(Int(position * Double(GardenConstants.cellCount)), GardenConstants.cellCount - 1)
            deltaByCell[index, default: 0] &+= 1
        }
        let deltas = deltaByCell.keys.sorted().map {
            CellDensityDelta(cellIndex: $0, amount: deltaByCell[$0] ?? 1)
        }
        return GardenLandingPlan(
            randomSeed: randomSeed,
            landingPositions: positions,
            cellDeltas: deltas
        )
    }

    private static func sparsePosition(
        cells: [GardenCell],
        random: inout GardenRandomNumberGenerator
    ) -> Double {
        guard cells.count == GardenConstants.cellCount else {
            return random.nextUnitInterval()
        }

        let weights = cells.map { cell in
            let divisor = Double(cell.density) + 1
            return 1 / (divisor * divisor)
        }
        let total = weights.reduce(0, +)
        var target = random.nextUnitInterval() * total
        var selectedIndex = cells.count - 1
        for (index, weight) in weights.enumerated() {
            target -= weight
            if target <= 0 {
                selectedIndex = index
                break
            }
        }
        let inset = 0.15 + random.nextUnitInterval() * 0.70
        return (Double(selectedIndex) + inset) / Double(cells.count)
    }
}

import Foundation

enum GardenConstants {
    static let cellCount = 128
    static let maximumPendingEvents = 16
    static let maximumVisibleDensity: UInt16 = 12
    static let minimumLandingCount = 6
    static let maximumLandingCount = 10
    static let growthAnimationFrameCount = 90
}

enum GardenRenderingMetrics {
    static func visibleBladeCount(density: UInt16) -> Int {
        guard density > 0 else { return 0 }
        let visibleDensity = min(density, GardenConstants.maximumVisibleDensity)
        return Int(visibleDensity) * 2
    }
}

enum GardenFlowerStyle: Int, CaseIterable, Sendable {
    case fivePetal = 1
    case daisy = 3
    case bell = 4
    case dandelion = 6
}

enum GardenFlowerTraits {
    static let probability = 0.02

    static func style(probabilityRoll: Double, styleRoll: Double) -> GardenFlowerStyle? {
        guard probabilityRoll >= 0, probabilityRoll < probability else { return nil }
        let styles = GardenFlowerStyle.allCases
        let normalizedStyleRoll = min(max(styleRoll, 0), 0.999_999_999)
        let index = min(Int(normalizedStyleRoll * Double(styles.count)), styles.count - 1)
        return styles[index]
    }

    static func style(cellSeed: UInt64, bladeIndex: Int) -> GardenFlowerStyle? {
        let bladeSeed = GardenSeedMixer.mix(
            cellSeed ^ (UInt64(bladeIndex) &* 0xD6E8FEB86659FD93)
        )
        var random = GardenRandomNumberGenerator(seed: bladeSeed)
        return style(
            probabilityRoll: random.nextUnitInterval(),
            styleRoll: random.nextUnitInterval()
        )
    }
}

struct GardenCell: Codable, Sendable, Equatable {
    var density: UInt16
    let styleSeed: UInt64
    var lastWateredAt: Date?
}

struct CellDensityDelta: Codable, Sendable, Equatable {
    let cellIndex: Int
    let amount: UInt16
}

struct PendingGardenEvent: Codable, Identifiable, Sendable, Equatable {
    var id: UUID { taskID }

    let taskID: UUID
    let completedAt: Date
    let impactNormalizedX: Double
    let randomSeed: UInt64
    let landingPositions: [Double]
    let cellDeltas: [CellDensityDelta]
    let preparedAt: Date
}

struct GardenState: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var totalCompletions: Int
    var cells: [GardenCell]
    var pendingEvents: [PendingGardenEvent]
    var savedAt: Date

    static func empty(savedAt: Date = .distantPast) -> GardenState {
        GardenState(
            schemaVersion: currentSchemaVersion,
            totalCompletions: 0,
            cells: (0..<GardenConstants.cellCount).map { index in
                GardenCell(
                    density: 0,
                    styleSeed: GardenSeedMixer.mix(UInt64(index) &+ 0x9E3779B97F4A7C15),
                    lastWateredAt: nil
                )
            },
            pendingEvents: [],
            savedAt: savedAt
        )
    }
}

struct GardenSnapshot: Sendable, Equatable {
    let totalCompletions: Int
    let cells: [GardenCell]

    static let empty = GardenSnapshot(totalCompletions: 0, cells: GardenState.empty().cells)

    var coverageFraction: Double {
        guard !cells.isEmpty else { return 0 }
        let occupied = cells.reduce(into: 0) { count, cell in
            if cell.density > 0 { count += 1 }
        }
        return Double(occupied) / Double(cells.count)
    }

    var maximumEmptyRun: Int {
        var maximum = 0
        var current = 0
        for cell in cells {
            if cell.density == 0 {
                current += 1
                maximum = max(maximum, current)
            } else {
                current = 0
            }
        }
        return maximum
    }
}

struct GardenCommitResult: Sendable, Equatable {
    let snapshot: GardenSnapshot
    let landingPositions: [Double]
    let changedCellIndices: Set<Int>
}

enum GardenStateValidationError: Error, Sendable, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    case invalidCellCount(Int)
    case tooManyPendingEvents(Int)
    case invalidPendingEvent(UUID)
    case invalidCellDelta(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "不支持花园数据版本 \(version)。"
        case let .invalidCellCount(count):
            "花园密度单元数量无效：\(count)。"
        case let .tooManyPendingEvents(count):
            "花园待提交事件过多：\(count)。"
        case let .invalidPendingEvent(taskID):
            "花园待提交事件无效：\(taskID.uuidString)。"
        case let .invalidCellDelta(index):
            "花园密度单元索引无效：\(index)。"
        }
    }
}

enum GardenStateValidator {
    static func validate(_ state: GardenState) throws {
        guard state.schemaVersion == GardenState.currentSchemaVersion else {
            throw GardenStateValidationError.unsupportedSchema(state.schemaVersion)
        }
        guard state.cells.count == GardenConstants.cellCount else {
            throw GardenStateValidationError.invalidCellCount(state.cells.count)
        }
        guard state.pendingEvents.count <= GardenConstants.maximumPendingEvents else {
            throw GardenStateValidationError.tooManyPendingEvents(state.pendingEvents.count)
        }

        var taskIDs = Set<UUID>()
        for event in state.pendingEvents {
            guard taskIDs.insert(event.taskID).inserted,
                  (0...1).contains(event.impactNormalizedX),
                  event.landingPositions.allSatisfy({ (0...1).contains($0) }),
                  !event.landingPositions.isEmpty else {
                throw GardenStateValidationError.invalidPendingEvent(event.taskID)
            }
            for delta in event.cellDeltas {
                guard state.cells.indices.contains(delta.cellIndex), delta.amount > 0 else {
                    throw GardenStateValidationError.invalidCellDelta(delta.cellIndex)
                }
            }
        }
    }
}

enum GardenSeedMixer {
    static func mix(_ value: UInt64) -> UInt64 {
        var value = value &+ 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

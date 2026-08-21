import Foundation
import Testing
@testable import WaterDropTodo

struct GardenStoreTests {
    @Test func stateRoundTripsThroughJSON() async throws {
        let directory = gardenTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GardenStore(directoryURL: directory)
        #expect(try await store.load() == .empty)

        var state = GardenState.empty(savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        state.totalCompletions = 3
        state.cells[4].density = 7
        state.cells[4].lastWateredAt = state.savedAt
        try await store.save(state)

        let reloaded = GardenStore(directoryURL: directory)
        #expect(try await reloaded.load() == .loaded)
        #expect(try await reloaded.snapshot() == state)
    }

    @Test func corruptPrimaryRecoversPreviousAndPreservesCorruptCopy() async throws {
        let directory = gardenTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GardenStore(directoryURL: directory)
        _ = try await store.load()

        var first = GardenState.empty(savedAt: Date(timeIntervalSince1970: 1_800_000_000))
        first.cells[2].density = 1
        try await store.save(first)
        var second = first
        second.cells[2].density = 2
        second.savedAt = first.savedAt.addingTimeInterval(1)
        try await store.save(second)

        let primary = directory.appendingPathComponent("garden.json")
        let broken = Data("{broken".utf8)
        try broken.write(to: primary, options: .atomic)

        let recovered = GardenStore(directoryURL: directory)
        guard case let .recoveredFromPrevious(corruptCopy) = try await recovered.load() else {
            Issue.record("花园主文件损坏时应从 previous 恢复")
            return
        }
        #expect(try Data(contentsOf: corruptCopy) == broken)
        #expect(try await recovered.snapshot() == first)
    }

    @Test func invalidCellCountIsRejected() throws {
        var state = GardenState.empty()
        state.cells.removeLast()
        #expect(throws: GardenStateValidationError.invalidCellCount(GardenConstants.cellCount - 1)) {
            try GardenStateValidator.validate(state)
        }
    }

    @Test func corruptStoreWithoutBackupResetsGardenButPreservesCorruptBytes() async throws {
        let directory = gardenTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primary = directory.appendingPathComponent("garden.json")
        let broken = Data("not-json".utf8)
        try broken.write(to: primary, options: .atomic)

        let store = GardenStore(directoryURL: directory)
        guard case let .resetAfterCorruption(corruptCopy) = try await store.load() else {
            Issue.record("没有备份时应保留损坏副本并重建空花园")
            return
        }
        #expect(try Data(contentsOf: corruptCopy) == broken)
        let snapshot = try await store.snapshot()
        #expect(snapshot.totalCompletions == 0)
        #expect(snapshot.pendingEvents.isEmpty)
        #expect(snapshot.cells.allSatisfy { $0.density == 0 })
    }
}

private func gardenTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "WaterDropTodo-GardenStoreTests-\(UUID().uuidString)",
        isDirectory: true
    )
}

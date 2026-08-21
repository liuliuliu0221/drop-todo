import Foundation
import Testing
@testable import WaterDropTodo

struct GardenServiceTests {
    @Test func prepareAndCommitIncreaseDensityExactlyOnce() async throws {
        let fixture = await gardenServiceFixture()
        defer { fixture.cleanup() }
        let taskID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try await fixture.service.prepare(
            taskID: taskID,
            completedAt: completedAt,
            impactNormalizedX: 0.5
        )
        let repeated = try await fixture.service.prepare(
            taskID: taskID,
            completedAt: completedAt,
            impactNormalizedX: 0.1
        )
        #expect(first == repeated)

        let committed = try await fixture.service.commit(taskID: taskID, at: completedAt)
        #expect(committed.snapshot.totalCompletions == 1)
        #expect(!committed.changedCellIndices.isEmpty)
        #expect(committed.landingPositions == first.landingPositions)

        let secondCommit = try await fixture.service.commit(taskID: taskID, at: completedAt)
        #expect(secondCommit.snapshot.totalCompletions == 1)
        #expect(secondCommit.changedCellIndices.isEmpty)
    }

    @Test func startupCommitsPendingEventOnlyForCompletedTask() async throws {
        let directory = gardenServiceTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstService = GardenService(store: GardenStore(directoryURL: directory))
        _ = try await firstService.start(taskStatuses: [:])
        let completedID = UUID()
        let activeID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await firstService.prepare(
            taskID: completedID,
            completedAt: date,
            impactNormalizedX: 0.4
        )
        _ = try await firstService.prepare(
            taskID: activeID,
            completedAt: date,
            impactNormalizedX: 0.6
        )

        let recovered = GardenService(store: GardenStore(directoryURL: directory))
        let snapshot = try await recovered.start(taskStatuses: [
            completedID: .completed,
            activeID: .active
        ])
        #expect(snapshot.totalCompletions == 1)
        #expect(snapshot.coverageFraction > 0)

        let state = try await GardenStore(directoryURL: directory).loadAndSnapshotForTesting()
        #expect(state.pendingEvents.isEmpty)
    }

    @Test func cancelAndClearLeaveEmptyGarden() async throws {
        let fixture = await gardenServiceFixture()
        defer { fixture.cleanup() }
        let taskID = UUID()
        _ = try await fixture.service.prepare(
            taskID: taskID,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000),
            impactNormalizedX: 0.5
        )
        try await fixture.service.cancel(taskID: taskID)
        #expect(try await fixture.service.currentSnapshot() == .empty)

        let committedID = UUID()
        _ = try await fixture.service.prepare(
            taskID: committedID,
            completedAt: Date(timeIntervalSince1970: 1_800_000_100),
            impactNormalizedX: 0.5
        )
        _ = try await fixture.service.commit(taskID: committedID)
        let cleared = try await fixture.service.clearAll()
        #expect(cleared == .empty)
    }
}

private struct GardenServiceFixture {
    let directory: URL
    let service: GardenService

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func gardenServiceFixture() async -> GardenServiceFixture {
    let directory = gardenServiceTemporaryDirectory()
    let service = GardenService(store: GardenStore(directoryURL: directory))
    _ = try? await service.start(taskStatuses: [:])
    return GardenServiceFixture(directory: directory, service: service)
}

private func gardenServiceTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "WaterDropTodo-GardenServiceTests-\(UUID().uuidString)",
        isDirectory: true
    )
}

private extension GardenStore {
    func loadAndSnapshotForTesting() async throws -> GardenState {
        _ = try load()
        return try snapshot()
    }
}

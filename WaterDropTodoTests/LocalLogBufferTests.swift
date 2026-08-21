import Foundation
import Testing
@testable import WaterDropTodo

struct LocalLogBufferTests {
    @Test func persistedLogRetainsOnlyRecentSevenDays() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaterDropTodoLogTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("diagnostics.jsonl")
        let buffer = LocalLogBuffer(logURL: url)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        await buffer.append(entry(at: now.addingTimeInterval(-8 * 24 * 60 * 60), message: "old"))
        await buffer.append(entry(at: now, message: "recent"))

        let exported = try await buffer.exportData(since: now.addingTimeInterval(-7 * 24 * 60 * 60))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([AppLogEntry].self, from: exported)
        #expect(entries.map(\.message) == ["recent"])
        let persistedText = try String(contentsOf: url, encoding: .utf8)
        #expect(!persistedText.contains("old"))
        #expect(persistedText.contains("recent"))
    }

    private func entry(at date: Date, message: String) -> AppLogEntry {
        AppLogEntry(
            id: UUID(),
            timestamp: date,
            category: .store,
            level: "INFO",
            message: message
        )
    }
}

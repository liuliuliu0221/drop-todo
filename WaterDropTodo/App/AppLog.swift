import Foundation
import OSLog

enum AppLogCategory: String, Codable, Sendable, CaseIterable {
    case app
    case store
    case time
    case window
    case render
    case animation
}

struct AppLogEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let category: AppLogCategory
    let level: String
    let message: String
}

actor LocalLogBuffer {
    static let shared = LocalLogBuffer()

    private var entries: [AppLogEntry] = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logURL: URL
    private let retentionInterval: TimeInterval

    init(logURL: URL? = nil, retentionInterval: TimeInterval = 7 * 24 * 60 * 60) {
        self.logURL = logURL ?? Self.defaultLogURL
        self.retentionInterval = retentionInterval
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func append(_ entry: AppLogEntry) {
        entries.append(entry)
        if entries.count > 200 {
            entries.removeFirst(entries.count - 200)
        }
        persist(entry)
        prune(referenceDate: entry.timestamp)
    }

    func snapshot() -> [AppLogEntry] {
        entries
    }

    func exportData(since: Date) throws -> Data {
        var exported = entries.filter { $0.timestamp >= since }
        if let data = try? Data(contentsOf: logURL),
           let text = String(data: data, encoding: .utf8) {
            let persisted = text.split(separator: "\n").compactMap { line in
                try? decoder.decode(AppLogEntry.self, from: Data(line.utf8))
            }.filter { $0.timestamp >= since }
            var byID: [UUID: AppLogEntry] = [:]
            for entry in persisted + exported {
                byID[entry.id] = entry
            }
            exported = byID.values.sorted { $0.timestamp < $1.timestamp }
        }
        let exportEncoder = JSONEncoder()
        exportEncoder.dateEncodingStrategy = .iso8601
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try exportEncoder.encode(exported)
    }

    private func persist(_ entry: AppLogEntry) {
        guard let data = try? encoder.encode(entry) else { return }
        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try? Data().write(to: logURL, options: .atomic)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
        } catch {}
    }

    private func prune(referenceDate: Date) {
        let cutoff = referenceDate.addingTimeInterval(-retentionInterval)
        entries.removeAll { $0.timestamp < cutoff }
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let retained = text.split(separator: "\n").compactMap { line in
            try? decoder.decode(AppLogEntry.self, from: Data(line.utf8))
        }.filter { $0.timestamp >= cutoff }
        var output = Data()
        for entry in retained {
            guard let encoded = try? encoder.encode(entry) else { continue }
            output.append(encoded)
            output.append(0x0A)
        }
        try? output.write(to: logURL, options: .atomic)
    }

    private static var defaultLogURL: URL {
        let base = (try? TaskStore.applicationSupportDirectory())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WaterDropTodo-Recovery")
        return base.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("diagnostics.jsonl")
    }
}

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.liuliuliu.WaterDropTodo"
    private static let loggers = Dictionary(
        uniqueKeysWithValues: AppLogCategory.allCases.map {
            ($0, Logger(subsystem: subsystem, category: $0.rawValue))
        }
    )

    static func info(_ category: AppLogCategory, _ message: String) {
        loggers[category]?.info("\(message, privacy: .public)")
        record(category: category, level: "INFO", message: message)
    }

    static func error(_ category: AppLogCategory, _ message: String) {
        loggers[category]?.error("\(message, privacy: .public)")
        record(category: category, level: "ERROR", message: message)
    }

    private static func record(category: AppLogCategory, level: String, message: String) {
        let entry = AppLogEntry(
            id: UUID(),
            timestamp: Date(),
            category: category,
            level: level,
            message: message
        )
        Task { await LocalLogBuffer.shared.append(entry) }
    }
}

import Foundation

struct StoreEnvelope: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let savedAt: Date
    var tasks: [TaskRecord]

    init(
        schemaVersion: Int = StoreEnvelope.currentSchemaVersion,
        savedAt: Date,
        tasks: [TaskRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.tasks = tasks
    }
}

enum StoreLoadOutcome: Sendable, Equatable {
    case empty
    case loaded
    case recoveredFromPrevious(corruptCopy: URL)
}

enum TaskStoreError: Error, Sendable, Equatable, LocalizedError {
    case notLoaded
    case unsupportedSchema(Int)
    case corruptStoreAndNoValidBackup

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            "任务存储尚未加载。"
        case let .unsupportedSchema(version):
            "不支持任务数据版本 \(version)。"
        case .corruptStoreAndNoValidBackup:
            "主任务文件已损坏，且没有可用备份。"
        }
    }
}

struct TaskStoreIO: Sendable {
    let writeAtomically: @Sendable (Data, URL) throws -> Void

    static let live = TaskStoreIO { data, url in
        try data.write(to: url, options: .atomic)
    }
}

actor TaskStore {
    let directoryURL: URL
    let primaryURL: URL
    let previousURL: URL

    private var envelope: StoreEnvelope?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let io: TaskStoreIO

    init(directoryURL: URL, io: TaskStoreIO = .live) {
        self.directoryURL = directoryURL
        self.primaryURL = directoryURL.appendingPathComponent("tasks.json")
        self.previousURL = directoryURL.appendingPathComponent("tasks.previous.json")
        self.io = io

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func applicationSupportDirectory(
        fileManager: FileManager = .default,
        bundleIdentifier: String = "com.liuliuliu.WaterDropTodo"
    ) throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return root.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    @discardableResult
    func load() throws -> StoreLoadOutcome {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: primaryURL.path) else {
            envelope = StoreEnvelope(savedAt: .distantPast, tasks: [])
            AppLog.info(.store, "store_load outcome=empty")
            return .empty
        }

        do {
            envelope = try decodeEnvelope(at: primaryURL)
            AppLog.info(.store, "store_load outcome=loaded")
            return .loaded
        } catch {
            let corruptCopy = directoryURL.appendingPathComponent(
                "tasks.corrupt-\(UUID().uuidString).json"
            )
            try fileManager.copyItem(at: primaryURL, to: corruptCopy)

            guard fileManager.fileExists(atPath: previousURL.path),
                  let recovered = try? decodeEnvelope(at: previousURL) else {
                AppLog.error(.store, "store_recovery_failed reason=no_valid_backup")
                throw TaskStoreError.corruptStoreAndNoValidBackup
            }
            let recoveredData = try encoder.encode(recovered)
            try io.writeAtomically(recoveredData, primaryURL)
            envelope = recovered
            AppLog.error(.store, "store_recovered corrupt_copy=\(corruptCopy.lastPathComponent)")
            return .recoveredFromPrevious(corruptCopy: corruptCopy)
        }
    }

    func snapshot() throws -> StoreEnvelope {
        guard let envelope else { throw TaskStoreError.notLoaded }
        return envelope
    }

    @discardableResult
    func save(tasks: [TaskRecord], savedAt: Date) throws -> StoreEnvelope {
        guard envelope != nil else { throw TaskStoreError.notLoaded }
        try TaskDataValidator.validate(tasks)

        let sortedTasks = tasks.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
        let nextEnvelope = StoreEnvelope(savedAt: savedAt, tasks: sortedTasks)
        let data = try encoder.encode(nextEnvelope)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: primaryURL.path) {
                if fileManager.fileExists(atPath: previousURL.path) {
                    try fileManager.removeItem(at: previousURL)
                }
                try fileManager.copyItem(at: primaryURL, to: previousURL)
            }

            try io.writeAtomically(data, primaryURL)
        } catch {
            AppLog.error(.store, "store_write_failed error=\(error.localizedDescription)")
            throw error
        }
        envelope = nextEnvelope
        return nextEnvelope
    }

    @discardableResult
    func clearAll(savedAt: Date) throws -> StoreEnvelope {
        guard envelope != nil else { throw TaskStoreError.notLoaded }
        let cleared = StoreEnvelope(savedAt: savedAt, tasks: [])
        let data = try encoder.encode(cleared)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try io.writeAtomically(data, primaryURL)
        if fileManager.fileExists(atPath: previousURL.path) {
            try fileManager.removeItem(at: previousURL)
        }
        envelope = cleared
        return cleared
    }

    private func decodeEnvelope(at url: URL) throws -> StoreEnvelope {
        let decoded = try decoder.decode(StoreEnvelope.self, from: Data(contentsOf: url))
        guard decoded.schemaVersion == StoreEnvelope.currentSchemaVersion else {
            throw TaskStoreError.unsupportedSchema(decoded.schemaVersion)
        }
        try TaskDataValidator.validate(decoded.tasks)
        return decoded
    }
}

import Foundation

enum GardenLoadOutcome: Sendable, Equatable {
    case empty
    case loaded
    case recoveredFromPrevious(corruptCopy: URL)
    case resetAfterCorruption(corruptCopy: URL)
}

enum GardenStoreError: Error, Sendable, Equatable, LocalizedError {
    case notLoaded
    case corruptStoreAndNoValidBackup

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            "花园存储尚未加载。"
        case .corruptStoreAndNoValidBackup:
            "花园数据已损坏，且没有可用备份。"
        }
    }
}

struct GardenStoreIO: Sendable {
    let writeAtomically: @Sendable (Data, URL) throws -> Void

    static let live = GardenStoreIO { data, url in
        try data.write(to: url, options: .atomic)
    }
}

actor GardenStore {
    let directoryURL: URL
    let primaryURL: URL
    let previousURL: URL

    private var state: GardenState?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let io: GardenStoreIO

    init(directoryURL: URL, io: GardenStoreIO = .live) {
        self.directoryURL = directoryURL
        self.primaryURL = directoryURL.appendingPathComponent("garden.json")
        self.previousURL = directoryURL.appendingPathComponent("garden.previous.json")
        self.io = io

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    @discardableResult
    func load() throws -> GardenLoadOutcome {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: primaryURL.path) else {
            state = .empty()
            return .empty
        }

        do {
            state = try decodeState(at: primaryURL)
            return .loaded
        } catch {
            let corruptCopy = directoryURL.appendingPathComponent(
                "garden.corrupt-\(UUID().uuidString).json"
            )
            try fileManager.copyItem(at: primaryURL, to: corruptCopy)
            guard fileManager.fileExists(atPath: previousURL.path),
                  let recovered = try? decodeState(at: previousURL) else {
                let empty = GardenState.empty(savedAt: Date())
                try io.writeAtomically(encoder.encode(empty), primaryURL)
                state = empty
                return .resetAfterCorruption(corruptCopy: corruptCopy)
            }
            try io.writeAtomically(encoder.encode(recovered), primaryURL)
            state = recovered
            return .recoveredFromPrevious(corruptCopy: corruptCopy)
        }
    }

    func snapshot() throws -> GardenState {
        guard let state else { throw GardenStoreError.notLoaded }
        return state
    }

    func save(_ nextState: GardenState) throws {
        guard state != nil else { throw GardenStoreError.notLoaded }
        try GardenStateValidator.validate(nextState)

        let data = try encoder.encode(nextState)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: primaryURL.path) {
            if fileManager.fileExists(atPath: previousURL.path) {
                try fileManager.removeItem(at: previousURL)
            }
            try fileManager.copyItem(at: primaryURL, to: previousURL)
        }
        try io.writeAtomically(data, primaryURL)
        state = nextState
    }

    func clearAll(at date: Date) throws {
        guard state != nil else { throw GardenStoreError.notLoaded }
        let cleared = GardenState.empty(savedAt: date)
        try GardenStateValidator.validate(cleared)
        let data = try encoder.encode(cleared)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try io.writeAtomically(data, primaryURL)
        if fileManager.fileExists(atPath: previousURL.path) {
            try fileManager.removeItem(at: previousURL)
        }
        state = cleared
    }

    private func decodeState(at url: URL) throws -> GardenState {
        let decoded = try decoder.decode(GardenState.self, from: Data(contentsOf: url))
        try GardenStateValidator.validate(decoded)
        return decoded
    }
}

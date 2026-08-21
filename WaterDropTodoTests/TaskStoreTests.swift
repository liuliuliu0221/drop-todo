import Foundation
import Testing
@testable import WaterDropTodo

struct TaskStoreTests {
    @Test func jsonRoundTripAndUnknownFields() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = sampleRecord(now: now)
        let store = TaskStore(directoryURL: directory)

        #expect(try await store.load() == .empty)
        _ = try await store.save(tasks: [record], savedAt: now)

        let data = try Data(contentsOf: directory.appendingPathComponent("tasks.json"))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["futureField"] = ["ignored": true]
        try JSONSerialization.data(withJSONObject: json)
            .write(to: directory.appendingPathComponent("tasks.json"), options: .atomic)

        let reloaded = TaskStore(directoryURL: directory)
        #expect(try await reloaded.load() == .loaded)
        #expect(try await reloaded.snapshot().tasks == [record])
    }

    @Test func corruptPrimaryRecoversPreviousAndPreservesCorruptCopy() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = sampleRecord(now: now)
        var second = sampleRecord(now: now.addingTimeInterval(1))
        second.title = "第二版"

        let store = TaskStore(directoryURL: directory)
        _ = try await store.load()
        _ = try await store.save(tasks: [first], savedAt: now)
        _ = try await store.save(tasks: [second], savedAt: now.addingTimeInterval(1))
        try Data("{broken".utf8).write(
            to: directory.appendingPathComponent("tasks.json"),
            options: .atomic
        )

        let recoveringStore = TaskStore(directoryURL: directory)
        let outcome = try await recoveringStore.load()
        guard case let .recoveredFromPrevious(corruptCopy) = outcome else {
            Issue.record("应从 previous 恢复，实际为 \(outcome)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: corruptCopy.path))
        #expect(try await recoveringStore.snapshot().tasks == [first])
    }

    @Test func corruptStoreWithoutBackupDoesNotOverwriteOriginal() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primary = directory.appendingPathComponent("tasks.json")
        let broken = Data("not-json".utf8)
        try broken.write(to: primary)

        let store = TaskStore(directoryURL: directory)
        do {
            _ = try await store.load()
            Issue.record("没有备份时应报告损坏")
        } catch {
            #expect(error as? TaskStoreError == .corruptStoreAndNoValidBackup)
        }
        #expect(try Data(contentsOf: primary) == broken)
    }

    @Test func truncatedPrimaryRecoversPreviousAndPreservesTruncatedBytes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = sampleRecord(now: now)
        var second = sampleRecord(now: now.addingTimeInterval(1))
        second.title = "截断前版本"

        let store = TaskStore(directoryURL: directory)
        _ = try await store.load()
        _ = try await store.save(tasks: [first], savedAt: now)
        _ = try await store.save(tasks: [second], savedAt: now.addingTimeInterval(1))
        let primary = directory.appendingPathComponent("tasks.json")
        let complete = try Data(contentsOf: primary)
        let truncated = complete.prefix(max(1, complete.count / 3))
        try Data(truncated).write(to: primary, options: .atomic)

        let recovered = TaskStore(directoryURL: directory)
        guard case let .recoveredFromPrevious(corruptCopy) = try await recovered.load() else {
            Issue.record("截断主文件应从 previous 恢复")
            return
        }
        #expect(try Data(contentsOf: corruptCopy) == Data(truncated))
        #expect(try await recovered.snapshot().tasks == [first])
    }

    @Test func corruptPrimaryAndBackupAreBothPreservedWithoutCreatingEmptyStore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = sampleRecord(now: now)
        let store = TaskStore(directoryURL: directory)
        _ = try await store.load()
        _ = try await store.save(tasks: [record], savedAt: now)
        _ = try await store.save(tasks: [record], savedAt: now.addingTimeInterval(1))

        let primary = directory.appendingPathComponent("tasks.json")
        let previous = directory.appendingPathComponent("tasks.previous.json")
        let brokenPrimary = Data("{truncated-primary".utf8)
        let brokenPrevious = Data("not-json-backup".utf8)
        try brokenPrimary.write(to: primary, options: .atomic)
        try brokenPrevious.write(to: previous, options: .atomic)

        let reloaded = TaskStore(directoryURL: directory)
        do {
            _ = try await reloaded.load()
            Issue.record("双文件损坏时必须拒绝加载")
        } catch {
            #expect(error as? TaskStoreError == .corruptStoreAndNoValidBackup)
        }

        #expect(try Data(contentsOf: primary) == brokenPrimary)
        #expect(try Data(contentsOf: previous) == brokenPrevious)
        let corruptCopies = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("tasks.corrupt-") }
        #expect(corruptCopies.count == 1)
        #expect(try Data(contentsOf: corruptCopies[0]) == brokenPrimary)
    }

    @Test func semanticCorruptionRecoversPreviousWithoutCrashing() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = sampleRecord(now: now)
        let store = TaskStore(directoryURL: directory)
        _ = try await store.load()
        _ = try await store.save(tasks: [valid], savedAt: now)
        _ = try await store.save(tasks: [valid], savedAt: now.addingTimeInterval(1))

        let primary = directory.appendingPathComponent("tasks.json")
        let data = try Data(contentsOf: primary)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var tasks = try #require(json["tasks"] as? [[String: Any]])
        tasks.append(tasks[0])
        json["tasks"] = tasks
        try JSONSerialization.data(withJSONObject: json).write(to: primary, options: .atomic)

        let recovered = TaskStore(directoryURL: directory)
        let outcome = try await recovered.load()
        guard case .recoveredFromPrevious = outcome else {
            Issue.record("语义损坏应从 previous 恢复")
            return
        }
        #expect(try await recovered.snapshot().tasks == [valid])
    }

    @Test func unsupportedSchemaWithoutBackupPreservesOriginalForFutureMigration() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let unsupported = StoreEnvelope(
            schemaVersion: StoreEnvelope.currentSchemaVersion + 1,
            savedAt: now,
            tasks: [sampleRecord(now: now)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let original = try encoder.encode(unsupported)
        let primary = directory.appendingPathComponent("tasks.json")
        try original.write(to: primary, options: .atomic)

        let store = TaskStore(directoryURL: directory)
        do {
            _ = try await store.load()
            Issue.record("未知 Schema 且无备份时应拒绝加载")
        } catch {
            #expect(error as? TaskStoreError == .corruptStoreAndNoValidBackup)
        }

        #expect(try Data(contentsOf: primary) == original)
        let preservedCopies = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("tasks.corrupt-") }
        #expect(preservedCopies.count == 1)
        #expect(try Data(contentsOf: preservedCopies[0]) == original)
    }

    @Test func rejectedSaveLeavesPrimaryFileUnchanged() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let record = sampleRecord(now: now)
        let store = TaskStore(directoryURL: directory)
        _ = try await store.load()
        _ = try await store.save(tasks: [record], savedAt: now)
        let primary = directory.appendingPathComponent("tasks.json")
        let before = try Data(contentsOf: primary)

        do {
            _ = try await store.save(tasks: [record, record], savedAt: now.addingTimeInterval(1))
            Issue.record("重复 ID 保存应失败")
        } catch {
            #expect(error as? TaskDataValidationError == .duplicateID(record.id))
        }
        #expect(try Data(contentsOf: primary) == before)
    }

    @Test func permissionFailureLeavesPrimaryAndInMemorySnapshotUnchanged() async throws {
        try await assertInjectedWriteFailure(.permissionDenied)
    }

    @Test func diskFullFailureLeavesPrimaryAndInMemorySnapshotUnchanged() async throws {
        try await assertInjectedWriteFailure(.diskFull)
    }

    private func assertInjectedWriteFailure(_ injectedError: InjectedWriteError) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = sampleRecord(now: now)
        let live = TaskStore(directoryURL: directory)
        _ = try await live.load()
        _ = try await live.save(tasks: [original], savedAt: now)

        let primary = directory.appendingPathComponent("tasks.json")
        let bytesBefore = try Data(contentsOf: primary)
        let failing = TaskStore(
            directoryURL: directory,
            io: TaskStoreIO { _, _ in throw injectedError }
        )
        _ = try await failing.load()
        var changed = original
        changed.title = "不得进入内存或磁盘"

        do {
            _ = try await failing.save(tasks: [changed], savedAt: now.addingTimeInterval(1))
            Issue.record("注入写入失败时保存必须失败")
        } catch {
            #expect(error as? InjectedWriteError == injectedError)
        }

        #expect(try Data(contentsOf: primary) == bytesBefore)
        #expect(try await failing.snapshot().tasks == [original])
        let reloaded = TaskStore(directoryURL: directory)
        #expect(try await reloaded.load() == .loaded)
        #expect(try await reloaded.snapshot().tasks == [original])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WaterDropTodoStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func sampleRecord(now: Date) -> TaskRecord {
        TaskRecord(
            id: UUID(),
            title: "测试任务",
            deadline: now.addingTimeInterval(600),
            tag: .work,
            urgency: .medium,
            status: .active,
            createdAt: now,
            visualStartAt: now,
            completedAt: nil,
            ruinedAt: nil,
            recalledAt: nil,
            recalledFromID: nil
        )
    }
}

private enum InjectedWriteError: Error, Sendable, Equatable {
    case permissionDenied
    case diskFull
}

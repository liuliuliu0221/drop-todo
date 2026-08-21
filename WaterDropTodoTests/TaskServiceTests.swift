import Foundation
import Testing
@testable import WaterDropTodo

private struct FixedNowProvider: NowProviding {
    let value: Date
    func now() -> Date { value }
}

struct TaskServiceTests {
    @Test func createTrimsTitleAndPersists() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        let created = try await fixture.service.create(
            CreateTaskInput(
                title: "  完成 M1A  ",
                deadline: now.addingTimeInterval(600),
                tag: .work,
                urgency: .high
            )
        )

        #expect(created.title == "完成 M1A")
        #expect(created.status == .active)
        #expect(try await fixture.service.tasks(status: .active) == [created])

        let reloaded = TaskService(
            store: TaskStore(directoryURL: fixture.directory),
            nowProvider: FixedNowProvider(value: now)
        )
        _ = try await reloaded.start()
        #expect(try await reloaded.tasks(status: .active) == [created])
    }

    @Test func rejectsInvalidTitleAndDeadline() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        do {
            _ = try await fixture.service.create(
                CreateTaskInput(title: " \n ", deadline: now.addingTimeInterval(600), tag: nil)
            )
            Issue.record("空标题应被拒绝")
        } catch {
            #expect(error as? TaskDomainError == .titleEmpty)
        }

        do {
            _ = try await fixture.service.create(
                CreateTaskInput(title: "太近", deadline: now.addingTimeInterval(59), tag: nil)
            )
            Issue.record("不足一分钟的截止时间应被拒绝")
        } catch let error as TaskDomainError {
            guard case .deadlineTooSoon = error else {
                Issue.record("收到错误：\(error)")
                return
            }
        }
    }

    @Test func updateCompleteAndCancelEnforceActiveState() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        let first = try await fixture.service.create(
            CreateTaskInput(title: "第一项", deadline: now.addingTimeInterval(600), tag: .life)
        )
        try await fixture.service.update(
            id: first.id,
            changes: TaskChanges(title: "已编辑", tag: .set(nil), urgency: .high)
        )
        let edited = try #require(try await fixture.service.tasks(status: .active).first)
        #expect(edited.title == "已编辑")
        #expect(edited.tag == nil)
        #expect(edited.urgency == .high)

        let completedAt = now.addingTimeInterval(120)
        let snapshot = try await fixture.service.complete(id: first.id, at: completedAt)
        #expect(snapshot.taskID == first.id)
        #expect(try await fixture.service.tasks(status: .completed).count == 1)

        do {
            try await fixture.service.update(id: first.id, changes: TaskChanges(title: "不能编辑"))
            Issue.record("完成任务不应允许编辑")
        } catch let error as TaskDomainError {
            #expect(error == .invalidStatus(expected: .active, actual: .completed))
        }

        let second = try await fixture.service.create(
            CreateTaskInput(title: "取消项", deadline: now.addingTimeInterval(900), tag: nil)
        )
        try await fixture.service.cancel(id: second.id)
        #expect(try await fixture.service.tasks(status: nil).contains { $0.id == second.id } == false)
    }

    @Test func expirationIsPersistedAndIdempotent() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        let task = try await fixture.service.create(
            CreateTaskInput(title: "即将到期", deadline: now.addingTimeInterval(60), tag: nil)
        )
        let expirationTime = now.addingTimeInterval(61)
        let first = try await fixture.service.expireDueTasks(at: expirationTime)
        let second = try await fixture.service.expireDueTasks(at: expirationTime)

        #expect(first.map(\.taskID) == [task.id])
        #expect(second.isEmpty)
        #expect(try await fixture.service.tasks(status: .active).isEmpty)
        #expect(try await fixture.service.tasks(status: .ruined).first?.ruinedAt == expirationTime)
    }

    @Test func expirationSkipsOnlyTheProtectedTask() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        let protected = try await fixture.service.create(
            CreateTaskInput(title: "悬停中", deadline: now.addingTimeInterval(60), tag: nil)
        )
        let unprotected = try await fixture.service.create(
            CreateTaskInput(title: "未悬停", deadline: now.addingTimeInterval(61), tag: nil)
        )

        let snapshots = try await fixture.service.expireDueTasks(
            at: now.addingTimeInterval(62),
            excluding: [protected.id]
        )

        #expect(snapshots.map(\.taskID) == [unprotected.id])
        #expect(try await fixture.service.tasks(status: .active).map(\.id) == [protected.id])
    }

    @Test func concurrentCreatesDoNotLoseWrites() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        try await withThrowingTaskGroup(of: TaskRecord.self) { group in
            for index in 0..<50 {
                group.addTask {
                    try await fixture.service.create(
                        CreateTaskInput(
                            title: "任务 \(index)",
                            deadline: now.addingTimeInterval(Double(600 + index)),
                            tag: nil
                        )
                    )
                }
            }
            for try await _ in group {}
        }

        #expect(try await fixture.service.tasks(status: .active).count == 50)
    }

    @Test func updateResortsActiveAndCompletedUsesCompletionTimeDescending() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        let first = try await fixture.service.create(
            CreateTaskInput(title: "稍后", deadline: now.addingTimeInterval(1_200), tag: .work)
        )
        let second = try await fixture.service.create(
            CreateTaskInput(title: "较早", deadline: now.addingTimeInterval(600), tag: .life)
        )
        #expect(try await fixture.service.tasks(status: .active).map(\.id) == [second.id, first.id])

        try await fixture.service.update(
            id: first.id,
            changes: TaskChanges(deadline: now.addingTimeInterval(300))
        )
        #expect(try await fixture.service.tasks(status: .active).map(\.id) == [first.id, second.id])

        _ = try await fixture.service.complete(id: first.id, at: now.addingTimeInterval(10))
        _ = try await fixture.service.complete(id: second.id, at: now.addingTimeInterval(20))
        #expect(try await fixture.service.tasks(status: .completed).map(\.id) == [second.id, first.id])
    }

    @Test func taskQueryFiltersTagsAndSortsDeadlines() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let workLater = makeRecord(
            title: "工作稍后",
            deadline: now.addingTimeInterval(900),
            tag: .work,
            createdAt: now
        )
        let workSooner = makeRecord(
            title: "工作较早",
            deadline: now.addingTimeInterval(600),
            tag: .work,
            createdAt: now.addingTimeInterval(1)
        )
        let life = makeRecord(
            title: "生活",
            deadline: now.addingTimeInterval(300),
            tag: .life,
            createdAt: now.addingTimeInterval(2)
        )

        #expect(TaskQuery.active([workLater, life, workSooner], tag: .work).map(\.id) == [workSooner.id, workLater.id])
        #expect(TaskQuery.active([workLater, life, workSooner], tag: nil).map(\.id) == [life.id, workSooner.id, workLater.id])
    }

    @Test func clearCompletedKeepsActiveAndRuinedRecords() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        let completed = try await fixture.service.create(
            CreateTaskInput(title: "完成项", deadline: now.addingTimeInterval(600), tag: nil)
        )
        let active = try await fixture.service.create(
            CreateTaskInput(title: "进行项", deadline: now.addingTimeInterval(1_200), tag: nil)
        )
        let ruined = try await fixture.service.create(
            CreateTaskInput(title: "到期项", deadline: now.addingTimeInterval(300), tag: nil)
        )
        _ = try await fixture.service.complete(id: completed.id, at: now.addingTimeInterval(10))
        _ = try await fixture.service.expireDueTasks(at: now.addingTimeInterval(301))

        try await fixture.service.clearCompleted()

        let remaining = try await fixture.service.tasks(status: nil)
        #expect(remaining.contains { $0.id == completed.id } == false)
        #expect(remaining.contains { $0.id == active.id })
        #expect(remaining.contains { $0.id == ruined.id && $0.status == .ruined })
    }

    @Test func recallAtomicallyArchivesRuinAndCreatesLinkedActiveTask() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        let original = try await fixture.service.create(
            CreateTaskInput(
                title: "召回我",
                deadline: now.addingTimeInterval(120),
                tag: .inspiration,
                urgency: .high
            )
        )
        _ = try await fixture.service.expireDueTasks(at: now.addingTimeInterval(121))
        let recalledAt = now.addingTimeInterval(180)
        let newDeadline = now.addingTimeInterval(1_800)
        let replacement = try await fixture.service.recall(
            id: original.id,
            newDeadline: newDeadline,
            at: recalledAt
        )

        #expect(replacement.id != original.id)
        #expect(replacement.title == original.title)
        #expect(replacement.tag == original.tag)
        #expect(replacement.urgency == original.urgency)
        #expect(replacement.deadline == newDeadline)
        #expect(replacement.recalledFromID == original.id)
        #expect(try await fixture.service.tasks(status: .ruined).isEmpty)

        let history = try #require(try await fixture.service.tasks(status: .recalled).first)
        #expect(history.id == original.id)
        #expect(history.recalledAt == recalledAt)

        let reloaded = TaskService(
            store: TaskStore(directoryURL: fixture.directory),
            nowProvider: FixedNowProvider(value: recalledAt)
        )
        _ = try await reloaded.start()
        #expect(try await reloaded.tasks(status: .active).first == replacement)
        #expect(try await reloaded.tasks(status: .recalled).first?.id == original.id)
    }

    @Test func burnDeletesOnlyRuinAndRepairsDanglingRecallLinks() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaterDropTodoBurnTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let ruinedID = UUID()
        let descendantID = UUID()
        let ruined = TaskRecord(
            id: ruinedID,
            title: "旧废墟",
            deadline: now.addingTimeInterval(-600),
            tag: .work,
            urgency: .medium,
            status: .ruined,
            createdAt: now.addingTimeInterval(-1_200),
            visualStartAt: now.addingTimeInterval(-1_200),
            completedAt: nil,
            ruinedAt: now.addingTimeInterval(-600),
            recalledAt: nil,
            recalledFromID: nil
        )
        let descendant = TaskRecord(
            id: descendantID,
            title: "后代",
            deadline: now.addingTimeInterval(600),
            tag: .work,
            urgency: .medium,
            status: .active,
            createdAt: now,
            visualStartAt: now,
            completedAt: nil,
            ruinedAt: nil,
            recalledAt: nil,
            recalledFromID: ruinedID
        )
        let store = TaskStore(directoryURL: directory)
        _ = try await store.load()
        _ = try await store.save(tasks: [ruined, descendant], savedAt: now)
        let service = TaskService(store: store, nowProvider: FixedNowProvider(value: now))
        _ = try await service.start()

        try await service.burn(id: ruinedID)

        let remaining = try await service.tasks(status: nil)
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == descendantID)
        #expect(remaining.first?.recalledFromID == nil)
    }

    @Test func clearAllRemovesRecordsAndPreviousBackup() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }
        _ = try await fixture.service.create(
            CreateTaskInput(title: "会被清除", deadline: now.addingTimeInterval(600), tag: nil)
        )
        _ = try await fixture.service.create(
            CreateTaskInput(title: "触发备份", deadline: now.addingTimeInterval(900), tag: nil)
        )

        try await fixture.service.clearAll()

        #expect(try await fixture.service.tasks(status: nil).isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("tasks.previous.json").path) == false)
        let reloaded = TaskService(
            store: TaskStore(directoryURL: fixture.directory),
            nowProvider: FixedNowProvider(value: now)
        )
        _ = try await reloaded.start()
        #expect(try await reloaded.tasks(status: nil).isEmpty)
    }

    @Test func oneHundredMixedMutationsSurviveTwentyReloads() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }

        var created: [TaskRecord] = []
        for index in 0..<100 {
            created.append(
                try await fixture.service.create(
                    CreateTaskInput(
                        title: "压力任务 \(index)",
                        deadline: now.addingTimeInterval(Double(600 + index)),
                        tag: TaskTag.allCases[index % TaskTag.allCases.count],
                        urgency: Urgency.allCases[index % Urgency.allCases.count]
                    )
                )
            )
        }

        for task in created[0..<25] {
            _ = try await fixture.service.complete(id: task.id, at: now.addingTimeInterval(120))
        }
        for task in created[25..<50] {
            try await fixture.service.cancel(id: task.id)
        }
        for task in created[50..<75] {
            try await fixture.service.update(
                id: task.id,
                changes: TaskChanges(title: "已更新 \(task.id.uuidString.prefix(8))", urgency: .high)
            )
        }

        for _ in 0..<20 {
            let reloaded = TaskService(
                store: TaskStore(directoryURL: fixture.directory),
                nowProvider: FixedNowProvider(value: now)
            )
            _ = try await reloaded.start()
            #expect(try await reloaded.tasks(status: .completed).count == 25)
            #expect(try await reloaded.tasks(status: .active).count == 50)
            #expect(try await reloaded.tasks(status: nil).count == 75)
        }
    }

    @Test func rapidRepeatedTerminalMutationsRemainConsistent() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try await makeService(now: now)
        defer { fixture.cleanup() }
        let completedCandidate = try await fixture.service.create(
            CreateTaskInput(title: "重复完成", deadline: now.addingTimeInterval(600), tag: nil)
        )

        let completionSuccesses = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do {
                        _ = try await fixture.service.complete(
                            id: completedCandidate.id,
                            at: now.addingTimeInterval(1)
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var successes = 0
            for await succeeded in group where succeeded { successes += 1 }
            return successes
        }
        #expect(completionSuccesses == 1)
        #expect(try await fixture.service.tasks(status: .completed).count == 1)

        let ruinCandidate = try await fixture.service.create(
            CreateTaskInput(title: "重复焚毁", deadline: now.addingTimeInterval(120), tag: nil)
        )
        _ = try await fixture.service.expireDueTasks(
            at: ruinCandidate.deadline.addingTimeInterval(1),
            excluding: []
        )
        let burnSuccesses = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do {
                        try await fixture.service.burn(id: ruinCandidate.id)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var successes = 0
            for await succeeded in group where succeeded { successes += 1 }
            return successes
        }
        #expect(burnSuccesses == 1)
        #expect(try await fixture.service.tasks(status: .ruined).isEmpty)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { try? await fixture.service.clearCompleted() }
            }
        }
        #expect(try await fixture.service.tasks(status: nil).isEmpty)

        let reloaded = TaskService(
            store: TaskStore(directoryURL: fixture.directory),
            nowProvider: FixedNowProvider(value: now)
        )
        _ = try await reloaded.start()
        #expect(try await reloaded.tasks(status: nil).isEmpty)
    }

    private func makeRecord(
        title: String,
        deadline: Date,
        tag: TaskTag?,
        createdAt: Date
    ) -> TaskRecord {
        TaskRecord(
            id: UUID(),
            title: title,
            deadline: deadline,
            tag: tag,
            urgency: .medium,
            status: .active,
            createdAt: createdAt,
            visualStartAt: createdAt,
            completedAt: nil,
            ruinedAt: nil,
            recalledAt: nil,
            recalledFromID: nil
        )
    }

    private func makeService(now: Date) async throws -> ServiceFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaterDropTodoTests-\(UUID().uuidString)", isDirectory: true)
        let service = TaskService(
            store: TaskStore(directoryURL: directory),
            nowProvider: FixedNowProvider(value: now)
        )
        _ = try await service.start()
        return ServiceFixture(directory: directory, service: service)
    }
}

private struct ServiceFixture: Sendable {
    let directory: URL
    let service: TaskService

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

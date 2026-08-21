import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var visibilityReason: NotchVisibilityReason = .unsupportedNoNotch
    @Published private(set) var geometrySummary = "尚未检测"
    @Published private(set) var transitionSummary = "尚未播放跨窗口动画"
    @Published private(set) var activeTasks: [TaskRecord] = []
    @Published private(set) var completedTasks: [TaskRecord] = []
    @Published private(set) var ruinedTasks: [TaskRecord] = []
    @Published private(set) var gardenSnapshot = GardenSnapshot.empty
    @Published private(set) var taskStoreReady = false
    @Published private(set) var taskErrorMessage: String?
    @Published private(set) var hideInFullscreen: Bool

    var onRequestQuickCapture: (() -> Void)?
    var onRequestSettings: (() -> Void)?
    private let windowCoordinator: WindowCoordinator
    private let taskService: TaskService
    private let gardenService: GardenService
    private lazy var timeEngine = TimeEngine(service: taskService)
    private var hasStartedTasks = false
    private var gardenServiceReady = false

    init(
        taskService: TaskService? = nil,
        gardenService: GardenService? = nil,
        applicationSupportURL: URL? = nil
    ) {
        let hideInFullscreen = UserDefaults.standard.object(forKey: "display.hideInFullscreen") as? Bool ?? true
        self.hideInFullscreen = hideInFullscreen
        self.windowCoordinator = WindowCoordinator()

        let directory: URL
        let arguments = ProcessInfo.processInfo.arguments
        if let applicationSupportURL {
            directory = applicationSupportURL
        } else if let benchmarkStoreName = arguments
            .first(where: { $0.hasPrefix("--m4-benchmark-store-name=") })?
            .replacingOccurrences(of: "--m4-benchmark-store-name=", with: ""),
            !benchmarkStoreName.isEmpty {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                benchmarkStoreName,
                isDirectory: true
            )
        } else if arguments.contains("--ui-testing") {
            let storeName = arguments
                .first { $0.hasPrefix("--ui-testing-store=") }?
                .replacingOccurrences(of: "--ui-testing-store=", with: "")
                ?? "WaterDropTodo-UITests-\(ProcessInfo.processInfo.processIdentifier)"
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                storeName,
                isDirectory: true
            )
        } else {
            directory = (try? TaskStore.applicationSupportDirectory())
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("WaterDropTodo-Recovery", isDirectory: true)
        }
        self.taskService = taskService ?? TaskService(store: TaskStore(directoryURL: directory))
        self.gardenService = gardenService ?? GardenService(
            store: GardenStore(directoryURL: directory)
        )
        self.windowCoordinator.setHideInFullscreen(hideInFullscreen)

        windowCoordinator.onDisplayStateChange = { [weak self] reason, geometry in
            guard let self else { return }
            visibilityReason = reason
            if let geometry {
                geometrySummary = "screen=\(geometry.screenID) notch=\(geometry.notchFrame.integral) render=\(geometry.renderFrame.integral)"
            } else {
                geometrySummary = reason.detail
            }
        }
        windowCoordinator.onTransitionStateChange = { [weak self] summary in
            self?.transitionSummary = summary
        }
        windowCoordinator.onProtectedTaskIDsChange = { [weak self] taskIDs in
            guard let self else { return }
            timeEngine.setProtectedTaskIDs(taskIDs)
            guard hasStartedTasks else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await timeEngine.reconcile(now: Date(), notifyExpiration: true)
                await refreshTasks()
            }
        }
        windowCoordinator.onCompleteTask = { [weak self] taskID, sourcePoint in
            guard let self else { return false }
            do {
                _ = try await completeAndAnimate(id: taskID, sourcePoint: sourcePoint)
                return true
            } catch {
                return false
            }
        }
    }

    @discardableResult
    func startDisplaySystem() -> NotchVisibilityReason {
        windowCoordinator.start()
    }

    func startTaskSystem() async {
        guard !hasStartedTasks else {
            await reconcileTime()
            return
        }

        do {
            let outcome = try await taskService.start()
            hasStartedTasks = true
            taskErrorMessage = nil
            switch outcome {
            case .empty:
                AppLog.info(.store, "store_started outcome=empty")
            case .loaded:
                AppLog.info(.store, "store_started outcome=loaded")
            case let .recoveredFromPrevious(corruptCopy):
                AppLog.error(.store, "store_recovered corrupt_copy=\(corruptCopy.lastPathComponent)")
            }

            try await seedRuinedTaskForUITestingIfNeeded()
            try await seedM4BenchmarkTasksIfNeeded()

            let records = try await taskService.tasks(status: nil)
            gardenSnapshot = try await gardenService.start(
                taskStatuses: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.status) })
            )
            gardenServiceReady = true
            windowCoordinator.updateGarden(gardenSnapshot)

            timeEngine.onExpiration = { [weak self] snapshots in
                guard let self else { return }
                windowCoordinator.playExpirationTransitions(snapshots)
                Task { @MainActor in await self.refreshTasks() }
            }
            timeEngine.onError = { [weak self] error in
                self?.taskErrorMessage = error.localizedDescription
                AppLog.error(.time, "reconcile_failed error=\(error.localizedDescription)")
            }
            await timeEngine.start()
            await refreshTasks()
            taskStoreReady = true
        } catch {
            taskStoreReady = false
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "store_start_failed error=\(error.localizedDescription)")
        }
    }

    private func seedRuinedTaskForUITestingIfNeeded() async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing-seed-ruin") else { return }
        let existing = try await taskService.tasks(status: nil)
        guard existing.isEmpty else { return }
        let now = Date()
        let task = try await taskService.create(
            CreateTaskInput(
                title: "稳定性测试废墟",
                // Keep the fixture clear of the service's one-minute minimum.
                // Using exactly 60 seconds is flaky because validation samples a later Date().
                deadline: now.addingTimeInterval(120),
                tag: .work,
                urgency: .medium
            )
        )
        _ = try await taskService.expireDueTasks(
            at: task.deadline.addingTimeInterval(1),
            excluding: []
        )
    }

    private func seedM4BenchmarkTasksIfNeeded() async throws {
        let argument = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--m4-benchmark-tasks=") }?
            .replacingOccurrences(of: "--m4-benchmark-tasks=", with: "")
        guard let argument,
              let requestedCount = Int(argument),
              (1...8).contains(requestedCount) else { return }
        let existing = try await taskService.tasks(status: nil)
        guard existing.isEmpty else { return }

        let now = Date()
        for index in 0..<requestedCount {
            _ = try await taskService.create(
                CreateTaskInput(
                    title: String(format: "M4 基准任务 %02d", index + 1),
                    deadline: now.addingTimeInterval(Double(3_600 + index * 600)),
                    tag: TaskTag.allCases[index % TaskTag.allCases.count],
                    urgency: Urgency.allCases[index % Urgency.allCases.count]
                )
            )
        }
        AppLog.info(.store, "benchmark_fixture_seeded count=\(requestedCount)")
        FileHandle.standardOutput.write(
            Data("M4_BENCHMARK_READY count=\(requestedCount)\n".utf8)
        )
    }

    @discardableResult
    func createTask(_ input: CreateTaskInput) async throws -> TaskRecord {
        let record = try await taskService.create(input)
        AppLog.info(.store, "task_created id=\(record.id.uuidString) status=active")
        await refreshTasks()
        await timeEngine.reconcile(now: Date())
        return record
    }

    func updateTask(id: UUID, changes: TaskChanges) async throws {
        do {
            try await taskService.update(id: id, changes: changes)
            AppLog.info(.store, "task_updated id=\(id.uuidString) status=active")
            await refreshTasks()
            await timeEngine.reconcile(now: Date())
        } catch {
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "task_update_failed id=\(id.uuidString) error=\(error.localizedDescription)")
            throw error
        }
    }

    @discardableResult
    func completeTask(id: UUID) async throws -> CompletionSnapshot {
        let sourcePoint = windowCoordinator.completionSourceForListTask(taskID: id)
        return try await completeAndAnimate(id: id, sourcePoint: sourcePoint)
    }

    private func completeAndAnimate(id: UUID, sourcePoint: CGPoint) async throws -> CompletionSnapshot {
        let completedAt = Date()
        let event: PendingGardenEvent
        do {
            guard gardenServiceReady else { throw GardenServiceError.notStarted }
            event = try await gardenService.prepare(
                taskID: id,
                completedAt: completedAt,
                impactNormalizedX: windowCoordinator.completionImpactNormalizedX(from: sourcePoint)
            )
        } catch {
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "garden_prepare_failed id=\(id.uuidString) error=\(error.localizedDescription)")
            throw error
        }

        let snapshot: CompletionSnapshot
        do {
            snapshot = try await taskService.complete(id: id, at: completedAt)
            AppLog.info(.store, "task_completed id=\(id.uuidString) status=completed")
        } catch {
            try? await gardenService.cancel(taskID: id)
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "task_complete_failed id=\(id.uuidString) error=\(error.localizedDescription)")
            throw error
        }

        do {
            let result = try await gardenService.commit(taskID: id, at: completedAt)
            gardenSnapshot = result.snapshot
            windowCoordinator.enqueueCompletionGardenAnimation(
                from: sourcePoint,
                event: event,
                result: result
            )
        } catch {
            AppLog.error(.store, "garden_commit_deferred id=\(id.uuidString) error=\(error.localizedDescription)")
        }
        await refreshTasks()
        await timeEngine.reconcile(now: Date())
        return snapshot
    }

    func cancelTask(id: UUID) async throws {
        do {
            try await taskService.cancel(id: id)
            AppLog.info(.store, "task_cancelled id=\(id.uuidString) status=deleted")
            await refreshTasks()
            await timeEngine.reconcile(now: Date())
        } catch {
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "task_cancel_failed id=\(id.uuidString) error=\(error.localizedDescription)")
            throw error
        }
    }

    func clearCompletedTasks() async throws {
        do {
            let count = completedTasks.count
            try await taskService.clearCompleted()
            AppLog.info(.store, "completed_cleared count=\(count)")
            await refreshTasks()
        } catch {
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "completed_clear_failed error=\(error.localizedDescription)")
            throw error
        }
    }

    func clearAllTasks() async throws {
        do {
            try await taskService.clearAll()
            if gardenServiceReady {
                gardenSnapshot = try await gardenService.clearAll()
                windowCoordinator.updateGarden(gardenSnapshot)
            }
            AppLog.info(.store, "all_tasks_cleared")
            await refreshTasks()
            await timeEngine.reconcile(now: Date())
        } catch {
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "all_tasks_clear_failed error=\(error.localizedDescription)")
            throw error
        }
    }

    func exportTasksJSON() async throws -> URL? {
        let records = try await taskService.tasks(status: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let envelope = StoreEnvelope(savedAt: Date(), tasks: records)
        return try saveExportData(
            encoder.encode(envelope),
            suggestedName: "WaterDropTodo-tasks.json"
        )
    }

    func exportRecentLogs() async throws -> URL? {
        let since = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let data = try await LocalLogBuffer.shared.exportData(since: since)
        return try saveExportData(
            data,
            suggestedName: "WaterDropTodo-diagnostics-7days.json"
        )
    }

    private func saveExportData(_ data: Data, suggestedName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func recallTask(id: UUID, newDeadline: Date) async throws -> TaskRecord {
        do {
            let record = try await taskService.recall(id: id, newDeadline: newDeadline, at: Date())
            AppLog.info(.store, "task_recalled old_id=\(id.uuidString) new_id=\(record.id.uuidString)")
            await refreshTasks()
            await timeEngine.reconcile(now: Date())
            return record
        } catch {
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "task_recall_failed id=\(id.uuidString) error=\(error.localizedDescription)")
            throw error
        }
    }

    func burnTask(id: UUID) async throws {
        do {
            try await taskService.burn(id: id)
            AppLog.info(.store, "task_burned id=\(id.uuidString)")
            await refreshTasks()
        } catch {
            taskErrorMessage = error.localizedDescription
            AppLog.error(.store, "task_burn_failed id=\(id.uuidString) error=\(error.localizedDescription)")
            throw error
        }
    }

    func refreshTasks() async {
        guard hasStartedTasks else { return }
        do {
            activeTasks = try await taskService.tasks(status: .active)
            windowCoordinator.updateActiveTasks(activeTasks)
            completedTasks = try await taskService.tasks(status: .completed)
            ruinedTasks = try await taskService.tasks(status: .ruined)
            taskErrorMessage = nil
        } catch {
            taskErrorMessage = error.localizedDescription
        }
    }

    func reconcileTime() async {
        guard hasStartedTasks else { return }
        AppLog.info(.time, "reconcile_started")
        await timeEngine.reconcile(now: Date())
        await refreshTasks()
    }

    var ruinedCount: Int { ruinedTasks.count }
    var gardenCoveragePercent: Int { Int((gardenSnapshot.coverageFraction * 100).rounded()) }

    func requestQuickCapture() {
        onRequestQuickCapture?()
    }

    func requestSettings() {
        onRequestSettings?()
    }

    func refreshDisplayPolicy() {
        windowCoordinator.refresh()
    }

    func setHideInFullscreen(_ enabled: Bool) {
        hideInFullscreen = enabled
        UserDefaults.standard.set(enabled, forKey: "display.hideInFullscreen")
        windowCoordinator.setHideInFullscreen(enabled)
    }

    func updateListSourceFrame(_ frame: CGRect) {
        windowCoordinator.updateListSourceFrame(frame)
    }

    func updateTaskRowFrame(taskID: UUID, frame: CGRect) {
        windowCoordinator.updateTaskRowFrame(taskID: taskID, frame: frame)
    }

    func playNotchTransition() {
        windowCoordinator.playNotchTransition()
    }

    func playListTransition() {
        windowCoordinator.playListTransition()
    }

}

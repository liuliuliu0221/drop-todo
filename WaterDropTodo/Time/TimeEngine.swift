import Foundation

@MainActor
final class TimeEngine {
    typealias ExpirationHandler = @MainActor ([ExpirationSnapshot]) -> Void
    typealias ErrorHandler = @MainActor (Error) -> Void

    var onExpiration: ExpirationHandler?
    var onError: ErrorHandler?

    private let service: any TaskServicing
    private let nowProvider: any NowProviding
    private var timer: Timer?
    private var protectedTaskIDs: Set<UUID> = []

    init(
        service: any TaskServicing,
        nowProvider: any NowProviding = SystemNowProvider()
    ) {
        self.service = service
        self.nowProvider = nowProvider
    }

    func start() async {
        await reconcile(now: nowProvider.now(), notifyExpiration: false)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setProtectedTaskIDs(_ ids: Set<UUID>) {
        protectedTaskIDs = ids
    }

    func reconcile(now: Date, notifyExpiration: Bool = false) async {
        stop()
        do {
            let snapshots = try await service.expireDueTasks(
                at: now,
                excluding: protectedTaskIDs
            )
            if notifyExpiration, !snapshots.isEmpty {
                onExpiration?(snapshots)
            }
            let active = try await service.tasks(status: .active)
            schedule(
                deadline: Self.nextDeadline(
                    in: active,
                    after: now,
                    excluding: protectedTaskIDs
                )
            )
        } catch {
            onError?(error)
        }
    }

    nonisolated static func nextDeadline(
        in tasks: [TaskRecord],
        after date: Date,
        excluding protectedTaskIDs: Set<UUID> = []
    ) -> Date? {
        tasks.lazy
            .filter {
                $0.status == .active
                    && $0.deadline > date
                    && !protectedTaskIDs.contains($0.id)
            }
            .map(\.deadline)
            .min()
    }

    private func schedule(deadline: Date?) {
        guard let deadline else { return }
        let interval = max(0, deadline.timeIntervalSince(nowProvider.now()))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.reconcile(now: self.nowProvider.now(), notifyExpiration: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

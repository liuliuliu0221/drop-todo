import AppKit

@MainActor
final class WindowCoordinator: NSObject {
    typealias DisplayStateHandler = (NotchVisibilityReason, NotchGeometry?) -> Void
    typealias TransitionStateHandler = (String) -> Void
    typealias ProtectionHandler = (Set<UUID>) -> Void
    typealias CompletionHandler = (UUID, CGPoint) async -> Bool

    var onDisplayStateChange: DisplayStateHandler?
    var onTransitionStateChange: TransitionStateHandler?
    var onProtectedTaskIDsChange: ProtectionHandler?
    var onCompleteTask: CompletionHandler?
    var onAquariumImpact: ((Bool) -> Void)?

    private let displayPolicy: DisplayPolicy
    private let renderPanel: NotchRenderPanel
    private let hitTestCoordinator: HitTestCoordinator
    private let layoutEngine = NotchLayoutEngine()
    private let transitionPanel = TransitionOverlayPanel()
    private let expirationPanel = ExpirationOverlayPanel()
    private let hoverCardPanel = HoverCardPanel()
    private let hoverCorridorPanel = HoverCorridorPanel()
    private var currentGeometry: NotchGeometry?
    private var currentLayout = NotchLayoutSnapshot.empty(at: .distantPast, contentWidth: 177)
    private var activeTasks: [TaskRecord] = []
    private var taskRowFrames: [UUID: CGRect] = [:]
    private var aquariumFrame: CGRect?
    private var aquariumIsVisible = false
    private var hoveredTaskID: UUID?
    private var hoveredHitTargetIDs: Set<UUID> = []
    private var currentHitTargets: [UUID: DropletHitTarget] = [:]
    private var cardSession = HoverCardSession()
    private var cardFrame: CGRect?
    private var corridorFrame: CGRect?
    private var isCardHovered = false
    private var isCorridorHovered = false
    private var isCompleting = false
    private var presentationWorkItem: DispatchWorkItem?
    private var dismissalWorkItem: DispatchWorkItem?
    private var protectionWorkItem: DispatchWorkItem?
    private var localEventMonitor: Any?
    private var globalMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var layoutTimer: Timer?
    private var listSourceFrame: CGRect?
    private var isObserving = false
    private var hideInFullscreen = true

    init(
        displayPolicy: DisplayPolicy = DisplayPolicy()
    ) {
        self.displayPolicy = displayPolicy
        self.renderPanel = NotchRenderPanel()
        self.hitTestCoordinator = HitTestCoordinator()
        super.init()
        self.hitTestCoordinator.setHoverHandler { [weak self] taskID, isHovering in
            self?.handleDropletHover(taskID: taskID, isHovering: isHovering)
        }
        self.hitTestCoordinator.setClickHandler { [weak self] taskID in
            self?.handleDropletClick(taskID: taskID)
        }
    }

    @discardableResult
    func start() -> NotchVisibilityReason {
        installObserversIfNeeded()
        installInteractionMonitorsIfNeeded()
        return refresh()
    }

    @discardableResult
    func refresh() -> NotchVisibilityReason {
        let snapshot = DisplaySnapshot.capture()
        let reason = displayPolicy.visibility(
            for: snapshot,
            hideInFullscreen: hideInFullscreen && Self.frontmostAppIsFullscreen()
        )

        guard reason == .visible,
              let geometry = NSScreen.screens.compactMap(NotchGeometry.init(screen:)).first else {
            currentGeometry = nil
            stopLayoutUpdates()
            closeCardSession()
            renderPanel.hide()
            hitTestCoordinator.hideAll()
            onDisplayStateChange?(reason, nil)
            return reason
        }

        currentGeometry = geometry
        renderPanel.show(geometry: geometry)
        updateLayout(now: Date())
        startLayoutUpdatesIfNeeded()
        onDisplayStateChange?(reason, geometry)
        return reason
    }

    func updateActiveTasks(_ tasks: [TaskRecord]) {
        activeTasks = tasks
        if let taskID = cardSession.taskID {
            if let task = tasks.first(where: { $0.id == taskID }) {
                cardSession.updateTask(task)
            } else {
                closeCardSession()
            }
        }
        updateLayout(now: Date())
        startLayoutUpdatesIfNeeded()
    }

    func updateListSourceFrame(_ frame: CGRect) {
        listSourceFrame = frame
    }

    func updateTaskRowFrame(taskID: UUID, frame: CGRect) {
        taskRowFrames[taskID] = frame
    }

    func updateAquarium(frame: CGRect?, isVisible: Bool) {
        aquariumFrame = frame
        aquariumIsVisible = isVisible
    }

    func setHideInFullscreen(_ enabled: Bool) {
        hideInFullscreen = enabled
        if isObserving { refresh() }
    }

    func playNotchTransition() {
        guard let geometry = currentGeometry else {
            onTransitionStateChange?("刘海测试点当前不可用。")
            return
        }
        let start = CGPoint(x: geometry.notchFrame.midX, y: geometry.notchFrame.minY - 18)
        playTransition(from: start, source: .notch)
    }

    func playListTransition() {
        guard let frame = listSourceFrame, !frame.isEmpty else {
            onTransitionStateChange?("尚未获取 SwiftUI 列表行的屏幕坐标。")
            return
        }
        playTransition(
            from: CGPoint(x: frame.midX, y: frame.midY),
            source: .listRow
        )
    }

    func playCompletionTransition(from point: CGPoint) {
        playTransition(from: point, source: .notch)
    }

    func playListCompletionTransition(taskID: UUID) {
        guard let frame = taskRowFrames[taskID], !frame.isEmpty else {
            onTransitionStateChange?("列表任务已完成；来源坐标不可用，跳过飞行动画。")
            return
        }
        playTransition(from: CGPoint(x: frame.midX, y: frame.midY), source: .listRow)
    }

    func playExpirationTransitions(_ snapshots: [ExpirationSnapshot]) {
        guard let screen = NSScreen.screens.first, NSScreen.screens.count == 1 else { return }
        let requests = snapshots.compactMap { snapshot -> ExpirationAnimationRequest? in
            guard let source = currentHitTargets[snapshot.taskID]?.frame.center else { return nil }
            return ExpirationAnimationRequest(taskID: snapshot.taskID, source: source)
        }
        guard !requests.isEmpty else { return }
        let overlayFrame = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        expirationPanel.animate(
            requests: Array(requests.prefix(5)),
            overlayFrame: overlayFrame,
            backingScale: screen.backingScaleFactor
        )
        onTransitionStateChange?("在线到期：正在播放 \(min(requests.count, 5)) 个水滴坠落")
    }

    private func installObserversIfNeeded() {
        guard !isObserving else { return }
        isObserving = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDisplayChange),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDisplayChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    private func installInteractionMonitorsIfNeeded() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .keyDown]
        ) { [weak self] event in
            Task { @MainActor in self?.handleInteractionEvent(event) }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            Task { @MainActor in self?.handleInteractionEvent(event) }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            Task { @MainActor in self?.handleInteractionEvent(event) }
        }
    }

    private func handleInteractionEvent(_ event: NSEvent) {
        guard cardSession.isPresented else { return }
        if event.type == .keyDown, event.keyCode == 53 {
            closeCardSession()
            return
        }
        guard event.type == .leftMouseDown else { return }
        let location = NSEvent.mouseLocation
        guard !interactiveFrames.contains(where: { $0.contains(location) }) else { return }
        closeCardSession()
    }

    @objc private func handleDisplayChange(_ notification: Notification) {
        transitionPanel.cancel()
        expirationPanel.cancel()
        onTransitionStateChange?("屏幕配置变化，跨窗口动画已安全取消。")
        refresh()
    }

    @objc private func handleScreensSleep(_ notification: Notification) {
        stopLayoutUpdates()
        closeCardSession()
        renderPanel.hide()
        hitTestCoordinator.hideAll()
        transitionPanel.cancel()
        expirationPanel.cancel()
        onTransitionStateChange?("屏幕休眠，跨窗口动画已安全取消。")
    }

    private func playTransition(from start: CGPoint, source: TransitionSourceKind) {
        let screens = NSScreen.screens
        guard screens.count == 1, let screen = screens.first else {
            onTransitionStateChange?("MVP 仅在单显示器环境播放跨窗口动画。")
            return
        }

        let overlayFrame = screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let target = aquariumFrame.map {
            CGPoint(x: $0.midX, y: $0.minY + $0.height * 0.68)
        } ?? start
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let mode = TransitionAnimationPolicy.mode(
            aquariumIsVisible: aquariumIsVisible && aquariumFrame != nil,
            reduceMotion: reduceMotion
        )
        let destination = mode == .travel ? "鱼缸" : "源位置淡出"
        onTransitionStateChange?("正在播放：\(source.rawValue) → \(destination)")
        transitionPanel.animate(
            screenRoute: TransitionRoute(start: start, target: target),
            source: source,
            overlayFrame: overlayFrame,
            backingScale: screen.backingScaleFactor,
            mode: mode,
            duration: mode == .travel ? 0.8 : 0.25
        ) { [weak self] metrics in
            if self?.aquariumIsVisible == true {
                self?.onAquariumImpact?(mode == .fadeAtSource)
            }
            self?.onTransitionStateChange?(
                "完成：\(metrics.source.rawValue)，scale=\(String(format: "%.1f", metrics.backingScale))，落点误差=\(String(format: "%.3f", metrics.endpointError))pt"
            )
        }
    }

    private func updateLayout(now: Date) {
        guard let geometry = currentGeometry else { return }
        let snapshot = layoutEngine.snapshot(
            tasks: activeTasks,
            now: now,
            contentWidth: geometry.renderFrame.width,
            fixedTaskIDs: Set(hoveredTaskID.map { [$0] } ?? [])
        )
        currentLayout = snapshot
        if let hoveredTaskID, !snapshot.items.contains(where: { $0.id == hoveredTaskID }) {
            self.hoveredTaskID = nil
        }
        renderPanel.update(snapshot: snapshot, hoveredTaskID: hoveredTaskID)

        let targets = HitTestCoordinator.disambiguatedTargets(
            hitTargets(for: snapshot, geometry: geometry)
        )
        currentHitTargets = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })

        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            hitTestCoordinator.hideAll()
        } else {
            hitTestCoordinator.apply(targets)
        }
        if cardSession.isPresented {
            showCardPanels()
        }
    }

    private func startLayoutUpdatesIfNeeded() {
        guard currentGeometry != nil, !activeTasks.isEmpty else {
            stopLayoutUpdates()
            return
        }
        guard layoutTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLayout(now: Date())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        layoutTimer = timer
    }

    private func stopLayoutUpdates() {
        layoutTimer?.invalidate()
        layoutTimer = nil
    }

    private func hitTargets(
        for snapshot: NotchLayoutSnapshot,
        geometry: NotchGeometry
    ) -> [DropletHitTarget] {
        let size = CGSize(width: NotchLayoutEngine.hitTargetWidth, height: 25)
        let y = geometry.notchFrame.minY - size.height + 7
        return snapshot.items.enumerated().map { index, item in
            return DropletHitTarget(
                id: item.id,
                index: index,
                frame: CGRect(
                    x: geometry.renderFrame.minX + item.resolvedX - size.width / 2,
                    y: y,
                    width: size.width,
                    height: size.height
                )
            )
        }
    }

    private func handleDropletHover(taskID: UUID, isHovering: Bool) {
        if isHovering {
            hoveredHitTargetIDs.insert(taskID)
            dismissalWorkItem?.cancel()
            guard cardSession.taskID != taskID else {
                setHoveredTask(taskID)
                return
            }
            closeCardSession()
            guard let task = activeTasks.first(where: { $0.id == taskID }) else { return }
            cardSession.begin(task: task, now: Date())
            notifyProtectedTaskIDs()
            setHoveredTask(taskID)
            schedulePresentation(for: taskID)
        } else {
            hoveredHitTargetIDs.remove(taskID)
            guard cardSession.taskID == taskID else { return }
            if cardSession.phase == .hoverPending {
                closeCardSession()
            } else {
                scheduleDismissalIfNeeded()
            }
        }
    }

    private func handleDropletClick(taskID: UUID) {
        dismissalWorkItem?.cancel()
        if cardSession.taskID != taskID {
            closeCardSession()
            guard let task = activeTasks.first(where: { $0.id == taskID }) else { return }
            cardSession.begin(task: task, now: Date())
            notifyProtectedTaskIDs()
        }
        presentationWorkItem?.cancel()
        cardSession.present()
        cardSession.pin()
        setHoveredTask(taskID)
        scheduleProtectionTimer()
        showCardPanels()
    }

    private func schedulePresentation(for taskID: UUID) {
        presentationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, cardSession.taskID == taskID else { return }
            cardSession.present()
            scheduleProtectionTimer()
            showCardPanels()
        }
        presentationWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + HoverCardSession.presentationDelay,
            execute: item
        )
    }

    private func scheduleProtectionTimer() {
        protectionWorkItem?.cancel()
        guard let end = cardSession.protectionEndsAt else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let oldIDs = cardSession.protectedTaskIDs
            cardSession.protectionTimerFired(now: Date())
            if oldIDs != cardSession.protectedTaskIDs {
                notifyProtectedTaskIDs()
            }
            showCardPanels()
        }
        protectionWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, end.timeIntervalSinceNow),
            execute: item
        )
    }

    private func scheduleDismissalIfNeeded() {
        guard cardSession.isPresented, !cardSession.isPinned else { return }
        dismissalWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if interactiveFrames.contains(where: { $0.contains(NSEvent.mouseLocation) }) {
                scheduleDismissalIfNeeded()
            } else {
                closeCardSession()
            }
        }
        dismissalWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + HoverCardSession.dismissalDelay,
            execute: item
        )
    }

    private func showCardPanels() {
        guard cardSession.isPresented,
              let task = cardSession.task,
              let target = currentHitTargets[task.id],
              let frames = cardFrames(anchor: target.frame) else {
            hoverCardPanel.orderOut(nil)
            hoverCorridorPanel.orderOut(nil)
            cardFrame = nil
            corridorFrame = nil
            return
        }

        cardFrame = frames.card
        corridorFrame = frames.corridor
        hoverCardPanel.show(
            content: HoverCardContent(
                task: task,
                frozenRemainingTime: cardSession.frozenRemainingTime,
                isGraceExpired: cardSession.phase == .graceExpired,
                isCompleting: isCompleting
            ),
            frame: frames.card,
            receivesEscape: cardSession.isPinned || cardSession.phase == .graceExpired,
            onHover: { [weak self] hovering in self?.handleCardHover(hovering) },
            onDismiss: { [weak self] in self?.closeCardSession() },
            onComplete: { [weak self] in self?.handleCardComplete() }
        )
        if frames.corridor.width > 0, frames.corridor.height > 0 {
            hoverCorridorPanel.show(
                frame: frames.corridor,
                onHover: { [weak self] hovering in self?.handleCorridorHover(hovering) }
            )
        } else {
            hoverCorridorPanel.orderOut(nil)
        }
    }

    private func handleCardHover(_ isHovering: Bool) {
        isCardHovered = isHovering
        if isHovering {
            dismissalWorkItem?.cancel()
        } else {
            scheduleDismissalIfNeeded()
        }
    }

    private func handleCorridorHover(_ isHovering: Bool) {
        isCorridorHovered = isHovering
        if isHovering {
            dismissalWorkItem?.cancel()
        } else {
            scheduleDismissalIfNeeded()
        }
    }

    private func handleCardComplete() {
        guard cardSession.isCompletionEnabled,
              !isCompleting,
              let taskID = cardSession.taskID,
              let handler = onCompleteTask else { return }
        isCompleting = true
        showCardPanels()
        let source = currentHitTargets[taskID]?.frame.center ?? .zero
        Task { @MainActor [weak self] in
            let succeeded = await handler(taskID, source)
            guard let self else { return }
            isCompleting = false
            if succeeded {
                closeCardSession()
            } else {
                showCardPanels()
            }
        }
    }

    private func closeCardSession() {
        let oldProtectedIDs = cardSession.protectedTaskIDs
        presentationWorkItem?.cancel()
        dismissalWorkItem?.cancel()
        protectionWorkItem?.cancel()
        presentationWorkItem = nil
        dismissalWorkItem = nil
        protectionWorkItem = nil
        hoverCardPanel.orderOut(nil)
        hoverCorridorPanel.orderOut(nil)
        cardFrame = nil
        corridorFrame = nil
        isCardHovered = false
        isCorridorHovered = false
        isCompleting = false
        cardSession.close()
        if !oldProtectedIDs.isEmpty {
            notifyProtectedTaskIDs()
        }
        setHoveredTask(nil)
    }

    private func setHoveredTask(_ taskID: UUID?) {
        hoveredTaskID = taskID
        renderPanel.update(snapshot: currentLayout, hoveredTaskID: hoveredTaskID)
    }

    private func notifyProtectedTaskIDs() {
        onProtectedTaskIDsChange?(cardSession.protectedTaskIDs)
    }

    private func cardFrames(anchor: CGRect) -> (card: CGRect, corridor: CGRect)? {
        let screen = currentGeometry.flatMap { geometry in
            NSScreen.screens.first { $0.displayID == geometry.screenID }
        } ?? NSScreen.main
        guard let screen else { return nil }
        let visible = screen.visibleFrame
        let size = HoverCardPanel.cardSize
        let gap: CGFloat = 8
        let preferredRightX = anchor.maxX + gap
        let useRight = preferredRightX + size.width <= visible.maxX - gap
        let x = useRight ? preferredRightX : anchor.minX - gap - size.width
        let y = max(visible.minY + gap, min(anchor.maxY - size.height, visible.maxY - size.height - gap))
        let card = CGRect(origin: CGPoint(x: x, y: y), size: size)
        let corridorX = useRight ? anchor.maxX : card.maxX
        let corridorWidth = useRight ? card.minX - anchor.maxX : anchor.minX - card.maxX
        let corridor = CGRect(
            x: corridorX,
            y: min(anchor.minY, card.minY),
            width: max(0, corridorWidth),
            height: max(anchor.maxY, card.maxY) - min(anchor.minY, card.minY)
        )
        return (card, corridor)
    }

    private var interactiveFrames: [CGRect] {
        var frames: [CGRect] = []
        if let taskID = cardSession.taskID, let target = currentHitTargets[taskID] {
            frames.append(target.frame)
        }
        if let cardFrame { frames.append(cardFrame) }
        if let corridorFrame { frames.append(corridorFrame) }
        return frames
    }

    private static func frontmostAppIsFullscreen() -> Bool {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let screen = NSScreen.main,
              let windowInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windowInfo.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == frontmostPID,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let values = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let width = values["Width"]?.doubleValue,
                  let height = values["Height"]?.doubleValue else { return false }
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            return abs(bounds.width - screen.frame.width) <= 2
                && abs(bounds.height - screen.frame.height) <= 2
        }
    }

}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

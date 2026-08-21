import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
final class ShellWindowCoordinator: NSObject, NSMenuDelegate, NSWindowDelegate {
    static let onboardingKey = "hasCompletedM1Welcome"
    private static let installedDefaultShortcutKey = "hasInstalledDefaultQuickCaptureShortcut"
    private static let aquariumVisibleKey = "aquarium.isVisible"

    private let environment: AppEnvironment
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var quickCapturePanel: QuickCapturePanel?
    private var aquariumPanel: AquariumPanel?
    private let aquariumPlacementStore = AquariumPlacementStore()
    private var aquariumIsAdjusting = false
    private var cancellables: Set<AnyCancellable> = []

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    func start() {
        AppLog.info(.app, "application_shell_started")
        configureStatusItem()
        configureEnvironmentCallbacks()
        configureShortcut()
        observeTaskSummary()
        installAquariumObservers()
        UserDefaults.standard.register(defaults: [Self.aquariumVisibleKey: true])
        if UserDefaults.standard.bool(forKey: Self.aquariumVisibleKey) {
            showAquarium()
        } else {
            environment.updateAquariumState(frame: nil, isVisible: false, isAdjusting: false)
        }

        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("--ui-testing")
        let isM4Benchmark = arguments.contains { $0.hasPrefix("--m4-benchmark-") }
        let completedWelcome = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        if isUITesting || (!completedWelcome && !isM4Benchmark) {
            showMainWindow()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildStatusMenu()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === mainWindow {
            mainWindow = nil
        } else if window === settingsWindow {
            settingsWindow = nil
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? AquariumPanel,
              panel === aquariumPanel else { return }
        environment.updateAquariumState(
            frame: panel.frame,
            isVisible: panel.isVisible,
            isAdjusting: aquariumIsAdjusting
        )
    }

    @objc func showQuickCapture() {
        presentQuickCapture(requestedAt: ProcessInfo.processInfo.systemUptime)
    }

    private func presentQuickCapture(requestedAt: TimeInterval) {
        AppLog.info(.window, "quick_capture_presented")
        let panel = quickCapturePanel ?? makeQuickCapturePanel()
        panel.contentView = NSHostingView(
            rootView: QuickCaptureView(
                presentationRequestedAt: requestedAt,
                onCancel: { [weak panel] in panel?.orderOut(nil) },
                onCreated: { [weak self, weak panel] in
                    panel?.orderOut(nil)
                    self?.rebuildStatusMenu()
                }
        )
        .environmentObject(environment)
        )
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func showMainWindow() {
        AppLog.info(.window, "main_window_presented")
        let window = mainWindow ?? makeMainWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() {
        AppLog.info(.window, "settings_window_presented")
        let window = settingsWindow ?? makeSettingsWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleAquarium() {
        if aquariumPanel?.isVisible == true {
            finishAquariumAdjustmentIfNeeded()
            aquariumPanel?.hideAquarium()
            UserDefaults.standard.set(false, forKey: Self.aquariumVisibleKey)
            environment.updateAquariumState(frame: aquariumPanel?.frame, isVisible: false, isAdjusting: false)
        } else {
            UserDefaults.standard.set(true, forKey: Self.aquariumVisibleKey)
            showAquarium()
        }
        rebuildStatusMenu()
    }

    @objc func toggleAquariumAdjustment() {
        guard let panel = aquariumPanel, panel.isVisible else { return }
        aquariumIsAdjusting.toggle()
        panel.setAdjustmentMode(aquariumIsAdjusting)
        if !aquariumIsAdjusting, let screen = panel.screen ?? NSScreen.main {
            aquariumPlacementStore.save(frame: panel.frame, on: screen)
        }
        environment.updateAquariumState(
            frame: panel.frame,
            isVisible: true,
            isAdjusting: aquariumIsAdjusting
        )
        rebuildStatusMenu()
    }

    @objc func terminateApplication() {
        NSApp.terminate(nil)
    }

    @objc private func handleScreensSleep(_ notification: Notification) {
        aquariumPanel?.pauseAnimation()
    }

    @objc private func handleScreensWake(_ notification: Notification) {
        aquariumPanel?.resumeAnimation()
    }

    @objc private func handleScreenConfigurationChange(_ notification: Notification) {
        guard let panel = aquariumPanel,
              let screen = NSScreen.main else { return }
        let frame = aquariumPlacementStore.frame(for: screen)
        panel.setFrame(AquariumPlacementGeometry.clamped(frame, to: screen.visibleFrame), display: true)
        if panel.isVisible { panel.showAquarium() }
        environment.updateAquariumState(
            frame: panel.frame,
            isVisible: panel.isVisible,
            isAdjusting: aquariumIsAdjusting
        )
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "水滴待办")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "水滴待办"
        }
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        rebuildStatusMenu()
    }

    private func configureEnvironmentCallbacks() {
        environment.onRequestQuickCapture = { [weak self] in
            self?.showQuickCapture()
        }
        environment.onRequestSettings = { [weak self] in
            self?.showSettings()
        }
        environment.onRequestToggleAquarium = { [weak self] in
            self?.toggleAquarium()
        }
        environment.onRequestToggleAquariumAdjustment = { [weak self] in
            self?.toggleAquariumAdjustment()
        }
        environment.onAquariumImpact = { [weak self] reducedMotion in
            self?.aquariumPanel?.triggerImpact(reducedMotion: reducedMotion)
        }
    }

    private func configureShortcut() {
        if !UserDefaults.standard.bool(forKey: Self.installedDefaultShortcutKey) {
            if KeyboardShortcuts.getShortcut(for: .quickCapture) == nil {
                KeyboardShortcuts.setShortcut(
                    .init(.t, modifiers: [.option]),
                    for: .quickCapture
                )
            }
            UserDefaults.standard.set(true, forKey: Self.installedDefaultShortcutKey)
        }
        KeyboardShortcuts.onKeyUp(for: .quickCapture) { [weak self] in
            let requestedAt = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in self?.presentQuickCapture(requestedAt: requestedAt) }
        }
    }

    private func installAquariumObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenConfigurationChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observeTaskSummary() {
        environment.$activeTasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildStatusMenu() }
            .store(in: &cancellables)
        environment.$visibilityReason
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildStatusMenu() }
            .store(in: &cancellables)
    }

    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()

        let countItem = NSMenuItem(
            title: "进行中：\(environment.activeTasks.count)",
            action: nil,
            keyEquivalent: ""
        )
        countItem.isEnabled = false
        statusMenu.addItem(countItem)

        if environment.visibilityReason != .visible {
            let displayItem = NSMenuItem(
                title: environment.visibilityReason.title,
                action: nil,
                keyEquivalent: ""
            )
            displayItem.isEnabled = false
            statusMenu.addItem(displayItem)
        }

        let nearestTitle: String
        if let nearest = environment.activeTasks.first {
            nearestTitle = "最近：\(nearest.deadline.formatted(date: .omitted, time: .shortened))"
        } else {
            nearestTitle = "最近：暂无任务"
        }
        let nearestItem = NSMenuItem(title: nearestTitle, action: nil, keyEquivalent: "")
        nearestItem.isEnabled = false
        statusMenu.addItem(nearestItem)
        statusMenu.addItem(.separator())

        let createItem = menuItem("新建任务…", action: #selector(showQuickCapture))
        createItem.setShortcut(for: .quickCapture)
        statusMenu.addItem(createItem)
        statusMenu.addItem(menuItem("打开主窗口", action: #selector(showMainWindow)))

        let aquariumItem = menuItem("显示鱼缸", action: #selector(toggleAquarium))
        aquariumItem.state = aquariumPanel?.isVisible == true ? .on : .off
        statusMenu.addItem(aquariumItem)
        let adjustmentTitle = aquariumIsAdjusting ? "完成调整鱼缸位置" : "调整鱼缸位置"
        let adjustmentItem = menuItem(adjustmentTitle, action: #selector(toggleAquariumAdjustment))
        adjustmentItem.isEnabled = aquariumPanel?.isVisible == true
        statusMenu.addItem(adjustmentItem)
        statusMenu.addItem(menuItem("设置…", action: #selector(showSettings)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("退出水滴待办", action: #selector(terminateApplication)))
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "水滴待办"
        window.minSize = NSSize(width: 680, height: 620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("WaterDropTodo.MainWindow")
        window.center()
        window.contentView = NSHostingView(
            rootView: ContentView().environmentObject(environment)
        )
        mainWindow = window
        return window
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "水滴待办设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsView().environmentObject(environment)
        )
        settingsWindow = window
        return window
    }

    private func makeQuickCapturePanel() -> QuickCapturePanel {
        let panel = QuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 390),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "快速创建"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        quickCapturePanel = panel
        return panel
    }

    private func showAquarium() {
        let panel = aquariumPanel ?? makeAquariumPanel()
        guard let screen = NSScreen.main else {
            panel.center()
            panel.showAquarium()
            return
        }
        if aquariumPanel == nil {
            panel.setFrame(aquariumPlacementStore.frame(for: screen), display: true)
        }
        aquariumIsAdjusting = false
        panel.setAdjustmentMode(false)
        panel.showAquarium()
        environment.updateAquariumState(frame: panel.frame, isVisible: true, isAdjusting: false)
    }

    private func makeAquariumPanel() -> AquariumPanel {
        let screen = NSScreen.main
        let frame = screen.map(aquariumPlacementStore.frame(for:))
            ?? CGRect(origin: .zero, size: AquariumPlacementGeometry.panelSize)
        let panel = AquariumPanel(frame: frame)
        panel.delegate = self
        aquariumPanel = panel
        return panel
    }

    private func finishAquariumAdjustmentIfNeeded() {
        guard aquariumIsAdjusting, let panel = aquariumPanel else { return }
        aquariumIsAdjusting = false
        panel.setAdjustmentMode(false)
        if let screen = panel.screen ?? NSScreen.main {
            aquariumPlacementStore.save(frame: panel.frame, on: screen)
        }
    }
}

private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

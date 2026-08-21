import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
final class ShellWindowCoordinator: NSObject, NSMenuDelegate, NSWindowDelegate {
    static let onboardingKey = "hasCompletedM1Welcome"
    private static let installedDefaultShortcutKey = "hasInstalledDefaultQuickCaptureShortcut"

    private let environment: AppEnvironment
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var quickCapturePanel: QuickCapturePanel?
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

    @objc func terminateApplication() {
        NSApp.terminate(nil)
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

}

private final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

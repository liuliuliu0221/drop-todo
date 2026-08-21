import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private lazy var shellCoordinator = ShellWindowCoordinator(environment: environment)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let reason = environment.startDisplaySystem()
        if reason == .unsupportedNoNotch, shouldEnforceDeviceGate {
            showUnsupportedDeviceAlertAndExit()
            return
        }

        shellCoordinator.start()
        installTimeObservers()
        Task { @MainActor in
            await environment.startTaskSystem()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await environment.reconcileTime()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func handleTimeContextChange(_ notification: Notification) {
        Task { @MainActor in
            await environment.reconcileTime()
        }
    }

    private func installTimeObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTimeContextChange),
            name: .NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTimeContextChange),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleTimeContextChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func showUnsupportedDeviceAlertAndExit() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "此 Mac 不受支持"
        alert.informativeText = "水滴待办仅支持带内置刘海屏的 Apple Silicon MacBook。"
        alert.addButton(withTitle: "退出")
        alert.runModal()
        NSApp.terminate(nil)
    }

    private var shouldEnforceDeviceGate: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("--skip-device-gate") {
            return false
        }
        return !processInfo.environment.keys.contains {
            $0.localizedCaseInsensitiveContains("xctest") || $0.hasPrefix("XC")
        }
    }
}

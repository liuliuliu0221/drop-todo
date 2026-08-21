import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let quickCapture = Self(
        "quickCapture",
        initial: .init(.t, modifiers: [.option])
    )
}

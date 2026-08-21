import AppKit
import CoreGraphics

struct NotchGeometry: Sendable, Equatable {
    let screenID: CGDirectDisplayID
    let notchFrame: CGRect
    let renderFrame: CGRect

    @MainActor
    init?(screen: NSScreen) {
        guard let screenID = screen.displayID,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              screen.safeAreaInsets.top > 0 else {
            return nil
        }

        let notchWidth = screen.frame.width - leftArea.width - rightArea.width
        let notchHeight = screen.safeAreaInsets.top
        guard notchWidth > 0, notchHeight > 0 else { return nil }

        let notchFrame = CGRect(
            x: screen.frame.midX - notchWidth / 2,
            y: screen.frame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        self.screenID = screenID
        self.notchFrame = notchFrame
        let renderLeftInset: CGFloat = 2
        let renderRightInset: CGFloat = 1
        self.renderFrame = CGRect(
            x: notchFrame.minX + renderLeftInset,
            y: notchFrame.minY - 25,
            width: notchFrame.width - renderLeftInset - renderRightInset,
            height: notchFrame.height + 25
        )
    }
}

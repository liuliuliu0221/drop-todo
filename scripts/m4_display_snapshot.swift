#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

struct Insets: Codable {
    let top: Double
    let left: Double
    let bottom: Double
    let right: Double
}

struct Rect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

struct Display: Codable {
    let displayID: UInt32
    let isBuiltin: Bool
    let mirrorsDisplayID: UInt32
    let frame: Rect
    let visibleFrame: Rect
    let backingScale: Double
    let safeAreaInsets: Insets
    let hasAuxiliaryTopAreas: Bool
    let hasNotch: Bool
}

struct Snapshot: Codable {
    let capturedAt: String
    let displayCount: Int
    let hasNotch: Bool
    let isMirrored: Bool
    let reduceMotion: Bool
    let displays: [Display]
}

let displays = NSScreen.screens.map { screen in
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let displayID = number?.uint32Value ?? 0
    let mirror = CGDisplayMirrorsDisplay(displayID)
    let hasAuxiliaryTopAreas = screen.auxiliaryTopLeftArea != nil
        && screen.auxiliaryTopRightArea != nil
    let hasNotch = screen.safeAreaInsets.top > 0 && hasAuxiliaryTopAreas
    return Display(
        displayID: displayID,
        isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
        mirrorsDisplayID: mirror,
        frame: Rect(screen.frame),
        visibleFrame: Rect(screen.visibleFrame),
        backingScale: screen.backingScaleFactor,
        safeAreaInsets: Insets(
            top: screen.safeAreaInsets.top,
            left: screen.safeAreaInsets.left,
            bottom: screen.safeAreaInsets.bottom,
            right: screen.safeAreaInsets.right
        ),
        hasAuxiliaryTopAreas: hasAuxiliaryTopAreas,
        hasNotch: hasNotch
    )
}

let formatter = ISO8601DateFormatter()
let snapshot = Snapshot(
    capturedAt: formatter.string(from: Date()),
    displayCount: displays.count,
    hasNotch: displays.contains(where: \.hasNotch),
    isMirrored: displays.contains { $0.mirrorsDisplayID != 0 },
    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
    displays: displays
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(snapshot))
FileHandle.standardOutput.write(Data("\n".utf8))

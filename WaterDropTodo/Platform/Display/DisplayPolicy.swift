import AppKit
import CoreGraphics

enum NotchVisibilityReason: String, Sendable, Equatable {
    case visible
    case unsupportedNoNotch
    case multipleDisplays
    case mirroredDisplay
    case hiddenByFullscreenPreference

    var title: String {
        switch self {
        case .visible: "刘海原型可见"
        case .unsupportedNoNotch: "设备无内置刘海"
        case .multipleDisplays: "多显示器模式已暂停"
        case .mirroredDisplay: "镜像显示模式已暂停"
        case .hiddenByFullscreenPreference: "已按全屏偏好隐藏"
        }
    }

    var detail: String {
        switch self {
        case .visible: "单屏刘海环境满足 M0B 渲染条件。"
        case .unsupportedNoNotch: "未从 NSScreen auxiliary areas 获取到刘海几何。"
        case .multipleDisplays: "MVP 阶段任意外接显示器都暂停刘海窗口。"
        case .mirroredDisplay: "MVP 阶段不在镜像环境显示刘海窗口。"
        case .hiddenByFullscreenPreference: "任务时间状态继续运行，只隐藏窗口。"
        }
    }

    var symbolName: String {
        switch self {
        case .visible: "checkmark.circle.fill"
        case .unsupportedNoNotch: "laptopcomputer.trianglebadge.exclamationmark"
        case .multipleDisplays: "rectangle.on.rectangle.slash"
        case .mirroredDisplay: "rectangle.on.rectangle"
        case .hiddenByFullscreenPreference: "eye.slash"
        }
    }
}

struct DisplaySnapshot: Sendable, Equatable {
    let displayCount: Int
    let hasNotch: Bool
    let isMirrored: Bool

    @MainActor
    static func capture() -> DisplaySnapshot {
        let screens = NSScreen.screens
        return DisplaySnapshot(
            displayCount: screens.count,
            hasNotch: screens.contains { NotchGeometry(screen: $0) != nil },
            isMirrored: screens.contains { screen in
                guard let displayID = screen.displayID else { return false }
                return CGDisplayMirrorsDisplay(displayID) != kCGNullDirectDisplay
            }
        )
    }
}

struct DisplayPolicy: Sendable {
    func visibility(
        for snapshot: DisplaySnapshot,
        hideInFullscreen: Bool = false
    ) -> NotchVisibilityReason {
        guard snapshot.hasNotch else { return .unsupportedNoNotch }
        if snapshot.isMirrored { return .mirroredDisplay }
        if snapshot.displayCount != 1 { return .multipleDisplays }
        if hideInFullscreen { return .hiddenByFullscreenPreference }
        return .visible
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}

import CoreGraphics

enum TransitionSourceKind: String, Sendable, Equatable {
    case notch = "刘海水滴"
    case listRow = "SwiftUI 列表行"
}

enum TransitionAnimationMode: Sendable, Equatable {
    case travel
    case fadeAtSource
}

struct TransitionAnimationPolicy: Sendable {
    static func mode(aquariumIsVisible: Bool, reduceMotion: Bool) -> TransitionAnimationMode {
        aquariumIsVisible && !reduceMotion ? .travel : .fadeAtSource
    }
}

struct TransitionRoute: Sendable, Equatable {
    let start: CGPoint
    let target: CGPoint

    func point(at progress: CGFloat) -> CGPoint {
        let progress = min(max(progress, 0), 1)
        return CGPoint(
            x: start.x + (target.x - start.x) * progress,
            y: start.y + (target.y - start.y) * progress
        )
    }
}

struct TransitionCoordinateSpace: Sendable, Equatable {
    let overlayFrame: CGRect
    let backingScale: CGFloat

    func localPoint(fromScreenPoint point: CGPoint) -> CGPoint {
        pixelAligned(
            CGPoint(x: point.x - overlayFrame.minX, y: point.y - overlayFrame.minY)
        )
    }

    func screenPoint(fromLocalPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + overlayFrame.minX, y: point.y + overlayFrame.minY)
    }

    func endpointError(renderedLocalPoint: CGPoint, expectedScreenPoint: CGPoint) -> CGFloat {
        let rendered = screenPoint(fromLocalPoint: renderedLocalPoint)
        return hypot(rendered.x - expectedScreenPoint.x, rendered.y - expectedScreenPoint.y)
    }

    private func pixelAligned(_ point: CGPoint) -> CGPoint {
        let scale = max(backingScale, 1)
        return CGPoint(
            x: (point.x * scale).rounded() / scale,
            y: (point.y * scale).rounded() / scale
        )
    }
}

struct TransitionMetrics: Sendable, Equatable {
    let source: TransitionSourceKind
    let backingScale: CGFloat
    let endpointError: CGFloat
}

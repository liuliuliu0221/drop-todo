import AppKit

struct ExpirationAnimationRequest: Sendable, Equatable {
    let taskID: UUID
    let source: CGPoint
}

@MainActor
final class ExpirationOverlayPanel: NSPanel {
    static let duration: TimeInterval = 0.6
    static let stagger: TimeInterval = 0.2

    private let overlayView = ExpirationOverlayView()
    private var animationTask: Task<Void, Never>?
    private var generation = 0

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = overlayView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func animate(
        requests: [ExpirationAnimationRequest],
        overlayFrame: CGRect,
        backingScale: CGFloat
    ) {
        cancel()
        guard !requests.isEmpty else { return }
        generation += 1
        let activeGeneration = generation
        let coordinateSpace = TransitionCoordinateSpace(
            overlayFrame: overlayFrame,
            backingScale: backingScale
        )
        let localSources = requests.map { coordinateSpace.localPoint(fromScreenPoint: $0.source) }
        setFrame(overlayFrame, display: true)
        orderFrontRegardless()

        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for source in localSources {
                guard !Task.isCancelled, activeGeneration == generation else { return }
                await animateOne(from: source, generation: activeGeneration)
                guard !Task.isCancelled, activeGeneration == generation else { return }
                try? await Task.sleep(nanoseconds: UInt64(Self.stagger * 1_000_000_000))
            }
            guard activeGeneration == generation else { return }
            overlayView.alpha = 0
            orderOut(nil)
            animationTask = nil
        }
    }

    func cancel() {
        generation += 1
        animationTask?.cancel()
        animationTask = nil
        overlayView.alpha = 0
        orderOut(nil)
    }

    private func animateOne(from source: CGPoint, generation activeGeneration: Int) async {
        let frameCount = max(1, Int(Self.duration * 60))
        for frameIndex in 0...frameCount {
            guard !Task.isCancelled, activeGeneration == generation else { return }
            let progress = CGFloat(frameIndex) / CGFloat(frameCount)
            let geometry = ExpirationAnimationGeometry.frame(
                source: source,
                bottomY: -32,
                progress: progress
            )
            overlayView.point = geometry.point
            overlayView.width = geometry.width
            overlayView.height = geometry.height
            overlayView.alpha = geometry.alpha
            try? await Task.sleep(nanoseconds: 16_666_667)
        }
    }
}

struct ExpirationAnimationFrame: Sendable, Equatable {
    let point: CGPoint
    let width: CGFloat
    let height: CGFloat
    let alpha: CGFloat
}

struct ExpirationAnimationGeometry: Sendable {
    static func frame(source: CGPoint, bottomY: CGFloat, progress: CGFloat) -> ExpirationAnimationFrame {
        let progress = min(max(progress, 0), 1)
        if progress < 0.4 {
            let stretch = progress / 0.4
            return ExpirationAnimationFrame(
                point: CGPoint(x: source.x, y: source.y - stretch * 9),
                width: 22 - stretch * 5,
                height: 24 + stretch * 28,
                alpha: 1
            )
        }
        let falling = (progress - 0.4) / 0.6
        let eased = falling * falling
        let alpha = falling >= 1
            ? CGFloat.zero
            : max(0, 1 - max(0, falling - 0.78) / 0.22)
        return ExpirationAnimationFrame(
            point: CGPoint(
                x: source.x + sin(falling * .pi * 2) * 2,
                y: source.y - 9 + (bottomY - source.y + 9) * eased
            ),
            width: 17,
            height: 52 - falling * 20,
            alpha: alpha
        )
    }
}

@MainActor
private final class ExpirationOverlayView: NSView {
    var point = CGPoint.zero { didSet { needsDisplay = true } }
    var width: CGFloat = 18 { didSet { needsDisplay = true } }
    var height: CGFloat = 24 { didSet { needsDisplay = true } }
    var alpha: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()
        guard alpha > 0 else { return }
        let rect = CGRect(
            x: point.x - width / 2,
            y: point.y - height / 2,
            width: width,
            height: height
        )
        NSColor.black.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
    }
}

import AppKit

@MainActor
final class TransitionOverlayPanel: NSPanel {
    typealias Completion = @MainActor (TransitionMetrics) -> Void

    private let overlayView = TransitionOverlayView()
    private var animationTask: Task<Void, Never>?
    private var animationGeneration = 0

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
        screenRoute: TransitionRoute,
        source: TransitionSourceKind,
        overlayFrame: CGRect,
        backingScale: CGFloat,
        mode: TransitionAnimationMode = .travel,
        duration: TimeInterval = 0.8,
        completion: @escaping Completion
    ) {
        cancel()
        animationGeneration += 1
        let generation = animationGeneration
        let coordinateSpace = TransitionCoordinateSpace(
            overlayFrame: overlayFrame,
            backingScale: backingScale
        )
        let localRoute = TransitionRoute(
            start: coordinateSpace.localPoint(fromScreenPoint: screenRoute.start),
            target: coordinateSpace.localPoint(fromScreenPoint: screenRoute.target)
        )

        setFrame(overlayFrame, display: true)
        overlayView.targetPoint = localRoute.target
        overlayView.dropletPoint = localRoute.start
        overlayView.showsTarget = mode == .travel
        overlayView.dropletAlpha = 1
        overlayView.dropletScale = 1
        orderFrontRegardless()

        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let frameCount = max(1, Int(duration * 60))
            for frameIndex in 0...frameCount {
                guard !Task.isCancelled, generation == animationGeneration else { return }
                let progress = CGFloat(frameIndex) / CGFloat(frameCount)
                switch mode {
                case .travel:
                    overlayView.dropletPoint = localRoute.point(at: progress)
                    overlayView.dropletAlpha = 1
                    overlayView.dropletScale = 1
                case .fadeAtSource:
                    overlayView.dropletPoint = localRoute.start
                    overlayView.dropletAlpha = 1 - progress
                    overlayView.dropletScale = 1 - progress * 0.25
                }
                try? await Task.sleep(nanoseconds: 16_666_667)
            }

            guard !Task.isCancelled, generation == animationGeneration else { return }
            let error = coordinateSpace.endpointError(
                renderedLocalPoint: overlayView.dropletPoint,
                expectedScreenPoint: screenRoute.target
            )
            orderOut(nil)
            animationTask = nil
            completion(
                TransitionMetrics(
                    source: source,
                    backingScale: backingScale,
                    endpointError: error
                )
            )
        }
    }

    func cancel() {
        animationGeneration += 1
        animationTask?.cancel()
        animationTask = nil
        orderOut(nil)
    }
}

@MainActor
private final class TransitionOverlayView: NSView {
    var dropletPoint: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
    var targetPoint: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
    var showsTarget = true {
        didSet { needsDisplay = true }
    }
    var dropletAlpha: CGFloat = 1 {
        didSet { needsDisplay = true }
    }
    var dropletScale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        if showsTarget {
            let targetRect = CGRect(
                x: targetPoint.x - 24,
                y: targetPoint.y - 24,
                width: 48,
                height: 48
            )
            let targetPath = NSBezierPath(ovalIn: targetRect)
            NSColor.systemTeal.withAlphaComponent(0.30).setStroke()
            targetPath.lineWidth = 3
            targetPath.stroke()
        }

        let halfWidth = 11 * dropletScale
        let halfHeight = 14 * dropletScale
        let dropletRect = CGRect(
            x: dropletPoint.x - halfWidth,
            y: dropletPoint.y - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
        let dropletPath = NSBezierPath(ovalIn: dropletRect)
        NSColor.systemBlue.withAlphaComponent(0.95 * dropletAlpha).setFill()
        dropletPath.fill()
    }
}

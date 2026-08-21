import AppKit

struct CompletionGardenAnimationRequest: Sendable, Equatable {
    let taskID: UUID
    let source: CGPoint
    let impactNormalizedX: Double
    let landingPositions: [Double]
    let randomSeed: UInt64
}

struct CompletionFallAnimationFrame: Sendable, Equatable {
    let point: CGPoint
    let width: CGFloat
    let height: CGFloat
}

enum CompletionFallGeometry {
    static func impactPoint(screenFrame: CGRect, normalizedX: Double) -> CGPoint {
        let normalizedX = min(max(normalizedX, 0), 1)
        return CGPoint(
            x: CGFloat(normalizedX) * screenFrame.width,
            y: 3
        )
    }

    static func frame(source: CGPoint, impact: CGPoint, progress: CGFloat) -> CompletionFallAnimationFrame {
        let linear = min(max(progress, 0), 1)
        let falling = linear * linear
        return CompletionFallAnimationFrame(
            point: CGPoint(
                x: source.x,
                y: source.y + (impact.y - source.y) * falling
            ),
            width: 18 - linear * 5,
            height: 24 + sin(linear * .pi) * 22
        )
    }
}

@MainActor
final class CompletionFallOverlayPanel: NSPanel {
    typealias Completion = @MainActor () -> Void

    private let animationView = CompletionFallAnimationView()
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
        contentView = animationView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func animate(
        request: CompletionGardenAnimationRequest,
        on screen: NSScreen,
        reducedMotion: Bool,
        completion: @escaping Completion
    ) {
        cancel()
        generation += 1
        let activeGeneration = generation
        let screenFrame = screen.frame
        let impact = CompletionFallGeometry.impactPoint(
            screenFrame: screenFrame,
            normalizedX: request.impactNormalizedX
        )
        let source = CGPoint(
            x: impact.x,
            y: request.source.y - screenFrame.minY
        )
        var random = GardenRandomNumberGenerator(seed: request.randomSeed)
        let particles = request.landingPositions.map { normalizedX in
            SplashParticleTrajectory(
                start: impact,
                target: CGPoint(
                    x: CGFloat(normalizedX) * screenFrame.width,
                    y: impact.y
                ),
                arcHeight: CGFloat(22 + random.nextUnitInterval() * 52),
                radius: CGFloat(2.2 + random.nextUnitInterval() * 2.8)
            )
        }

        setFrame(screenFrame, display: true)
        animationView.configure(source: source, impact: impact, particles: particles)
        orderFrontRegardless()

        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if reducedMotion {
                await animateReducedMotion(
                    source: source,
                    impact: impact,
                    generation: activeGeneration
                )
            } else {
                await animateFall(source: source, impact: impact, generation: activeGeneration)
                guard !Task.isCancelled, generation == activeGeneration else { return }
                await animateSplash(generation: activeGeneration)
            }
            guard !Task.isCancelled, generation == activeGeneration else { return }
            orderOut(nil)
            animationTask = nil
            completion()
        }
    }

    func cancel() {
        generation += 1
        animationTask?.cancel()
        animationTask = nil
        animationView.reset()
        orderOut(nil)
    }

    private func animateFall(source: CGPoint, impact: CGPoint, generation activeGeneration: Int) async {
        let frameCount = 40
        for frameIndex in 0...frameCount {
            guard !Task.isCancelled, generation == activeGeneration else { return }
            let linear = CGFloat(frameIndex) / CGFloat(frameCount)
            let frame = CompletionFallGeometry.frame(
                source: source,
                impact: impact,
                progress: linear
            )
            animationView.dropletPoint = frame.point
            animationView.dropletWidth = frame.width
            animationView.dropletHeight = frame.height
            animationView.dropletAlpha = 1
            try? await Task.sleep(nanoseconds: 16_666_667)
        }
        animationView.dropletPoint = impact
        animationView.dropletWidth = 32
        animationView.dropletHeight = 9
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func animateSplash(generation activeGeneration: Int) async {
        animationView.dropletAlpha = 0
        let frameCount = 30
        for frameIndex in 0...frameCount {
            guard !Task.isCancelled, generation == activeGeneration else { return }
            let progress = CGFloat(frameIndex) / CGFloat(frameCount)
            animationView.splashProgress = progress
            animationView.splashAlpha = 1 - max(0, progress - 0.78) / 0.22
            try? await Task.sleep(nanoseconds: 16_666_667)
        }
    }

    private func animateReducedMotion(
        source: CGPoint,
        impact: CGPoint,
        generation activeGeneration: Int
    ) async {
        let frameCount = 10
        for frameIndex in 0...frameCount {
            guard !Task.isCancelled, generation == activeGeneration else { return }
            let progress = CGFloat(frameIndex) / CGFloat(frameCount)
            animationView.dropletPoint = CGPoint(
                x: source.x,
                y: source.y + (impact.y - source.y) * progress
            )
            animationView.dropletAlpha = 1 - progress * 0.55
            try? await Task.sleep(nanoseconds: 16_666_667)
        }
        animationView.dropletAlpha = 0
    }
}

struct SplashParticleTrajectory: Sendable, Equatable {
    let start: CGPoint
    let target: CGPoint
    let arcHeight: CGFloat
    let radius: CGFloat

    func point(at progress: CGFloat) -> CGPoint {
        let progress = min(max(progress, 0), 1)
        return CGPoint(
            x: start.x + (target.x - start.x) * progress,
            y: start.y + (target.y - start.y) * progress
                + 4 * arcHeight * progress * (1 - progress)
        )
    }
}

@MainActor
private final class CompletionFallAnimationView: NSView {
    var dropletPoint = CGPoint.zero { didSet { needsDisplay = true } }
    var dropletWidth: CGFloat = 18 { didSet { needsDisplay = true } }
    var dropletHeight: CGFloat = 24 { didSet { needsDisplay = true } }
    var dropletAlpha: CGFloat = 0 { didSet { needsDisplay = true } }
    var splashProgress: CGFloat = 0 { didSet { needsDisplay = true } }
    var splashAlpha: CGFloat = 0 { didSet { needsDisplay = true } }

    private var impact = CGPoint.zero
    private var particles: [SplashParticleTrajectory] = []

    override var isOpaque: Bool { false }

    func configure(
        source: CGPoint,
        impact: CGPoint,
        particles: [SplashParticleTrajectory]
    ) {
        dropletPoint = source
        dropletWidth = 18
        dropletHeight = 24
        dropletAlpha = 1
        splashProgress = 0
        splashAlpha = 1
        self.impact = impact
        self.particles = particles
    }

    func reset() {
        dropletAlpha = 0
        splashAlpha = 0
        splashProgress = 0
        particles = []
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        if dropletAlpha > 0 {
            drawDroplet()
        }
        if splashAlpha > 0, splashProgress > 0 {
            drawSplash()
        }
    }

    private func drawDroplet() {
        let rect = CGRect(
            x: dropletPoint.x - dropletWidth / 2,
            y: dropletPoint.y - dropletHeight / 2,
            width: dropletWidth,
            height: dropletHeight
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: dropletWidth / 2, yRadius: dropletWidth / 2)
        let gradient = NSGradient(
            starting: NSColor.systemCyan.withAlphaComponent(dropletAlpha),
            ending: NSColor.systemBlue.withAlphaComponent(dropletAlpha)
        )
        gradient?.draw(in: path, angle: -90)
    }

    private func drawSplash() {
        for particle in particles {
            let point = particle.point(at: splashProgress)
            let radius = particle.radius * (1 - splashProgress * 0.42)
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            NSColor.systemCyan.withAlphaComponent(0.88 * splashAlpha).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }

        let ringRadius = 8 + splashProgress * 24
        let ringRect = CGRect(
            x: impact.x - ringRadius,
            y: impact.y - ringRadius * 0.22,
            width: ringRadius * 2,
            height: ringRadius * 0.44
        )
        let ring = NSBezierPath(ovalIn: ringRect)
        NSColor.systemBlue.withAlphaComponent(0.45 * splashAlpha).setStroke()
        ring.lineWidth = 1.5
        ring.stroke()
    }
}

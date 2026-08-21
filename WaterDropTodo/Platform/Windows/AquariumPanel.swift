import AppKit

struct AquariumPlacementGeometry: Sendable, Equatable {
    static let panelSize = CGSize(width: 180, height: 110)
    static let edgeInset: CGFloat = 16

    static func defaultFrame(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.maxX - panelSize.width - edgeInset,
            y: visibleFrame.minY + edgeInset,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func normalizedOrigin(of frame: CGRect, in visibleFrame: CGRect) -> CGPoint {
        let availableWidth = max(visibleFrame.width - frame.width, 1)
        let availableHeight = max(visibleFrame.height - frame.height, 1)
        return CGPoint(
            x: min(max((frame.minX - visibleFrame.minX) / availableWidth, 0), 1),
            y: min(max((frame.minY - visibleFrame.minY) / availableHeight, 0), 1)
        )
    }

    static func frame(
        normalizedOrigin: CGPoint,
        size: CGSize = panelSize,
        in visibleFrame: CGRect
    ) -> CGRect {
        let availableWidth = max(visibleFrame.width - size.width, 0)
        let availableHeight = max(visibleFrame.height - size.height, 0)
        return CGRect(
            x: visibleFrame.minX + min(max(normalizedOrigin.x, 0), 1) * availableWidth,
            y: visibleFrame.minY + min(max(normalizedOrigin.y, 0), 1) * availableHeight,
            width: size.width,
            height: size.height
        )
    }

    static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }
}

@MainActor
final class AquariumPlacementStore {
    private enum Key {
        static let screenID = "aquarium.screenID"
        static let normalizedX = "aquarium.normalizedX"
        static let normalizedY = "aquarium.normalizedY"
        static let frameX = "aquarium.frameX"
        static let frameY = "aquarium.frameY"
        static let hasPlacement = "aquarium.hasPlacement"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func frame(for screen: NSScreen) -> CGRect {
        guard defaults.bool(forKey: Key.hasPlacement) else {
            return AquariumPlacementGeometry.defaultFrame(in: screen.visibleFrame)
        }

        let savedScreenID = UInt32(defaults.integer(forKey: Key.screenID))
        if savedScreenID == screen.displayID {
            return AquariumPlacementGeometry.frame(
                normalizedOrigin: CGPoint(
                    x: defaults.double(forKey: Key.normalizedX),
                    y: defaults.double(forKey: Key.normalizedY)
                ),
                in: screen.visibleFrame
            )
        }

        let lastFrame = CGRect(
            x: defaults.double(forKey: Key.frameX),
            y: defaults.double(forKey: Key.frameY),
            width: AquariumPlacementGeometry.panelSize.width,
            height: AquariumPlacementGeometry.panelSize.height
        )
        return AquariumPlacementGeometry.clamped(lastFrame, to: screen.visibleFrame)
    }

    func save(frame: CGRect, on screen: NSScreen) {
        let normalized = AquariumPlacementGeometry.normalizedOrigin(
            of: frame,
            in: screen.visibleFrame
        )
        defaults.set(Int(screen.displayID ?? 0), forKey: Key.screenID)
        defaults.set(normalized.x, forKey: Key.normalizedX)
        defaults.set(normalized.y, forKey: Key.normalizedY)
        defaults.set(frame.minX, forKey: Key.frameX)
        defaults.set(frame.minY, forKey: Key.frameY)
        defaults.set(true, forKey: Key.hasPlacement)
    }
}

@MainActor
final class AquariumPanel: NSPanel {
    private let aquariumView = AquariumCanvasView()

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        contentView = aquariumView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showAquarium() {
        aquariumView.startAnimating()
        orderFrontRegardless()
    }

    func hideAquarium() {
        aquariumView.stopAnimating()
        orderOut(nil)
    }

    func pauseAnimation() {
        aquariumView.stopAnimating()
    }

    func resumeAnimation() {
        guard isVisible else { return }
        aquariumView.startAnimating()
    }

    func setAdjustmentMode(_ enabled: Bool) {
        ignoresMouseEvents = !enabled
        aquariumView.isAdjustmentMode = enabled
    }

    func triggerImpact(reducedMotion: Bool) {
        aquariumView.triggerImpact(reducedMotion: reducedMotion)
    }
}

@MainActor
private final class AquariumCanvasView: NSView {
    private static let ambientFrameInterval: TimeInterval = 0.25
    private static let impactFrameInterval: TimeInterval = 1.0 / 30.0

    var isAdjustmentMode = false {
        didSet { needsDisplay = true }
    }

    private var timer: Timer?
    private var frameInterval = ambientFrameInterval
    private var phase: CGFloat = 0
    private var boostUntil = Date.distantPast
    private var splashStrength: CGFloat = 0

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    func startAnimating() {
        guard timer == nil else { return }
        scheduleTimer(interval: Self.ambientFrameInterval)
        needsDisplay = true
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        frameInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }

    func triggerImpact(reducedMotion: Bool) {
        boostUntil = reducedMotion ? .distantPast : Date().addingTimeInterval(1)
        splashStrength = reducedMotion ? 0.35 : 1
        if !reducedMotion, timer != nil {
            scheduleTimer(interval: Self.impactFrameInterval)
        }
        needsDisplay = true
    }

    private func advance() {
        let boosted = Date() < boostUntil
        phase += CGFloat((boosted ? 1.7 : 0.45) * frameInterval)
        splashStrength = max(0, splashStrength - CGFloat(1.2 * frameInterval))
        needsDisplay = true

        if !boosted, frameInterval != Self.ambientFrameInterval {
            scheduleTimer(interval: Self.ambientFrameInterval)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let glassRect = bounds.insetBy(dx: 2, dy: 2)
        let glassPath = NSBezierPath(roundedRect: glassRect, xRadius: 18, yRadius: 18)
        NSGraphicsContext.saveGraphicsState()
        glassPath.addClip()

        NSColor(calibratedWhite: 0.07, alpha: 0.90).setFill()
        bounds.fill()

        let waterRect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.72)
        let waterGradient = NSGradient(
            starting: NSColor.systemTeal.withAlphaComponent(0.64),
            ending: NSColor.systemBlue.withAlphaComponent(0.78)
        )
        waterGradient?.draw(in: waterRect, angle: 90)

        drawWaterSurface(y: waterRect.maxY)
        drawBubbles(in: waterRect)
        drawFish(index: 0, color: .systemOrange, waterRect: waterRect)
        drawFish(index: 1, color: .systemYellow, waterRect: waterRect)
        drawFish(index: 2, color: .systemPink, waterRect: waterRect)
        drawSplash(at: CGPoint(x: bounds.midX, y: waterRect.maxY))

        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(isAdjustmentMode ? 0.72 : 0.25).setStroke()
        glassPath.lineWidth = isAdjustmentMode ? 2.5 : 1.2
        glassPath.stroke()

        if isAdjustmentMode {
            let text = "拖动鱼缸 · 完成后从菜单关闭调整"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.9)
            ]
            text.draw(at: CGPoint(x: 12, y: bounds.maxY - 18), withAttributes: attributes)
        }
    }

    private func drawWaterSurface(y: CGFloat) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 0, y: y))
        for x in stride(from: CGFloat(0), through: bounds.width, by: 6) {
            path.line(to: CGPoint(x: x, y: y + sin(x * 0.07 + phase) * 1.7))
        }
        NSColor.cyan.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func drawBubbles(in waterRect: CGRect) {
        for index in 0..<5 {
            let x = CGFloat(20 + index * 33)
            let y = 12 + (CGFloat(index * 17) + phase * 9).truncatingRemainder(dividingBy: waterRect.height - 18)
            let radius = CGFloat(2 + index % 2)
            let bubble = NSBezierPath(ovalIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2))
            NSColor.white.withAlphaComponent(0.30).setStroke()
            bubble.lineWidth = 1
            bubble.stroke()
        }
    }

    private func drawFish(index: Int, color: NSColor, waterRect: CGRect) {
        let direction: CGFloat = index == 1 ? -1 : 1
        let baseX = [38.0, 94.0, 142.0][index]
        let amplitude = [19.0, 24.0, 17.0][index]
        let x = CGFloat(baseX) + sin(phase * direction + CGFloat(index) * 1.7) * CGFloat(amplitude)
        let y = CGFloat([50.0, 29.0, 61.0][index]) + cos(phase * 0.65 + CGFloat(index)) * 5
        let body = CGRect(x: x - 11, y: min(y, waterRect.maxY - 9) - 5, width: 22, height: 10)
        let bodyPath = NSBezierPath(ovalIn: body)
        color.withAlphaComponent(0.92).setFill()
        bodyPath.fill()

        let tail = NSBezierPath()
        let tailX = direction > 0 ? body.minX : body.maxX
        tail.move(to: CGPoint(x: tailX, y: body.midY))
        tail.line(to: CGPoint(x: tailX - direction * 8, y: body.midY + 6))
        tail.line(to: CGPoint(x: tailX - direction * 8, y: body.midY - 6))
        tail.close()
        color.withAlphaComponent(0.78).setFill()
        tail.fill()

        let eyeX = direction > 0 ? body.maxX - 5 : body.minX + 3
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: CGRect(x: eyeX, y: body.midY + 1, width: 2, height: 2)).fill()
    }

    private func drawSplash(at point: CGPoint) {
        guard splashStrength > 0 else { return }
        let radius = 5 + (1 - splashStrength) * 18
        let path = NSBezierPath(ovalIn: CGRect(
            x: point.x - radius,
            y: point.y - radius * 0.35,
            width: radius * 2,
            height: radius * 0.7
        ))
        NSColor.cyan.withAlphaComponent(splashStrength * 0.75).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

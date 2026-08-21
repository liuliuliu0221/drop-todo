import AppKit

enum GardenScreenGeometry {
    static let panelHeight: CGFloat = 64

    static func panelFrame(for screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: panelHeight
        )
    }
}

enum GardenPointerInteraction {
    static let horizontalRadius: CGFloat = 44
    static let maximumInteractionY: CGFloat = 30
    static let maximumSway: CGFloat = 11

    static func targetSway(
        cellCenterX: CGFloat,
        pointer: CGPoint?,
        hasGrass: Bool
    ) -> CGFloat {
        guard hasGrass,
              let pointer,
              (0...maximumInteractionY).contains(pointer.y) else {
            return 0
        }
        let horizontalDelta = cellCenterX - pointer.x
        let distance = abs(horizontalDelta)
        guard distance < horizontalRadius else { return 0 }
        let direction: CGFloat = horizontalDelta >= 0 ? 1 : -1
        let proximity = 1 - distance / horizontalRadius
        return direction * maximumSway * proximity * proximity
    }
}

@MainActor
final class GardenOverlayPanel: NSPanel {
    private let gardenView = GardenCanvasView()
    private var pointerTrackingTask: Task<Void, Never>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1
        )
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = gardenView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(
        snapshot: GardenSnapshot,
        on screen: NSScreen,
        changedCellIndices: Set<Int> = [],
        reducedMotion: Bool = false
    ) {
        guard snapshot.coverageFraction > 0 else {
            stopPointerTracking()
            gardenView.update(snapshot: snapshot, changedCellIndices: [], reducedMotion: true)
            orderOut(nil)
            return
        }
        setFrame(GardenScreenGeometry.panelFrame(for: screen.frame), display: true)
        gardenView.update(
            snapshot: snapshot,
            changedCellIndices: changedCellIndices,
            reducedMotion: reducedMotion
        )
        orderFrontRegardless()
        startPointerTracking()
    }

    func hideGarden() {
        stopPointerTracking()
        gardenView.finishAnimation()
        orderOut(nil)
    }

    private func startPointerTracking() {
        guard pointerTrackingTask == nil else { return }
        pointerTrackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let pointer = convertPoint(fromScreen: NSEvent.mouseLocation)
                let isAnimating = gardenView.advancePointerInteraction(at: pointer)
                let delay: UInt64 = isAnimating ? 16_666_667 : 100_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func stopPointerTracking() {
        pointerTrackingTask?.cancel()
        pointerTrackingTask = nil
        gardenView.resetPointerInteraction()
    }
}

@MainActor
private final class GardenCanvasView: NSView {
    private var snapshot = GardenSnapshot.empty
    private var growingCellIndices = Set<Int>()
    private var baselineBladeCountByCell: [Int: Int] = [:]
    private var swayByCell = Array(
        repeating: CGFloat.zero,
        count: GardenConstants.cellCount
    )
    private var growthProgress: CGFloat = 1
    private var animationTask: Task<Void, Never>?

    override var isOpaque: Bool { false }

    func update(
        snapshot: GardenSnapshot,
        changedCellIndices: Set<Int>,
        reducedMotion: Bool
    ) {
        animationTask?.cancel()
        baselineBladeCountByCell = Dictionary(
            uniqueKeysWithValues: changedCellIndices.map { cellIndex in
                let previousDensity = snapshot.cells.indices.contains(cellIndex)
                    ? snapshot.cells[cellIndex].density
                    : 0
                return (
                    cellIndex,
                    GardenRenderingMetrics.visibleBladeCount(density: previousDensity)
                )
            }
        )
        self.snapshot = snapshot
        growingCellIndices = changedCellIndices
        growthProgress = reducedMotion || changedCellIndices.isEmpty ? 1 : 0
        needsDisplay = true
        guard growthProgress < 1 else { return }

        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let frameCount = GardenConstants.growthAnimationFrameCount
            for frameIndex in 0...frameCount {
                guard !Task.isCancelled else { return }
                let linear = CGFloat(frameIndex) / CGFloat(frameCount)
                growthProgress = 1 - pow(1 - linear, 3)
                needsDisplay = true
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
            growingCellIndices = []
            baselineBladeCountByCell = [:]
            growthProgress = 1
            animationTask = nil
        }
    }

    func finishAnimation() {
        animationTask?.cancel()
        animationTask = nil
        growingCellIndices = []
        baselineBladeCountByCell = [:]
        growthProgress = 1
        needsDisplay = true
    }

    @discardableResult
    func advancePointerInteraction(at pointer: CGPoint) -> Bool {
        guard bounds.width > 0,
              snapshot.cells.count == GardenConstants.cellCount else {
            return false
        }
        let pointerInGarden = bounds.contains(pointer) ? pointer : nil
        let cellWidth = bounds.width / CGFloat(snapshot.cells.count)
        var hasMotion = false
        var changed = false

        for cellIndex in snapshot.cells.indices {
            let target = GardenPointerInteraction.targetSway(
                cellCenterX: (CGFloat(cellIndex) + 0.5) * cellWidth,
                pointer: pointerInGarden,
                hasGrass: snapshot.cells[cellIndex].density > 0
            )
            let current = swayByCell[cellIndex]
            let response: CGFloat = target == 0 ? 0.18 : 0.34
            var next = current + (target - current) * response
            if abs(next) < 0.025, target == 0 { next = 0 }
            if abs(next - current) > 0.001 {
                swayByCell[cellIndex] = next
                changed = true
            }
            if abs(next) > 0.025 || target != 0 { hasMotion = true }
        }

        if changed { needsDisplay = true }
        return hasMotion
    }

    func resetPointerInteraction() {
        swayByCell = Array(repeating: 0, count: GardenConstants.cellCount)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()
        guard bounds.width > 0, snapshot.cells.count == GardenConstants.cellCount else { return }

        let cellWidth = bounds.width / CGFloat(snapshot.cells.count)
        for (cellIndex, cell) in snapshot.cells.enumerated() where cell.density > 0 {
            let bladeCount = GardenRenderingMetrics.visibleBladeCount(density: cell.density)
            let cellGrowth = growingCellIndices.contains(cellIndex) ? growthProgress : 1
            drawCell(
                cell,
                index: cellIndex,
                bladeCount: bladeCount,
                baselineBladeCount: baselineBladeCountByCell[cellIndex] ?? bladeCount,
                cellWidth: cellWidth,
                growth: cellGrowth
            )
        }
    }

    private func drawCell(
        _ cell: GardenCell,
        index: Int,
        bladeCount: Int,
        baselineBladeCount: Int,
        cellWidth: CGFloat,
        growth: CGFloat
    ) {
        var random = GardenRandomNumberGenerator(seed: cell.styleSeed)
        let originX = CGFloat(index) * cellWidth
        let pointerSway = swayByCell.indices.contains(index) ? swayByCell[index] : 0
        for bladeIndex in 0..<bladeCount {
            let bladeGrowth = bladeIndex < baselineBladeCount ? 1 : growth
            let horizontal = CGFloat(random.nextUnitInterval())
            let height = CGFloat(9 + random.nextUnitInterval() * 9) * bladeGrowth
            let lean = CGFloat(random.nextUnitInterval() * 8 - 4)
            let baseX = originX + horizontal * max(cellWidth, 1)
            let baseY = CGFloat(1 + random.nextUnitInterval() * 2)
            let depth = CGFloat(bladeIndex) / CGFloat(max(bladeCount - 1, 1))
            let effectiveLean = lean * bladeGrowth
                + pointerSway * (0.72 + depth * 0.28) * bladeGrowth
            let tip = CGPoint(x: baseX + effectiveLean, y: baseY + height)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: baseX, y: baseY))
            path.curve(
                to: tip,
                controlPoint1: CGPoint(
                    x: baseX - effectiveLean * 0.12,
                    y: baseY + height * 0.38
                ),
                controlPoint2: CGPoint(
                    x: tip.x - effectiveLean * 0.22,
                    y: baseY + height * 0.76
                )
            )
            NSColor(
                calibratedRed: 0.16 + depth * 0.08,
                green: 0.48 + depth * 0.20,
                blue: 0.16 + depth * 0.05,
                alpha: 0.76 + depth * 0.22
            ).setStroke()
            path.lineWidth = 0.75 + depth * 0.75
            path.lineCapStyle = .round
            path.stroke()

            if let flowerStyle = GardenFlowerTraits.style(
                cellSeed: cell.styleSeed,
                bladeIndex: bladeIndex
            ) {
                drawFlower(flowerStyle, at: tip, growth: bladeGrowth)
            }
        }

        let densityAlpha = min(CGFloat(cell.density) / 10, 1) * 0.32
        NSColor(calibratedRed: 0.10, green: 0.36, blue: 0.12, alpha: densityAlpha).setFill()
        CGRect(x: originX, y: 0, width: ceil(cellWidth + 0.5), height: 2).fill()
    }

    private func drawFlower(
        _ style: GardenFlowerStyle,
        at anchor: CGPoint,
        growth: CGFloat
    ) {
        guard growth > 0.02 else { return }
        let scale = growth
        switch style {
        case .fivePetal:
            drawRadialFlower(
                at: anchor,
                petalCount: 5,
                petalColor: NSColor(
                    calibratedRed: 0.96,
                    green: 0.52,
                    blue: 0.68,
                    alpha: 0.96
                ),
                centerColor: NSColor(
                    calibratedRed: 1,
                    green: 0.78,
                    blue: 0.25,
                    alpha: 1
                ),
                scale: scale,
                petalRadius: 1.45
            )
        case .daisy:
            drawRadialFlower(
                at: anchor,
                petalCount: 8,
                petalColor: NSColor(
                    calibratedRed: 0.98,
                    green: 0.98,
                    blue: 0.91,
                    alpha: 0.98
                ),
                centerColor: NSColor(
                    calibratedRed: 1,
                    green: 0.68,
                    blue: 0.10,
                    alpha: 1
                ),
                scale: scale,
                petalRadius: 1.22
            )
        case .bell:
            let width = 5.8 * scale
            let height = 5.4 * scale
            let path = NSBezierPath()
            path.move(to: CGPoint(x: anchor.x - width * 0.46, y: anchor.y + height * 0.15))
            path.curve(
                to: CGPoint(x: anchor.x - width * 0.35, y: anchor.y - height * 0.72),
                controlPoint1: CGPoint(x: anchor.x - width * 0.52, y: anchor.y - height * 0.08),
                controlPoint2: CGPoint(x: anchor.x - width * 0.50, y: anchor.y - height * 0.54)
            )
            path.curve(
                to: CGPoint(x: anchor.x, y: anchor.y - height * 0.58),
                controlPoint1: CGPoint(x: anchor.x - width * 0.22, y: anchor.y - height * 0.88),
                controlPoint2: CGPoint(x: anchor.x - width * 0.10, y: anchor.y - height * 0.54)
            )
            path.curve(
                to: CGPoint(x: anchor.x + width * 0.35, y: anchor.y - height * 0.72),
                controlPoint1: CGPoint(x: anchor.x + width * 0.10, y: anchor.y - height * 0.54),
                controlPoint2: CGPoint(x: anchor.x + width * 0.22, y: anchor.y - height * 0.88)
            )
            path.curve(
                to: CGPoint(x: anchor.x + width * 0.46, y: anchor.y + height * 0.15),
                controlPoint1: CGPoint(x: anchor.x + width * 0.50, y: anchor.y - height * 0.54),
                controlPoint2: CGPoint(x: anchor.x + width * 0.52, y: anchor.y - height * 0.08)
            )
            path.close()
            NSColor(
                calibratedRed: 0.66,
                green: 0.48,
                blue: 0.96,
                alpha: 0.96
            ).setFill()
            path.fill()
        case .dandelion:
            let dotRadius = 0.78 * scale
            let orbit = 2.2 * scale
            let yellow = NSColor(
                calibratedRed: 1,
                green: 0.76,
                blue: 0.10,
                alpha: 0.98
            )
            yellow.setFill()
            NSBezierPath(
                ovalIn: CGRect(
                    x: anchor.x - dotRadius,
                    y: anchor.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
            ).fill()
            for index in 0..<7 {
                let angle = CGFloat(index) / 7 * .pi * 2
                let center = CGPoint(
                    x: anchor.x + cos(angle) * orbit,
                    y: anchor.y + sin(angle) * orbit
                )
                NSBezierPath(
                    ovalIn: CGRect(
                        x: center.x - dotRadius,
                        y: center.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                ).fill()
            }
        }
    }

    private func drawRadialFlower(
        at anchor: CGPoint,
        petalCount: Int,
        petalColor: NSColor,
        centerColor: NSColor,
        scale: CGFloat,
        petalRadius: CGFloat
    ) {
        let orbit = 2.15 * scale
        let radius = petalRadius * scale
        petalColor.setFill()
        for index in 0..<petalCount {
            let angle = CGFloat(index) / CGFloat(petalCount) * .pi * 2
            let center = CGPoint(
                x: anchor.x + cos(angle) * orbit,
                y: anchor.y + sin(angle) * orbit
            )
            NSBezierPath(
                ovalIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ).fill()
        }
        let centerRadius = 1.15 * scale
        centerColor.setFill()
        NSBezierPath(
            ovalIn: CGRect(
                x: anchor.x - centerRadius,
                y: anchor.y - centerRadius,
                width: centerRadius * 2,
                height: centerRadius * 2
            )
        ).fill()
    }
}

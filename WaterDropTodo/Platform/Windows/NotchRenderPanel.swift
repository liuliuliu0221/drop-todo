import AppKit

@MainActor
final class NotchRenderPanel: NSPanel {
    private let renderView: LiquidBitmapView
    private let renderContainer: NotchRenderContainerView
    private var visibleTaskIDs: [UUID] = []

    init() {
        let renderView = LiquidBitmapView()
        let renderContainer = NotchRenderContainerView(renderView: renderView)
        self.renderView = renderView
        self.renderContainer = renderContainer

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        contentView = renderContainer
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(geometry: NotchGeometry) {
        setFrame(geometry.renderFrame, display: true)
        renderContainer.frame = CGRect(origin: .zero, size: geometry.renderFrame.size)
        renderContainer.layoutSubtreeIfNeeded()
        orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            renderView.startRendering()
            renderView.requestRedraw()
        }
    }

    func update(snapshot: NotchLayoutSnapshot, hoveredTaskID: UUID?) {
        let taskIDs = snapshot.items.map(\.id)
        renderView.update(parameters: .notch(snapshot: snapshot, hoveredTaskID: hoveredTaskID))

        if taskIDs != visibleTaskIDs, !visibleTaskIDs.isEmpty, !taskIDs.isEmpty {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.35
            fade.toValue = 1
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            renderView.layer?.add(fade, forKey: "visibleTaskCrossfade")
        }
        visibleTaskIDs = taskIDs
    }

    func hide() {
        renderView.stopRendering()
        orderOut(nil)
    }
}

@MainActor
private final class NotchRenderContainerView: NSView {
    private let renderView: LiquidBitmapView

    override var isOpaque: Bool { false }

    init(renderView: LiquidBitmapView) {
        self.renderView = renderView
        super.init(frame: .zero)

        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor

        renderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(renderView)
        NSLayoutConstraint.activate([
            renderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            renderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            renderView.topAnchor.constraint(equalTo: topAnchor),
            renderView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

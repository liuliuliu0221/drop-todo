import AppKit
import Metal

@MainActor
final class LiquidBitmapView: NSView {
    private let renderer: LiquidRenderer?
    private var hasVisibleDroplets = false

    override var isOpaque: Bool { false }

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            renderer = LiquidRenderer(device: device, pixelFormat: .bgra8Unorm)
        } else {
            renderer = nil
        }
        super.init(frame: .zero)

        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contentsGravity = .resize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(parameters: LiquidParameters) {
        hasVisibleDroplets = parameters.dropletCount > 0
        renderer?.update(parameters: parameters)
        if hasVisibleDroplets {
            requestRedraw()
        } else {
            layer?.contents = nil
        }
    }

    func startRendering() {
        requestRedraw()
    }

    func stopRendering() {}

    func requestRedraw() {
        guard hasVisibleDroplets,
              window?.isVisible == true,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }
        let scale = window?.backingScaleFactor ?? 1
        let drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let image = renderer?.renderImage(drawableSize: drawableSize) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        layer?.contents = image
        CATransaction.commit()
    }
}

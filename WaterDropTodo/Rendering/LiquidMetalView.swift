import MetalKit
import SwiftUI

@MainActor
final class LiquidMTKView: MTKView {
    private var liquidRenderer: LiquidRenderer?

    override var isOpaque: Bool { false }

    func configureForLiquidRendering() {
        guard liquidRenderer == nil else { return }

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true
        autoResizeDrawable = true
        preferredFramesPerSecond = 30
        isPaused = false
        enableSetNeedsDisplay = false
        wantsLayer = true
        layer?.isOpaque = false

        guard let device,
              let renderer = LiquidRenderer(device: device, pixelFormat: colorPixelFormat) else {
            return
        }
        liquidRenderer = renderer
        delegate = renderer
    }

    func update(parameters: LiquidParameters) {
        liquidRenderer?.update(parameters: parameters, view: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        requestRedraw()
    }

    override func layout() {
        super.layout()
        requestRedraw()
    }

    func requestRedraw() {
        guard window != nil, bounds.width > 0, bounds.height > 0 else {
            return
        }
        setNeedsDisplay(bounds)
        draw()
    }
}

struct LiquidMetalView: NSViewRepresentable {
    let parameters: LiquidParameters

    func makeNSView(context: Context) -> LiquidMTKView {
        let view = LiquidMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.configureForLiquidRendering()
        view.update(parameters: parameters)
        return view
    }

    func updateNSView(_ view: LiquidMTKView, context: Context) {
        view.update(parameters: parameters)
    }
}

import CoreGraphics
import Foundation
import Metal
import MetalKit
import simd

private struct LiquidUniforms {
    var resolution = SIMD2<Float>(1, 1)
    var time: Float = 0
    var dropletCount: UInt32 = 0
    var threshold: Float = 0
    var perturbation: Float = 0
    var colorProgress: Float = 0
    var padding: Float = 0
    var surfaceY: Float = 0
    var surfaceDepth: Float = 0
    var dropletY: Float = 0
    var opacity: Float = 0
    var clearBlue = SIMD4<Float>.zero
    var deepBlue = SIMD4<Float>.zero
    var asphalt = SIMD4<Float>.zero
    var progress0To3 = SIMD4<Float>.zero
    var progress4To7 = SIMD4<Float>.zero
    var ball0 = SIMD4<Float>.zero
    var ball1 = SIMD4<Float>.zero
    var ball2 = SIMD4<Float>.zero
    var ball3 = SIMD4<Float>.zero
    var ball4 = SIMD4<Float>.zero
    var ball5 = SIMD4<Float>.zero
    var ball6 = SIMD4<Float>.zero
    var ball7 = SIMD4<Float>.zero

    mutating func setBall(_ ball: SIMD4<Float>, at index: Int) {
        switch index {
        case 0: ball0 = ball
        case 1: ball1 = ball
        case 2: ball2 = ball
        case 3: ball3 = ball
        case 4: ball4 = ball
        case 5: ball5 = ball
        case 6: ball6 = ball
        case 7: ball7 = ball
        default: break
        }
    }

    mutating func setProgress(_ progress: Float, at index: Int) {
        guard (0..<8).contains(index) else { return }
        if index < 4 {
            progress0To3[index] = progress
        } else {
            progress4To7[index - 4] = progress
        }
    }
}

@MainActor
final class LiquidRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var parameters = LiquidParameters()
    private let startTime = ProcessInfo.processInfo.systemUptime

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        guard let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: LiquidShaderSource.source, options: nil),
              let vertexFunction = library.makeFunction(name: "liquidVertex"),
              let fragmentFunction = library.makeFunction(name: "liquidFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        super.init()
    }

    func update(parameters: LiquidParameters) {
        self.parameters = parameters
    }

    func update(parameters: LiquidParameters, view: MTKView) {
        update(parameters: parameters)
        view.setNeedsDisplay(view.bounds)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encodeFrame(with: encoder, drawableSize: view.drawableSize)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func renderImage(drawableSize: CGSize) -> CGImage? {
        let width = Int(drawableSize.width.rounded(.up))
        let height = Int(drawableSize.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget]
        textureDescriptor.storageMode = .shared
        guard let texture = commandQueue.device.makeTexture(descriptor: textureDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return nil
        }

        encodeFrame(with: encoder, drawableSize: CGSize(width: width, height: height))
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private func encodeFrame(with encoder: MTLRenderCommandEncoder, drawableSize: CGSize) {
        var uniforms = makeUniforms(drawableSize: drawableSize)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LiquidUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeUniforms(drawableSize: CGSize) -> LiquidUniforms {
        var uniforms = LiquidUniforms()
        uniforms.resolution = SIMD2(Float(drawableSize.width), Float(drawableSize.height))
        uniforms.time = Float(ProcessInfo.processInfo.systemUptime - startTime)
        uniforms.dropletCount = UInt32(parameters.dropletCount)
        uniforms.threshold = parameters.threshold
        uniforms.perturbation = parameters.perturbation
        uniforms.colorProgress = parameters.colorProgress
        uniforms.surfaceY = parameters.theme.surfaceY
        uniforms.surfaceDepth = parameters.theme.surfaceDepth
        uniforms.dropletY = parameters.theme.dropletY
        uniforms.opacity = parameters.theme.opacity
        uniforms.clearBlue = SIMD4(parameters.theme.clearBlue, 0)
        uniforms.deepBlue = SIMD4(parameters.theme.deepBlue, 0)
        uniforms.asphalt = SIMD4(parameters.theme.asphalt, 0)

        let count = min(parameters.dropletCount, LiquidParameters.maximumDropletCount)
        let centerOffset = Float(count - 1) / 2
        for index in 0..<LiquidParameters.maximumDropletCount {
            guard index < count else {
                uniforms.setBall(.zero, at: index)
                continue
            }
            let hoverScale: Float = index == parameters.hoveredDroplet
                ? parameters.theme.hoverScale
                : 1
            let radius = parameters.radius * hoverScale
            let droplet = parameters.droplets.indices.contains(index) ? parameters.droplets[index] : nil
            let x = droplet?.normalizedX
                ?? 0.5 + (Float(index) - centerOffset) * parameters.spacing
            let baseVerticalRadius = droplet?.halfLength
                ?? parameters.radius * (1 + parameters.stretch * 1.7)
            let baseY = droplet.map {
                parameters.theme.centerY(forHalfLength: $0.halfLength)
            } ?? parameters.theme.dropletY
            let y = baseY
                + parameters.stretch * 0.08
                + parameters.fallProgress * 0.30
            let verticalRadius = baseVerticalRadius * hoverScale
            uniforms.setBall(SIMD4(x, y, radius, verticalRadius), at: index)
            uniforms.setProgress(droplet?.colorProgress ?? parameters.colorProgress, at: index)
        }
        return uniforms
    }
}

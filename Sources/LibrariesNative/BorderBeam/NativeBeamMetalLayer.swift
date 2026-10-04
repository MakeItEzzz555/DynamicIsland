// MIT © 2026 Jakub Antalik; native macOS host added by DynamicIsland.
// BeamShaders.metal is the unchanged official BorderBeamKit shader.
import SwiftUI
import AppKit
import MetalKit

/// Shared compiler and two pipelines. Runtime Metal compilation is required
/// because the installed Xcode lacks its separately downloadable Metal
/// compiler, and plain SwiftPM does not compile stitchable shader resources.
/// No per-frame compilation, display link, or detached work is created.
enum BeamMetalResources {
    static let device = MTLCreateSystemDefaultDevice()
    static let result: Result<[MTLRenderPipelineState], Error> = Result {
        guard let device,
              let url = NativeResources.bundle.url(forResource: "BeamShaders", withExtension: "metal", subdirectory: "Resources")
        else { throw NSError(domain: "BorderBeam", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal device or bundled official shader unavailable"]) }
        // SwiftUI links stitchable functions through its visible-function
        // table. Our fragment entry points call the same equations directly,
        // so mark the two original functions inline for ordinary pipeline
        // linking. The bundled upstream source and equations stay intact.
        let original = try String(contentsOf: url, encoding: .utf8)
        let source = original.replacingOccurrences(of: "[[ stitchable ]]", with: "static inline") + wrappers
        let library = try device.makeLibrary(source: source, options: nil)
        return try ["beamRotateFragment", "beamBlobFragment"].map { name in
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "beamVertex")
            descriptor.fragmentFunction = library.makeFunction(name: name)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
    }

    /// Deterministic native GPU sampling for parity/lifecycle tests. Production
    /// never calls this synchronous readback path or waits for a GPU command.
    static func fixturePixels(_ parameters: BeamLayerParameters, width: Int, height: Int) throws -> [UInt8] {
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              let device, let queue = device.makeCommandQueue() else {
            throw NSError(domain: "BorderBeam", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid fixture dimensions or Metal unavailable"])
        }
        let pipelines = try result.get()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let command = queue.makeCommandBuffer() else { throw NSError(domain: "BorderBeam", code: 3) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw NSError(domain: "BorderBeam", code: 4) }
        encoder.setRenderPipelineState(pipelines[parameters.pipeline])
        parameters.uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        for (index, values) in parameters.arrays.enumerated() {
            let encoded = values.isEmpty ? [Float(0)] : values
            encoded.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: index + 1) }
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        return pixels
    }

    // Only the entry points differ from SwiftUI colorEffect. Every color,
    // geometry, SDF, compositing and corner equation remains upstream.
    private static let wrappers = """

    struct BeamVertexOut { float4 position [[position]]; float2 uv; };
    vertex BeamVertexOut beamVertex(uint id [[vertex_id]]) {
        const float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
        BeamVertexOut out;
        out.position = float4(p[id], 0, 1);
        out.uv = float2((p[id].x+1)*0.5, (1-p[id].y)*0.5);
        return out;
    }
    fragment half4 beamRotateFragment(BeamVertexOut in [[stage_in]],
        constant float4 *u [[buffer(0)]],
        device const float *blobs [[buffer(1)]],
        device const float *bg [[buffer(2)]],
        device const float *mask [[buffer(3)]],
        device const float *cm [[buffer(4)]]) {
        return beamRotateLayer(in.uv*u[0].xy, half4(1), u[0].xy,
            u[0].z, u[0].w, u[1].x, u[1].y, u[1].z,
            blobs, int(u[2].x), bg, int(u[2].y), u[1].w,
            mask, int(u[2].z), cm, int(u[2].w), u[3].x,
            half4(u[4]), u[3].y);
    }
    fragment half4 beamBlobFragment(BeamVertexOut in [[stage_in]],
        constant float4 *u [[buffer(0)]],
        device const float *radial [[buffer(1)]],
        device const float *blobs [[buffer(2)]],
        device const float *cm [[buffer(3)]]) {
        return beamBlobLayer(in.uv*u[0].xy, half4(1), float2(0), u[0].xy,
            u[0].w, u[1].x, u[1].y, u[1].z, u[1].w,
            radial, int(u[2].x), blobs, int(u[2].y), cm, int(u[2].z), u[3].x);
    }
    """
}

public enum BeamMetalDiagnostics {
    /// Explicit failure reporting: a fallback frame is never a parity PASS.
    public static var isAvailable: Bool {
        if case .success = BeamMetalResources.result { return true }
        return false
    }
    public static var failureDescription: String? {
        if case let .failure(error) = BeamMetalResources.result { return error.localizedDescription }
        return nil
    }
}

struct BeamLayerParameters {
    let pipeline: Int
    let uniforms: [SIMD4<Float>]
    let arrays: [[Float]]
    static func rotate(size: CGSize, angle: Double, radius: Double, borderWidth: Double, kind: Double, edgeMaskPx: Double, blobs: [Float], background: [Float], backgroundBlack: Bool, mask: [Float], matrix: [Float], opacity: Double, shadow: BeamRGBA, shadowBlur: Double) -> Self {
        Self(pipeline: 0, uniforms: [
            SIMD4(Float(size.width), Float(size.height), Float(angle), Float(radius)),
            SIMD4(Float(borderWidth), Float(kind), Float(edgeMaskPx), backgroundBlack ? 1 : 0),
            SIMD4(Float(blobs.count), Float(background.count), Float(mask.count), Float(matrix.count)),
            SIMD4(Float(opacity), Float(shadowBlur), 0, 0),
            SIMD4(Float(shadow.r), Float(shadow.g), Float(shadow.b), Float(shadow.a))
        ], arrays: [blobs, background, mask, matrix])
    }
    static func blob(size: CGSize, radius: Double, borderWidth: Double, kind: Double, edgeMaskPx: Double, wrapCorners: Bool, radial: [Float], blobs: [Float], matrix: [Float], opacity: Double) -> Self {
        Self(pipeline: 1, uniforms: [
            SIMD4(Float(size.width), Float(size.height), 0, Float(radius)),
            SIMD4(Float(borderWidth), Float(kind), Float(edgeMaskPx), wrapCorners ? 1 : 0),
            SIMD4(Float(radial.count), Float(blobs.count), Float(matrix.count), 0),
            SIMD4(Float(opacity), 0, 0, 0), SIMD4.zero
        ], arrays: [radial, blobs, matrix])
    }
}

struct NativeBeamMetalLayer: NSViewRepresentable {
    let parameters: BeamLayerParameters
    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) {
        view.parameters = parameters
        view.draw()
    }
    static func dismantleNSView(_ view: Surface, coordinator: ()) {
        view.delegate = nil
        view.releaseDrawableResources()
    }

    final class Surface: MTKView, MTKViewDelegate {
        var parameters: BeamLayerParameters?
        private let commandQueue = BeamMetalResources.device?.makeCommandQueue()
        // Triple-buffered uniforms/arrays prevent CPU writes racing GPU reads.
        // The three banks are reused; a semaphore bounds in-flight work.
        private let inFlight = DispatchSemaphore(value: 3)
        private var banks: [[MTLBuffer?]] = Array(repeating: Array(repeating: nil, count: 5), count: 3)
        private var nextBank = 0

        init() {
            super.init(frame: .zero, device: BeamMetalResources.device)
            colorPixelFormat = .bgra8Unorm
            clearColor = MTLClearColorMake(0, 0, 0, 0)
            framebufferOnly = true
            isPaused = true
            enableSetNeedsDisplay = false
            delegate = self
            wantsLayer = true
            layer?.isOpaque = false
            setAccessibilityElement(false)
            (layer as? CAMetalLayer)?.maximumDrawableCount = 2
        }
        required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func releaseDrawableResources() { parameters = nil; banks = [] }

        func draw(in view: MTKView) {
            guard !banks.isEmpty,
                  let parameters, let device,
                  case let .success(pipelines) = BeamMetalResources.result,
                  let commandQueue,
                  inFlight.wait(timeout: .now()) == .success else { return }
            guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
                  let command = commandQueue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass)
            else { inFlight.signal(); return }
            let bank = nextBank
            nextBank = (nextBank + 1) % banks.count
            let semaphore = inFlight
            command.addCompletedHandler { _ in semaphore.signal() }
            encoder.setRenderPipelineState(pipelines[parameters.pipeline])
            parameters.uniforms.withUnsafeBytes { bytes in
                encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
            }
            for (index, values) in parameters.arrays.enumerated() {
                let byteCount = max(MemoryLayout<Float>.stride, values.count * MemoryLayout<Float>.stride)
                if (banks[bank][index]?.length ?? 0) < byteCount {
                    banks[bank][index] = device.makeBuffer(length: byteCount, options: .storageModeShared)
                }
                guard let buffer = banks[bank][index] else { continue }
                if !values.isEmpty {
                    values.withUnsafeBytes { bytes in buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count) }
                }
                encoder.setFragmentBuffer(buffer, offset: 0, index: index + 1)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }
}

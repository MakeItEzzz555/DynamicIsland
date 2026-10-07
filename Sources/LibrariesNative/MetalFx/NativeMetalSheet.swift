// MIT © 2026 Jakub Antalik; native macOS GPU host by DynamicIsland.
import AppKit
import MetalKit
import SwiftUI

enum MetalSheetResources {
    static let device = MTLCreateSystemDefaultDevice()
    static let result: Result<MTLRenderPipelineState, Error> = Result {
        guard let device, let url = NativeResources.bundle.url(forResource: "MetalFxShaders", withExtension: "metal", subdirectory: "MetalResources") else { throw NSError(domain: "MetalFx", code: 1) }
        let original = try String(contentsOf: url, encoding: .utf8)
        // Preserve the full upstream source/resource; only adapt its native
        // colorEffect entry point to an ordinary macOS fragment pipeline.
        let material = original.components(separatedBy: "// Screen-edge halo (SwiftUI")[0]
            .replacingOccurrences(of: "#include <SwiftUI/SwiftUI.h>", with: "")
            .replacingOccurrences(of: "[[ stitchable ]]", with: "static inline")
        let library = try device.makeLibrary(source: material + """

        struct MfxVertex { float4 position [[position]]; float2 uv; };
        vertex MfxVertex mfxVertex(uint id [[vertex_id]]) {
            const float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
            MfxVertex out; out.position=float4(p[id],0,1);
            out.uv=float2((p[id].x+1)*0.5,(1-p[id].y)*0.5); return out;
        }
        fragment half4 mfxFragment(MfxVertex in [[stage_in]], constant float4 *u [[buffer(0)]]) {
            return mfxLiquidMetal(in.uv*u[0].xy, half4(1), u[1].xy, u[1].zw,
                u[0].z, u[2], u[3], u[4].x, u[4].y, u[4].z, u[4].w,
                u[5].x, u[5].y, u[5].z, u[0].w, u[5].w);
        }
        """, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mfxVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "mfxFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    static func fixturePixels(_ parameters: MetalSheetParameters, side: Int = 64) throws -> [UInt8] {
        guard let device, let queue = device.makeCommandQueue(), side > 0, side <= 512 else { throw NSError(domain: "MetalFx", code: 2) }
        let pipeline = try result.get()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = .renderTarget; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else { throw NSError(domain: "MetalFx", code: 3) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture; pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw NSError(domain: "MetalFx", code: 4) }
        encoder.setRenderPipelineState(pipeline)
        parameters.uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); encoder.endEncoding()
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        bytes.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0) }
        return bytes
    }
}

public enum MetalFxDiagnostics {
    public static var isAvailable: Bool { if case .success = MetalSheetResources.result { return true }; return false }
    public static var failureDescription: String? { if case let .failure(error) = MetalSheetResources.result { return error.localizedDescription }; return nil }
}

struct MetalSheetParameters {
    let uniforms: [SIMD4<Float>]
    init(size: CGSize, mapping: MetalSheetMapping, material: MetalMaterial, time: Double, opacity: Float, displayScale: CGFloat) {
        uniforms = [SIMD4(Float(size.width), Float(size.height), Float(time) * material.speed, opacity),
            SIMD4(mapping.origin.x, mapping.origin.y, mapping.scale.x, mapping.scale.y), material.colorBack, material.colorTint,
            SIMD4(material.repetition, material.softness, material.shiftRed, material.shiftBlue),
            SIMD4(material.distortion, material.contour, material.angle, Float(displayScale))]
    }
}

struct NativeMetalSheet: NSViewRepresentable {
    let parameters: MetalSheetParameters
    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.parameters = parameters; view.draw() }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.delegate = nil; view.parameters = nil; view.releaseDrawables() }

    final class Surface: MTKView, MTKViewDelegate {
        var parameters: MetalSheetParameters?
        var pipeline: MTLRenderPipelineState?
        private let queue = MetalSheetResources.device?.makeCommandQueue()
        private let inFlight = DispatchSemaphore(value: 2)
        init() {
            super.init(frame: .zero, device: MetalSheetResources.device)
            colorPixelFormat = .bgra8Unorm; clearColor = MTLClearColorMake(0, 0, 0, 0)
            isPaused = true; enableSetNeedsDisplay = false; delegate = self
            wantsLayer = true; layer?.isOpaque = false
            setAccessibilityElement(false)
            // Compilation never blocks a shell/layout frame. The normal
            // circle/send affordance remains functional while warming/failing.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let pipeline = try? MetalSheetResources.result.get()
                DispatchQueue.main.async { [weak self] in self?.pipeline = pipeline; self?.draw() }
            }
        }
        required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard let pipeline, let parameters, let queue, window?.occlusionState.contains(.visible) == true,
                  !visibleRect.isEmpty, !isHiddenOrHasHiddenAncestor,
                  inFlight.wait(timeout: .now()) == .success else { return }
            guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
                  let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass)
            else { inFlight.signal(); return }
            let semaphore = inFlight
            command.addCompletedHandler { _ in semaphore.signal() }
            encoder.setRenderPipelineState(pipeline)
            parameters.uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding(); command.present(drawable); command.commit()
        }
    }
}

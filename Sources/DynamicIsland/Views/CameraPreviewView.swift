import AppKit
import AVFoundation
import SwiftUI

/// Renders the controller's running capture session. Owns no capture state;
/// when the session is nil it shows nothing.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession?

    func makeNSView(context: Context) -> CameraPreviewLayerView {
        let view = CameraPreviewLayerView()
        view.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewLayerView, context: Context) {
        nsView.session = session
    }

    static func dismantleNSView(_ nsView: CameraPreviewLayerView, coordinator: ()) {
        nsView.session = nil
    }
}

final class CameraPreviewLayerView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set {
            guard previewLayer.session !== newValue else { return }
            previewLayer.session = newValue
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

import AVFoundation
import Foundation

@MainActor
final class CameraMirrorController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false

    let session = AVCaptureSession()

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    granted ? self.configureAndStart() : (self.permissionDenied = true)
                }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        session.stopRunning()
        isRunning = false
    }

    private func configureAndStart() {
        permissionDenied = false
        if session.inputs.isEmpty,
           let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.beginConfiguration()
            session.addInput(input)
            session.commitConfiguration()
        }
        session.startRunning()
        isRunning = true
    }
}

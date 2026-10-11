import AppKit
@preconcurrency import AVFoundation
import Darwin

/// Packaged, numeric-only capture probe. A missing grant is reported without
/// prompting, replacing an installed app or changing any privacy permission.
@MainActor
enum CameraNavigationNativeAcceptance {
    static func run(directory: URL) async {
        var report: [String: Any] = ["framesSaved": false, "globalInputPosted": false]
        let camera = CameraPreviewController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry())
        await camera.refresh()
        report["permission"] = String(describing: camera.permissionState)
        guard camera.permissionState == .authorized else {
            report["gate"] = "Open DynamicIsland Settings → Island → Gestures → Enable Camera Navigation, then allow Camera access."
            write(report, directory: directory); return
        }
        guard let device = camera.devices.first(where: \.isBuiltIn) ?? camera.devices.first else {
            report["gate"] = "Connect a camera."; write(report, directory: directory); return
        }
        if AVCaptureDevice(uniqueID: device.id)?.isInUseByAnotherApplication == true {
            report["gate"] = "Camera is in use by another application; its active session was preserved."
            write(report, directory: directory); return
        }
        camera.selectedDeviceID = device.id
        let navigation = CameraNavigationLease(controller: camera)
        let mirror = CameraMirrorConsumerLease(controller: camera)
        let metrics = Metrics()
        let mailbox = HandPoseResultMailbox { result in
            if !metrics.ready {
                metrics.ready = true; metrics.startupInferenceMS = result.latency * 1000
            } else { metrics.latencies.append(result.latency * 1000) }
            if result.failed { metrics.failed = true }
            if result.observation != nil { metrics.handFrames += 1 }
        }
        let processor = HandPoseFrameProcessor(generation: 1) { mailbox.submit($0) }
        defer { processor.stop(); camera.terminate() }
        do {
            try await navigation.acquire()
            let session = camera.previewSession
            try await camera.setNavigationProcessor(processor)
            await mirror.acquire(); try await mirror.startExplicitly()
            report["sameCaptureSession"] = session === camera.previewSession
            await mirror.closeByUser()
            report["mirrorCloseKeepsNavigation"] = camera.isRunning
            for _ in 0..<400 {
                if metrics.ready { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard metrics.ready, !metrics.failed else { throw CameraPreviewError.sessionFailed("Hand tracking could not initialize.") }
            report["startupInferenceMS"] = metrics.startupInferenceMS
            metrics.latencies = []; metrics.handFrames = 0
            let started = ProcessInfo.processInfo.systemUptime
            report["activeMemoryMB"] = memoryMB()
            for _ in 0..<200 {
                let before = ProcessInfo.processInfo.systemUptime
                try await Task.sleep(for: .milliseconds(50))
                metrics.uiDelays.append(max(0, ProcessInfo.processInfo.systemUptime - before - 0.05) * 1000)
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            report["inferenceFPS"] = Double(metrics.latencies.count) / elapsed
            report["visionMeanMS"] = metrics.latencies.reduce(0, +) / Double(max(1, metrics.latencies.count))
            report["visionP95MS"] = percentile(metrics.latencies)
            report["uiDelayP95MS"] = percentile(metrics.uiDelays)
            report["handFrames"] = metrics.handFrames
            report["endActiveMemoryMB"] = memoryMB()
            processor.stop(); try await camera.setNavigationProcessor(nil)
            await mirror.acquire(); try await mirror.startExplicitly()
            await navigation.release()
            report["navigationStopKeepsMirror"] = camera.isRunning
            await mirror.release()
            report["finalOwnerStopsCapture"] = !camera.isRunning && camera.previewSession == nil
            report["afterStopMemoryMB"] = memoryMB()
            report["gate"] = "Physical hand direction, pinch/drag, page swipes and mouse priority still require a user exercise in the running island."
        } catch { report["gate"] = error.localizedDescription }
        write(report, directory: directory)
    }
    private final class Metrics {
        var ready = false
        var failed = false
        var startupInferenceMS = 0.0
        var latencies: [Double] = []
        var uiDelays: [Double] = []
        var handFrames = 0
    }
    private static func percentile(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    }
    private static func memoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }
    private static func write(_ report: [String: Any], directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("camera-navigation.json"), options: .atomic)
        } catch { print("Camera acceptance report could not be written.") }
    }
}

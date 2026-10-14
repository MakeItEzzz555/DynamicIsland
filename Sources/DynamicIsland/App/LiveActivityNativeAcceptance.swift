import AppKit
import AVFoundation
import SwiftUI

/// Explicit packaged acceptance entry point. Never registers the normal app delegate,
/// prompts, sends messages, changes user preferences, or replaces an installed bundle.
@MainActor
enum LiveActivityNativeAcceptance {
    static func run(directory: URL) async {
        var report: [String: Any] = ["bundle": Bundle.main.bundleURL.path,
            "buildIdentity": AppRelauncher.buildIdentity ?? "unsigned", "callObservation": "unavailable on native macOS",
            "callControls": "unsupported", "messagesFullDiskAccess": String(describing: FullDiskAccessProbe.state()),
            "messagesLiveIncoming": "requires a new user test notification", "messagesLiveSend": "requires a user-selected recipient and text"]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await renderPreviews(directory: directory)
            report["nativePreviews"] = "six production presentations, normal and Reduce Motion; synthetic data, inert controls"
            let granted = CGPreflightScreenCaptureAccess()
            report["screenCapturePreflight"] = granted
            if granted {
                report["recordings"] = try await recordSources(directory: directory) { rows in report["recordings"] = rows }
            } else {
                report["recordings"] = "blocked: open this exact packaged build, Screen Record → Allow Screen Recording; grant in System Settings, relaunch if offered"
            }
        } catch {
            report["error"] = String(describing: error)
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: directory.appendingPathComponent("acceptance.json"), options: .atomic)
        } catch { fputs("Unable to write acceptance report\n", stderr) }
    }

    private static func renderPreviews(directory: URL) async throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        for reduced in [false, true] {
            for scenario in [LiveActivityLayoutPreviewScenario.activeCall, .connectedCall, .message,
                             .messageReply, .recording, .permissionHover] {
                let view = LiveActivityLayoutSettingsPreview(settings: settings, scenario: scenario)
                    .environment(\.settingsPreviewReduceMotion, reduced)
                    .frame(width: 740, height: 280)
                let host = NSHostingView(rootView: view)
                let panel = NSPanel(contentRect: CGRect(x: 90, y: 120, width: 740, height: 280),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isReleasedWhenClosed = false
                panel.appearance = NSAppearance(named: .darkAqua)
                panel.contentView = host
                panel.orderFrontRegardless()
                defer { panel.orderOut(nil) }
                try await Task.sleep(for: .milliseconds(250))
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    throw ScreenRecordingError.invalidOutput
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
                    throw ScreenRecordingError.invalidOutput
                }
                try png.write(to: directory.appendingPathComponent("\(String(describing: scenario))-\(reduced ? "reduced" : "normal").png"))
            }
        }
    }

    private static func recordSources(directory: URL, progress: ([[String: Any]]) -> Void) async throws -> [[String: Any]] {
        let activities = LiveActivityStore()
        let controller = ScreenRecordingController(liveActivities: activities, capabilities: IslandCapabilityRegistry(),
            requestLedger: .init(defaults: SettingsPreviewDefaults(), buildIdentity: AppRelauncher.buildIdentity))
        controller.options = ScreenRecordingOptions(capturesSystemAudio: false, capturesMicrophone: false,
            showsCursor: false, excludesDynamicIsland: false)
        await controller.prepareTargets(requestPermission: false)
        guard controller.accessState == .granted else {
            throw ScreenRecordingError.permissionNotActive
        }
        let display = controller.displays.first
        let window = NSWindow(contentRect: CGRect(x: 150, y: 150, width: 480, height: 320),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .systemBlue
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(500))
        await controller.prepareTargets(requestPermission: false)
        guard let screen = window.screen, let displayID = ScreenRecordingController.displayID(for: screen) else {
            throw ScreenRecordingError.noDisplay
        }
        let sourceContent = try await SystemScreenCaptureAuthorization().shareableContent()
        let sourceWindow = sourceContent.windows.first { $0.windowID == CGWindowID(window.windowNumber) }
        let area = CGRect(x: window.frame.minX - screen.frame.minX,
            y: screen.frame.maxY - window.frame.maxY, width: window.frame.width, height: window.frame.height)
        var rows: [[String: Any]] = [["sourceGeometry": "NSWindow \(window.frame); SCWindow \(String(describing: sourceWindow?.frame)); NSscreen \(screen.frame); onActiveSpace \(window.isOnActiveSpace); occlusion \(window.occlusionState.rawValue)"]]
        progress(rows)
        var includedCenter: [Int]?
        var hiddenCursorPatch: [Int]?
        for source in ["display", "window", "area", "pauseResume", "systemAudio", "excludeApp", "cursorHidden", "cursorShown", "microphone"] {
            if display == nil, !["window", "pauseResume", "microphone"].contains(source) {
                rows.append(["source": source, "result": "gate: ScreenCaptureKit returned no shareable display; validate on an unlocked local desktop"])
                progress(rows)
                continue
            }
            if source == "microphone", !controller.microphoneCaptureAvailable || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                rows.append(["source": source, "result": "gate: enable Microphone audio and Start; microphone permission required (macOS 15+)"])
                continue
            }
            controller.options.capturesSystemAudio = source == "systemAudio"
            controller.options.capturesMicrophone = source == "microphone"
            controller.options.excludesDynamicIsland = source == "excludeApp"
            controller.options.showsCursor = source == "display" || source == "cursorShown"
            var restorePointer: CGPoint?
            defer { if let restorePointer { CGWarpMouseCursorPosition(restorePointer) } }
            if source == "cursorHidden" || source == "cursorShown" {
                restorePointer = CGEvent(source: nil)?.location
                let bounds = CGDisplayBounds(displayID)
                guard restorePointer != nil,
                      CGWarpMouseCursorPosition(CGPoint(x: bounds.minX + area.midX, y: bounds.minY + area.midY)) == .success else {
                    throw ScreenRecordingError.captureUnavailable("Cursor placement failed")
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            switch source {
            case "display", "systemAudio": await controller.startDisplay(display!.id)
            case "area", "excludeApp", "cursorHidden", "cursorShown": await controller.startArea(displayID: displayID, sourceRect: area)
            default: await controller.startWindow(CGWindowID(window.windowNumber))
            }
            let deadline = Date().addingTimeInterval(10)
            while controller.phase == .preparing, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            guard controller.phase == .recording else { throw ScreenRecordingError.captureUnavailable(controller.statusText) }
            var sound: Process?
            if source == "systemAudio" {
                let player = Process()
                player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                player.arguments = ["-v", "0.1", "/System/Library/Sounds/Glass.aiff"]
                try player.run()
                sound = player
            }
            if source == "pauseResume" {
                try await Task.sleep(for: .seconds(1.5))
                controller.pause()
                let paused = controller.recordedDuration
                try await Task.sleep(for: .seconds(1))
                guard abs(controller.recordedDuration - paused) < 0.15 else { throw ScreenRecordingError.invalidOutput }
                controller.resume()
                try await Task.sleep(for: .seconds(1.5))
            } else { try await Task.sleep(for: .seconds(3)) }
            await controller.stopAndSave()
            guard controller.phase == .saved, let url = controller.lastSavedURL else {
                throw ScreenRecordingError.finalizationFailed(controller.statusText)
            }
            defer { try? FileManager.default.removeItem(at: url) }
            let asset = AVURLAsset(url: url)
            let seconds = CMTimeGetSeconds(try await asset.load(.duration))
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first, abs(seconds - 3) < 0.6,
                  !activities.activities.contains(where: { $0.kind == .screenRecording }) else {
                throw ScreenRecordingError.invalidOutput
            }
            let retained = directory.appendingPathComponent("\(source).mp4")
            if FileManager.default.fileExists(atPath: retained.path) { try FileManager.default.removeItem(at: retained) }
            try FileManager.default.copyItem(at: url, to: retained)
            let size = try await track.load(.naturalSize)
            let trackDuration = CMTimeGetSeconds(try await track.load(.timeRange).duration)
            let reader = try AVAssetReader(asset: asset)
            let video = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(video)
            guard reader.startReading(), let sample = video.copyNextSampleBuffer(),
                  let pixel = CMSampleBufferGetImageBuffer(sample) else { throw ScreenRecordingError.invalidOutput }
            CVPixelBufferLockBaseAddress(pixel, .readOnly)
            var center: [Int] = []
            var cursorPatch: [Int] = []
            if let base = CVPixelBufferGetBaseAddress(pixel) {
                let offset = (CVPixelBufferGetHeight(pixel) / 2) * CVPixelBufferGetBytesPerRow(pixel)
                    + (CVPixelBufferGetWidth(pixel) / 2) * 4
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                center = (0..<3).map { Int(bytes[offset + $0]) }
                if source == "cursorHidden" || source == "cursorShown" {
                    let rowSize = CVPixelBufferGetBytesPerRow(pixel)
                    let midX = CVPixelBufferGetWidth(pixel) / 2
                    let midY = CVPixelBufferGetHeight(pixel) / 2
                    for y in max(midY - 4, 0)..<min(midY + 50, CVPixelBufferGetHeight(pixel)) {
                        for x in max(midX - 4, 0)..<min(midX + 40, CVPixelBufferGetWidth(pixel)) {
                            for channel in 0..<3 { cursorPatch.append(Int(bytes[y * rowSize + x * 4 + channel])) }
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
            reader.cancelReading()
            if ["window", "area", "pauseResume", "cursorHidden", "microphone"].contains(source) {
                guard center.count == 3, center[0] > 140, center[1] > 70, center[2] < 130 else {
                    throw ScreenRecordingError.captureUnavailable("\(source) did not capture the blue test-owned window; center BGR \(center)")
                }
            }
            if source == "area" { includedCenter = center }
            if source == "cursorHidden" { hiddenCursorPatch = cursorPatch }
            if source == "cursorShown" {
                guard let hiddenCursorPatch, !cursorPatch.isEmpty,
                      zip(cursorPatch, hiddenCursorPatch).filter({ abs($0.0 - $0.1) > 40 }).count > 30 else {
                    throw ScreenRecordingError.captureUnavailable("Cursor-enabled capture matched the cursor-hidden capture")
                }
            }
            if source == "excludeApp" {
                guard let includedCenter, center.count == 3,
                      zip(center, includedCenter).reduce(0, { $0 + abs($1.0 - $1.1) }) > 40 else {
                    throw ScreenRecordingError.captureUnavailable("Exclude content check: included \(String(describing: includedCenter)), excluded \(center); source frame \(String(describing: sourceWindow?.frame)); crop \(area)")
                }
            }
            if source != "display", source != "systemAudio" {
                guard abs(size.width - area.width * screen.backingScaleFactor) <= 2,
                      abs(size.height - area.height * screen.backingScaleFactor) <= 2 else { throw ScreenRecordingError.invalidOutput }
            }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            var audioSamples = 0
            if source == "systemAudio" || source == "microphone" {
                guard let audio = audioTracks.first else { throw ScreenRecordingError.invalidOutput }
                let audioReader = try AVAssetReader(asset: asset)
                let audioOutput = AVAssetReaderTrackOutput(track: audio, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
                audioReader.add(audioOutput)
                guard audioReader.startReading() else { throw ScreenRecordingError.invalidOutput }
                while let buffer = audioOutput.copyNextSampleBuffer() { audioSamples += CMSampleBufferGetNumSamples(buffer) }
                guard audioSamples > 0 else { throw ScreenRecordingError.invalidOutput }
            } else if !audioTracks.isEmpty { throw ScreenRecordingError.invalidOutput }
            rows.append(["source": source, "duration": seconds, "trackDuration": trackDuration,
                "width": size.width, "height": size.height, "decode": "passed",
                "audioTracks": audioTracks.count, "audioSamples": audioSamples,
                "centerBGR": center,
                "cursorEnabled": controller.options.showsCursor,
                "excludedOwnWindow": source == "excludeApp", "file": retained.path])
            progress(rows)
            _ = sound
        }
        await controller.startWindow(CGWindowID.max)
        guard controller.phase == .failed, activities.activities.isEmpty else { throw ScreenRecordingError.invalidOutput }
        rows.append(["failedStart": "invalid window rejected, no activity remains",
            "cursorToggle": "real captured pixel difference on the test-owned window; public CG cursor placement, pointer restored"])
        return rows
    }
}

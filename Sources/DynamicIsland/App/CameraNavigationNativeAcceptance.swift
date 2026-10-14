import AppKit
@preconcurrency import AVFoundation
import Darwin

/// Packaged, numeric-only capture probe. A missing grant is reported without
/// prompting, replacing an installed app or changing any privacy permission.
@MainActor
enum CameraNavigationNativeAcceptance {
    static func run(directory: URL) async {
        let settings = AppSettings()
        var report: [String: Any] = ["framesSaved": false, "globalInputPosted": false,
            "configuredInputSource": settings.gestureInputSource.rawValue,
            "desiredCameraNavigation": settings.gesturesEnabled && settings.gestureInputSource == .camera,
            "cameraPermission": "not verified", "cameraRunning": false, "navigationOwners": 0,
            "videoOutputAttached": false, "firstFrameReceived": false, "visionFPS": 0.0,
            "validHandObserved": false, "pointerPresentationProduced": false,
            "duplicateDynamicIslandInstances": CameraNavigationController.normalInstanceCount()]
        let camera = CameraPreviewController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry())
        await camera.refresh()
        report["cameraPermission"] = String(describing: camera.permissionState)
        guard camera.permissionState == .authorized else {
            report["gate"] = "Select Camera under Settings → Island → Gestures, enable gesture navigation, then press Allow Camera."
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
        let fixtureSettings = AppSettings(defaults: SettingsPreviewDefaults())
        fixtureSettings.gesturesEnabled = settings.gesturesEnabled
        fixtureSettings.gestureInputSource = settings.gestureInputSource
        fixtureSettings.clipboardHistoryEnabled = false
        let state = IslandStateStore()
        // Run the actual production root/window with inert services and no input delivery.
        let controller = CameraNavigationController(camera: camera, settings: settings, deliversInput: false)
        let overlay = OverlayWindowController(settings: fixtureSettings, islandState: state,
            modules: probeModules(settings: fixtureSettings, camera: camera),
            geometryService: NotchGeometryService(), cameraNavigation: controller)
        overlay.setVisible(true)
        let mirror = CameraMirrorConsumerLease(controller: camera)
        defer { controller.terminate(); camera.terminate(); overlay.setVisible(false) }
        do {
            await controller.waitForReconciliation()
            for _ in 0..<400 {
                if controller.visionHasProducedResult || controller.runtimeState == .noFrames || !controller.isEnabled { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            report["cameraRunning"] = camera.isRunning
            report["navigationOwners"] = camera.activeNavigationOwners
            report["videoOutputAttached"] = controller.videoOutputAttached
            report["firstFrameReceived"] = controller.firstFrameReceived
            report["collapsedPointerOverlayMounted"] = overlay.cameraPointerOverlayMounted
            state.expand()
            try await Task.sleep(for: .milliseconds(100))
            report["expandedPointerOverlayMounted"] = overlay.cameraPointerOverlayMounted
            report["activeMemoryMB"] = memoryMB()
            if controller.visionHasProducedResult {
                let session = camera.previewSession
                await mirror.acquire(); try await mirror.startExplicitly()
                report["sameCaptureSession"] = session === camera.previewSession
                await mirror.closeByUser()
                report["mirrorCloseKeepsNavigation"] = camera.isRunning
                for _ in 0..<200 { try await Task.sleep(for: .milliseconds(50)) }
                report["visionFPS"] = controller.recognitionFPS
                report["visionMeanMS"] = controller.meanLatencyMS
                report["visionP95MS"] = controller.p95LatencyMS
                report["validHandObserved"] = controller.validHandObserved
                report["pointerPresentationProduced"] = controller.pointerPresentationProduced
                report["runtimeState"] = controller.status
                controller.refreshInstanceDiagnostic()
                report["duplicateDynamicIslandInstances"] = controller.duplicateDynamicIslandInstances
                report["endActiveMemoryMB"] = memoryMB()
                await mirror.acquire(); try await mirror.startExplicitly()
                await controller.shutdown()
                report["navigationStopKeepsMirror"] = camera.isRunning
                await mirror.release()
                report["finalOwnerStopsCapture"] = !camera.isRunning && camera.previewSession == nil
                report["afterStopMemoryMB"] = memoryMB()
                report["gate"] = "Physical hand direction, pinch/drag, swipes, scroll separation and mouse priority require a user exercise. Quit other DynamicIsland copies manually before using the repaired package."
            } else {
                report["runtimeState"] = controller.status
                report["gate"] = controller.desiredCameraNavigation ? "Check Again or select another camera; quit other DynamicIsland copies manually if needed." : "Enable gesture navigation and select Camera."
                await controller.shutdown()
            }
        } catch { report["gate"] = error.localizedDescription; await controller.shutdown() }
        write(report, directory: directory)
    }
    private static func probeModules(settings: AppSettings, camera: CameraPreviewController) -> IslandModules {
        let defaults = SettingsPreviewDefaults(), activities = LiveActivityStore(), capabilities = IslandCapabilityRegistry()
        let shelf = FileShelfStore(settings: settings, defaults: defaults)
        let operations = BackgroundOperationController(liveActivities: activities)
        let events = AgentEventStore(), approvals = AgentApprovalController()
        let coordinator = AgentIngestionCoordinator(eventStore: events)
        let recorder = ScreenRecordingController(liveActivities: activities, capabilities: capabilities)
        let removal = BackgroundRemovalController(liveActivities: activities, capabilities: capabilities, addToShelf: { _ in })
        let basket = BasketManager(settings: settings, shelf: shelf, operations: operations)
        return IslandModules(media: MediaController(), fileShelf: shelf, backgroundOperations: operations,
            fileDragSession: FileDragSessionController(), shortcuts: ShortcutsStore(), timer: TimerController(),
            stats: SystemStatsController(), liveActivities: activities,
            clipboardHistory: ClipboardHistoryStore(settings: settings, automaticallySchedulesTimer: false),
            navigation: IslandNavigationStore(), agentEvents: events, agentAttention: AgentAttentionCoordinator(),
            agentApprovalControl: approvals,
            agentManagedControl: AgentManagedSessionController(provider: nil, coordinator: coordinator, eventStore: events, approvals: approvals),
            agentProjects: AgentProjectProjectionStore(), agentActivityRecorder: AgentActivityRecorder(),
            productivity: ProductivityModules(capabilities: capabilities,
                keepAwake: KeepAwakeController(liveActivities: activities, capabilities: capabilities),
                windowSnap: WindowSnapController(liveActivities: activities, capabilities: capabilities),
                terminal: TerminalSessionController(liveActivities: activities, capabilities: capabilities),
                reminders: RemindersController(liveActivities: activities, capabilities: capabilities),
                voice: VoiceTranscriptionController(liveActivities: activities, capabilities: capabilities, addToShelf: { _ in }),
                camera: camera, backgroundRemoval: removal, screenRecording: recorder,
                screenRecordingSetup: .production(controller: recorder)),
            systemHUD: SystemHUDController(settings: settings, liveActivities: activities),
            messaging: MessagingController(adapters: [], liveActivities: activities),
            rightWorkspace: RightWorkspaceStore(defaults: defaults),
            workspaceServices: WorkspaceServices(appLibrary: AppLibraryStore(defaults: defaults),
                calendar: CalendarEventsController(), spotify: SpotifyLibraryController(defaults: defaults, tokens: EmptyCredentials())),
            basketPresenter: BasketPresenter(manager: basket, settings: settings, fileShelf: shelf, backgroundRemoval: removal))
    }

    private struct EmptyCredentials: SpotifyCredentialStoring {
        func credentials() -> SpotifyStoredCredentials { .init() }
        func store(accessToken: String, expiresAt: Date, refreshToken: String?, authorizationDate: Date?) {}
        func clear() {}
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

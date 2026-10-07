import Foundation

struct ProductivityModules {
    let capabilities: IslandCapabilityRegistry
    let keepAwake: KeepAwakeController
    let windowSnap: WindowSnapController
    let terminal: TerminalSessionController
    let reminders: RemindersController
    let voice: VoiceTranscriptionController
    let camera: CameraPreviewController
    let backgroundRemoval: BackgroundRemovalController
    let screenRecording: ScreenRecordingController
    let screenRecordingSetup: ScreenRecordingSetupPresenter
}

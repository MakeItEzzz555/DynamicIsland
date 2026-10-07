import Foundation

enum LiveActivityLayoutPreviewScenario: String, CaseIterable, Identifiable {
    case media = "Media"
    case mediaTimer = "Media + Timer"
    case mediaBatteryTimer = "Battery + Media + Timer"
    case agentTimer = "Agent + Timer"
    case mediaVolume = "Media + Volume HUD"
    case constrained = "Constrained"
    case mediaKeepAwake = "Media + Keep Awake"
    case mediaTimerKeepAwake = "Media + Timer + Keep Awake"
    case agentTerminal = "Agent + Terminal Task"
    case timerReminder = "Timer + Reminder"
    case voiceTimer = "Voice Recording + Timer"
    case camera = "Camera"
    case backgroundRemoval = "Background Removal"
    case keepAwakeVolume = "Keep Awake + Volume HUD"

    var id: String { rawValue }
}

/// Settings preview scenarios. Productivity activities come from each
/// controller's production activity builder so previews use real metadata.
@MainActor
enum LiveActivityPreviewCatalog {
    static let referenceDate = Date(timeIntervalSince1970: 1_000)

    static func activities(for scenario: LiveActivityLayoutPreviewScenario) -> [DynamicIslandLiveActivity] {
        switch scenario {
        case .media:
            [media]
        case .mediaTimer:
            [media, timer]
        case .mediaBatteryTimer, .constrained:
            [media, battery, timer]
        case .agentTimer:
            [agent, timer]
        case .mediaVolume:
            [media, timer, volume]
        case .mediaKeepAwake:
            [media, keepAwake]
        case .mediaTimerKeepAwake:
            [media, timer, keepAwake]
        case .agentTerminal:
            [agent, terminal]
        case .timerReminder:
            [timer, reminder]
        case .voiceTimer:
            [voiceRecording, timer]
        case .camera:
            [camera]
        case .backgroundRemoval:
            [backgroundRemoval]
        case .keepAwakeVolume:
            [keepAwake, volume]
        }
    }

    // MARK: Existing sources (published inline by AppDelegate)

    static let media = DynamicIslandLiveActivity(
        id: "preview-media",
        kind: .media,
        title: "Now Playing",
        subtitle: "Artist",
        symbolName: "music.note",
        priority: 80,
        isActive: true,
        progress: 0.42,
        updatedAt: referenceDate
    )

    static let timer = DynamicIslandLiveActivity(
        id: "preview-timer",
        kind: .timer,
        title: "Timer",
        subtitle: "4:18",
        symbolName: "timer",
        priority: 90,
        isActive: true,
        progress: 0.64,
        updatedAt: referenceDate
    )

    static let battery = DynamicIslandLiveActivity(
        id: "preview-battery",
        kind: .battery,
        title: "Battery",
        subtitle: "18%",
        symbolName: "battery.25percent",
        priority: 85,
        isActive: true,
        progress: 0.18,
        updatedAt: referenceDate,
        batteryState: .low
    )

    static let agent = DynamicIslandLiveActivity(
        id: "preview-agent",
        kind: .agent,
        title: "Codex",
        subtitle: "Working",
        symbolName: "terminal.fill",
        priority: 130,
        isActive: true,
        progress: nil,
        updatedAt: referenceDate
    )

    static let volume = DynamicIslandLiveActivity(
        id: "preview-system",
        kind: .system,
        title: "Volume",
        subtitle: "68%",
        symbolName: "speaker.wave.2.fill",
        priority: 200,
        isActive: true,
        progress: 0.68,
        updatedAt: referenceDate
    )

    // MARK: Productivity (production builders)

    static var keepAwake: DynamicIslandLiveActivity {
        KeepAwakeController.makeActivity(subtitle: "28 min left", progress: 0.07, hasDuration: true, updatedAt: referenceDate)
    }

    static var terminal: DynamicIslandLiveActivity {
        TerminalSessionController.makeActivity(
            title: "swift test",
            subtitle: "Running",
            isActive: true,
            completionEvidence: nil,
            updatedAt: referenceDate
        )
    }

    static var reminder: DynamicIslandLiveActivity {
        RemindersController.makeActivity(
            for: ReminderDescriptor(
                id: "preview-reminder",
                title: "Submit report",
                listID: "work",
                listTitle: "Work",
                dueDate: referenceDate.addingTimeInterval(1_800),
                isCompleted: false
            ),
            updatedAt: referenceDate
        )
    }

    static var voiceRecording: DynamicIslandLiveActivity {
        VoiceTranscriptionController.makeRecordingActivity(startedAt: referenceDate)
    }

    static var camera: DynamicIslandLiveActivity {
        CameraPreviewController.makeActivity(deviceName: "FaceTime HD Camera", updatedAt: referenceDate)
    }

    static var backgroundRemoval: DynamicIslandLiveActivity {
        BackgroundRemovalController.makeActivity(filename: "Portrait.jpeg", updatedAt: referenceDate)
    }
}

import AppKit
import Combine
import SwiftUI

@main
struct DynamicIslandApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let islandState = IslandStateStore()
    private lazy var fileShelf = FileShelfStore(settings: settings)
    private let shortcuts = ShortcutsStore()
    private let media = MediaController()
    private let timer = TimerController()
    private let stats = SystemStatsController()
    private let liveActivities = LiveActivityStore()
    private let navigation = IslandNavigationStore()
    private let geometryService = NotchGeometryService()

    private var overlayController: OverlayWindowController?
    private var menuController: MenuBarController?
    private var settingsController: SettingsWindowController?
    private var eventMonitor: Any?
    private var lastObservedFileShelfCount = 0
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcuts.seedDefaultsIfNeeded()

        let modules = IslandModules(
            media: media,
            fileShelf: fileShelf,
            shortcuts: shortcuts,
            timer: timer,
            stats: stats,
            liveActivities: liveActivities,
            navigation: navigation
        )
        #if DEBUG
        debugPrint(
            "DynamicIsland AppDelegate modules",
            "mediaInstance=\(ObjectIdentifier(media))"
        )
        #endif

        let overlayController = OverlayWindowController(
            settings: settings,
            islandState: islandState,
            modules: modules,
            geometryService: geometryService,
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )
        self.overlayController = overlayController
        overlayController.show()
        LaunchAtLoginController.setEnabled(settings.launchAtLoginEnabled)

        settings.$launchAtLoginEnabled
            .removeDuplicates()
            .sink { enabled in
                LaunchAtLoginController.setEnabled(enabled)
            }
            .store(in: &cancellables)

        settings.$statsRefreshIntervalSeconds
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.stats.setRefreshInterval(interval)
            }
            .store(in: &cancellables)

        installLiveActivityObservers()

        menuController = MenuBarController(
            settings: settings,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onToggleOverlay: { [weak self] in self?.toggleOverlay() },
            onQuit: { NSApp.terminate(nil) }
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displaysChanged),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    @objc private func displaysChanged() {
        overlayController?.reposition()
    }

    private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                settings: settings,
                shortcuts: shortcuts
            )
        }
        settingsController?.show()
    }

    private func toggleOverlay() {
        settings.overlayEnabled.toggle()
        overlayController?.setVisible(settings.overlayEnabled)
    }

    private func installLiveActivityObservers() {
        Publishers.CombineLatest3(timer.$remainingSeconds, timer.$totalSeconds, timer.$isRunning)
            .sink { [weak self] remainingSeconds, totalSeconds, isRunning in
                self?.updateTimerLiveActivity(
                    remainingSeconds: remainingSeconds,
                    totalSeconds: totalSeconds,
                    isRunning: isRunning
                )
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            media.$hasActiveMediaSource,
            media.$title,
            media.$artist,
            media.$sourceName
        )
        .sink { [weak self] _, _, _, _ in
            self?.updateMediaLiveActivity()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            media.$isPlaying,
            media.$hasPlaybackProgress,
            media.$playbackPosition,
            media.$duration
        )
        .sink { [weak self] _, _, _, _ in
            self?.updateMediaLiveActivity()
        }
        .store(in: &cancellables)

        lastObservedFileShelfCount = fileShelf.files.count
        fileShelf.$files
            .sink { [weak self] files in
                self?.updateFileTrayLiveActivity(files: files)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            settings.$liveActivitiesEnabled,
            settings.$showMusicLiveActivity,
            settings.$showTimerLiveActivity,
            settings.$showFileDropLiveActivity
        )
        .sink { [weak self] _, _, _, _ in
            self?.refreshLiveActivitiesForSettingsChange()
        }
        .store(in: &cancellables)
    }

    private func refreshLiveActivitiesForSettingsChange() {
        guard settings.liveActivitiesEnabled else {
            liveActivities.removeAll()
            return
        }
        updateTimerLiveActivity(
            remainingSeconds: timer.remainingSeconds,
            totalSeconds: timer.totalSeconds,
            isRunning: timer.isRunning
        )
        updateMediaLiveActivity()
        updateFileTrayLiveActivity(files: fileShelf.files)
    }

    private func updateTimerLiveActivity(
        remainingSeconds: Int,
        totalSeconds: Int,
        isRunning: Bool
    ) {
        guard settings.liveActivitiesEnabled, settings.showTimerLiveActivity else {
            liveActivities.remove(id: LiveActivityStore.timerActivityID)
            return
        }
        let hasPausedPartialTimer = !isRunning && remainingSeconds > 0 && remainingSeconds < totalSeconds
        guard isRunning || hasPausedPartialTimer else {
            liveActivities.remove(id: LiveActivityStore.timerActivityID)
            return
        }

        let progress = TimerProgressFormatting.progress(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds
        )
        liveActivities.update(
            DynamicIslandLiveActivity(
                id: LiveActivityStore.timerActivityID,
                kind: .timer,
                title: "Timer",
                subtitle: isRunning ? Self.formattedTimerText(remainingSeconds) : "Paused • \(Self.formattedTimerText(remainingSeconds))",
                symbolName: isRunning ? "timer" : "pause.circle.fill",
                priority: isRunning ? 90 : 70,
                isActive: isRunning,
                progress: LiveActivityStore.clampedProgress(progress),
                updatedAt: Date()
            )
        )
    }

    private func updateMediaLiveActivity() {
        guard settings.liveActivitiesEnabled, settings.showMusicLiveActivity, media.hasActiveMediaSource else {
            liveActivities.remove(id: LiveActivityStore.mediaActivityID)
            return
        }
        let subtitleParts = [media.artist, media.sourceName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let progress: Double?
        if media.hasPlaybackProgress {
            progress = media.duration > 0 ? media.playbackPosition / media.duration : nil
        } else {
            progress = nil
        }

        liveActivities.update(
            DynamicIslandLiveActivity(
                id: LiveActivityStore.mediaActivityID,
                kind: .media,
                title: media.title,
                subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " • "),
                symbolName: media.isPlaying ? "play.fill" : "pause.fill",
                priority: media.isPlaying ? 80 : 55,
                isActive: media.isPlaying,
                progress: LiveActivityStore.clampedProgress(progress),
                updatedAt: Date()
            )
        )
    }

    private func updateFileTrayLiveActivity(files: [URL]) {
        guard settings.liveActivitiesEnabled, settings.showFileDropLiveActivity else {
            liveActivities.remove(id: LiveActivityStore.fileTrayActivityID)
            lastObservedFileShelfCount = files.count
            return
        }
        defer {
            lastObservedFileShelfCount = files.count
        }
        guard !files.isEmpty else {
            liveActivities.remove(id: LiveActivityStore.fileTrayActivityID)
            return
        }
        guard files.count > lastObservedFileShelfCount else { return }

        liveActivities.update(
            DynamicIslandLiveActivity(
                id: LiveActivityStore.fileTrayActivityID,
                kind: .fileTray,
                title: "Files added",
                subtitle: "\(files.count) \(files.count == 1 ? "file" : "files") in Tray",
                symbolName: "tray.and.arrow.down.fill",
                priority: 50,
                isActive: true,
                progress: nil,
                updatedAt: Date()
            )
        )
    }

    private static func formattedTimerText(_ seconds: Int) -> String {
        LiveActivityTimeFormatting.remainingTime(seconds)
    }
}

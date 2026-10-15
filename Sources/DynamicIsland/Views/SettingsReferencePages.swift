import AppKit
import SwiftUI

extension SettingsView {
    var accountPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 72)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("DynamicIsland").font(.title2.bold())
                Text("A local installation, with integrations you control.").foregroundStyle(.secondary)
            }
            SettingsGroup("Installation") {
                LabeledContent("License", value: "No license required")
                LabeledContent("Account", value: "No account required")
            }
            SettingsGroup("Integrations") {
                SettingsNavigationRow(title: "AI Agents", subtitle: "Providers, sessions and exact approvals", symbol: "cpu") {
                    navigation.navigate(.section(.agents))
                }
                SettingsNavigationRow(title: "Messages & FaceTime", subtitle: "Review permissions and communication capabilities", symbol: "message") {
                    navigation.navigate(.section(.messaging))
                }
                SettingsNavigationRow(title: "Apps & media", subtitle: "Configure local apps and optional Spotify access", symbol: "music.note") {
                    navigation.navigate(.section(.rightWorkspace))
                }
            }
        }
    }

    var generalPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("") {
                SettingsLoginItemRow(settings: settings)
                Divider()
                HStack {
                    Text("Visibility")
                    Spacer()
                    Toggle("Menu bar icon", isOn: $settings.menuBarIconEnabled).disabled(!settings.dockIconEnabled)
                    Toggle("Dock icon", isOn: $settings.dockIconEnabled)
                }.toggleStyle(.checkbox)
                .help("Keep at least one app icon visible to reopen Settings.")
            }
            SettingsGroup("Appearance and access") {
                SettingsNavigationRow(title: "Appearance", subtitle: "Theme, shell and visualizer", symbol: "paintbrush.fill") {
                    navigation.navigate(.section(.appearance))
                }
                SettingsNavigationRow(title: "Permissions", subtitle: "Camera, recording and communication access", symbol: "hand.raised.fill") {
                    navigation.navigate(.permissions)
                }
            }
            SettingsGroup("Notch interaction") {
                LabeledContent("Right-click Notch", value: "Context menu")
                Text("Right-click an accessible empty area at the top of the collapsed island for Settings, Clipboard History and Quit Island. Protected controls and files keep their own menus.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Expand on click", isOn: $settings.expandOnClick)
                Toggle("Collapse on mouse leave", isOn: $settings.collapseOnMouseLeave)
                SettingsNavigationRow(title: "Gesture shortcuts", subtitle: "Pointer, trackpad and Camera Navigation", symbol: "hand.raised") {
                    navigation.navigate(.section(.gestures))
                }
            }
            SettingsGroup("Hide in apps") { SettingsHiddenAppsView(settings: settings) }
            SettingsGroup("File handling") {
                Toggle("Protect originals by confirming shelf clearing", isOn: $settings.confirmBeforeClearShelf)
                SettingsNavigationRow(title: "File Tray", subtitle: "Drop targets, persistence and contextual file actions", symbol: "tray.full") {
                    navigation.navigate(.section(.tray))
                }
            }
            SettingsGroup("Quick Actions") {
                SettingsShortcutStrip(store: shortcuts)
            }
        }
    }

    var shelfPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("Widgets") {
                if let previews, let store = previews.customization {
                    SettingsWorkspaceLayoutPreview(settings: settings, store: store, dependencies: previews, navigation: navigation)
                } else { IslandShellSettingsPreview(settings: settings, dependencies: previews) }
                SettingsNavigationRow(title: "Custom Shelf", subtitle: "Widget placement, sizes and vertical arrangement", symbol: "rectangle.split.3x1") {
                    navigation.navigate(.section(.rightWorkspace))
                }
                SettingsWidgetIconsPreview(settings: settings) { navigation.navigate(.section(.tabs)) }
                Text("Favorites").font(.headline)
                SettingsShortcutStrip(store: shortcuts)
            }
            SettingsGroup("Behavior") {
                Toggle("Auto-collapse", isOn: $settings.autoCollapseEnabled)
                Toggle("Auto-expand", isOn: $settings.expandOnHover)
                Text("Hover the collapsed background to open the island. Message reply previews, approvals and protected native controls keep their own interactions.")
                    .font(.caption).foregroundStyle(.secondary)
                SliderRow(title: "Collapse delay", value: Binding(
                    get: { settings.autoCollapseDelayPreset == .manual ? settings.autoCollapseGraceSeconds : settings.autoCollapseDelayPreset.impliedSeconds },
                    set: { settings.autoCollapseGraceSeconds = $0; settings.autoCollapseDelayPreset = .manual }
                ), range: 0.10...2.00, format: "%.2fs", disabled: !settings.autoCollapseEnabled)
                Toggle("Show navigation", isOn: $settings.showNavigationControls)
                SettingsAnimationSpeedChoices(selection: $settings.animationPreset)
                SettingsNavigationRow(title: "Gestures", subtitle: "Configure the existing input authority", symbol: "hand.draw") {
                    navigation.navigate(.section(.gestures))
                }
            }
            SettingsGroup("File tray") {
                Toggle("Show File Tray", isOn: $settings.trayEnabled)
                Toggle("Keep files across launches", isOn: $settings.persistFileShelfAcrossLaunches)
                Picker("File retention", selection: $settings.shelfFileRetention) {
                    ForEach(ShelfFileRetention.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Removes expired references from the Shelf. Your original files stay on disk; selected files and an open action panel are retained until interaction ends.")
                    .font(.caption).foregroundStyle(.secondary)
                SettingsNavigationRow(title: "File actions", subtitle: "Configure real conversion, compression and sharing", symbol: "doc.badge.gearshape") {
                    navigation.navigate(.section(.tray))
                }
            }
        }
    }

    var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Access is requested only when you choose an action. Opening this page does not request permission.")
                .foregroundStyle(.secondary)
            SettingsGroup("Camera") {
                LabeledContent("Camera access", value: String(describing: productivity.camera.permissionState).capitalized)
                SettingsNavigationRow(title: "Camera Navigation", subtitle: "Allow camera access and inspect tracking status", symbol: "camera") {
                    navigation.navigate(.section(.gestures))
                }
            }
            SettingsGroup("Screen recording") {
                SettingsNavigationRow(title: "Screen Recorder", subtitle: "Permission checks, sources and relaunch recovery", symbol: "record.circle") {
                    navigation.navigate(.section(.productivity))
                }
            }
            SettingsGroup("Communications & system controls") {
                SettingsNavigationRow(title: "Messages", subtitle: "Full Disk Access, exact targeting and send confirmation", symbol: "message") {
                    navigation.navigate(.section(.messaging))
                }
                SettingsNavigationRow(title: "FaceTime & Live Activities", subtitle: "Accessibility evidence and supported controls", symbol: "phone") {
                    navigation.navigate(.page(.liveActivities))
                }
                SettingsNavigationRow(title: "Volume & brightness", subtitle: "Accessibility and supported HUD controls", symbol: "speaker.wave.2") {
                    navigation.navigate(.section(.media))
                }
            }
        }
    }

    var lockScreenPage: some View {
        let prefs = Binding(get: { settings.lockScreenPreferences }, set: { settings.lockScreenPreferences = $0 })
        let tested = SkyLightLockScreenSpace.isTestedOS()
        return VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("General") {
                Toggle("Lock Screen widgets (experimental)", isOn: prefs.enabled)
                    .disabled(!tested && !settings.lockScreenPreferences.enabled)
                Text(tested
                     ? "Shows the widgets below over the macOS Lock Screen using private system interfaces. They never take keyboard focus from the password field, are hidden from screenshots, and show only what you allow here. A future macOS update may disable this."
                     : "Unavailable on this macOS version. Lock Screen widgets are enabled only on tested versions (macOS 15.7).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep widgets visible during the screensaver", isOn: prefs.keepVisibleDuringScreensaver)
            }
            SettingsGroup("Lock & Unlock") {
                Toggle("Lock and unlock animation", isOn: prefs.hud)
                lockSoundPicker("Lock sound", selection: prefs.lockSound)
                lockSoundPicker("Unlock sound", selection: prefs.unlockSound)
                LabeledContent("Sound volume") {
                    Slider(value: prefs.soundVolume, in: 0...1).frame(maxWidth: 220)
                }
            }
            SettingsGroup("Widgets") {
                Toggle("Now Playing controls", isOn: prefs.nowPlaying)
                Toggle("Show song title, artist and artwork", isOn: prefs.showTrackDetails)
                    .disabled(!settings.lockScreenPreferences.nowPlaying)
                LabeledContent("Now Playing position") {
                    Slider(value: prefs.mediaVerticalOffset, in: -200...200).frame(maxWidth: 220)
                }
                Toggle("Timer", isOn: prefs.timer)
                Toggle("Keep Awake status", isOn: prefs.keepAwake)
                Toggle("Battery", isOn: prefs.battery)
                Toggle("Generic alerts (low battery, Keep Awake ending)", isOn: prefs.alerts)
            }
            SettingsGroup("Side controls") {
                Toggle("Volume slider on the left edge", isOn: prefs.sideVolume)
                Toggle("Brightness slider on the left edge", isOn: prefs.sideBrightness)
            }
            SettingsGroup("Privacy") {
                Text("Never shown while locked: clipboard, files, agent messages or commands, messages, notification text, calendar details, people or account information. Song details appear only when you turn them on above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func lockSoundPicker(_ title: String, selection: Binding<String>) -> some View {
        HStack {
            Picker(title, selection: selection) {
                ForEach(SettingsLockSoundModel.availableNames, id: \.self) { Text($0).tag($0) }
            }
            Button("Play") {
                LockScreenCoordinator.playSystemSound(selection.wrappedValue, volume: settings.lockScreenPreferences.soundVolume)
            }
            .disabled(selection.wrappedValue == "None")
        }
    }

    var sharingPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.fill").font(.system(size: 56)).foregroundStyle(.tint)
            Text("Local sharing").font(.title2.bold())
            Text("Files stay on your Mac. Share selected files using macOS's sharing services.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            SettingsGroup("File sharing") {
                SettingsNavigationRow(title: "File Tray & AirDrop", subtitle: "Configure the island's existing file sharing controls", symbol: "airplayaudio") {
                    navigation.navigate(.section(.tray))
                }
            }
            SettingsGroup("Cloud service") {
                Text("No cloud provider is configured.")
                Text("Storage quotas, uploads and shared links need a chosen provider and explicit account authorization.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var shortcutsPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Spacer(); Image(systemName: "command").font(.system(size: 46)).foregroundStyle(.tint); Spacer() }
            Text("Configure app shortcuts and input mappings in one place.").foregroundStyle(.secondary)
            SettingsGroup("App shortcuts") { SettingsShortcutStrip(store: shortcuts) }
            SettingsGroup("Navigation") {
                SettingsNavigationRow(title: "Gesture shortcuts", subtitle: "Pointer, trackpad, camera and configured actions", symbol: "hand.raised") {
                    navigation.navigate(.section(.gestures))
                }
                SettingsNavigationRow(title: "Page navigation", subtitle: "Gesture Only and visible controls", symbol: "square.grid.2x2") {
                    navigation.navigate(.section(.tabs))
                }
            }
        }
    }

    var aboutPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup("DynamicIsland") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "SwiftPM")
                Text("Update status has not been checked.").font(.caption).foregroundStyle(.secondary)
                Link("Source and releases", destination: URL(string: "https://github.com/MakeItEzzz555/DynamicIsland")!)
            }
            SettingsGroup("Privacy") {
                LabeledContent("Camera processing", value: "On-device")
                LabeledContent("Online integrations", value: "Opt-in")
                Text("Camera frames are not saved or uploaded. Permission-gated integrations retain their own explicit consent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsGroup("Troubleshooting") {
                SettingsAppearanceTransferView(settings: settings, workspace: previews?.customization)
                if let resetPanelSize { SettingsPanelSizeResetView(reset: resetPanelSize) }
                Button("Reset Shell & Motion…") { resetConfirmation = true }
                SettingsHardResetView(settings: settings, workspace: previews?.customization)
                Link("Changelog", destination: URL(string: "https://github.com/MakeItEzzz555/DynamicIsland/releases")!)
                SettingsIntroductionReplay { navigation.navigate($0) }
                SettingsNavigationRow(title: "Diagnostics", subtitle: "Agent health, permissions and runtime capabilities", symbol: "stethoscope") {
                    navigation.navigate(.section(.agents))
                }
            }
            Text("Built with SwiftUI and AppKit. Third-party notices are included in the app bundle.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Reset Shell & Motion?", isPresented: $resetConfirmation) {
            Button("Reset", role: .destructive) { settings.resetLayoutSettings() }
        } message: {
            Text("Restores shell sizes and motion preferences. Saved widgets, clipboard history and sessions are preserved.")
        }
    }
}

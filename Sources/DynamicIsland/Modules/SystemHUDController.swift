import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import IOKit
import IOKit.graphics

enum SystemHUDKind: Equatable, Sendable {
    case volume
    case brightness
}

struct SystemHUDSnapshot: Equatable, Sendable {
    let kind: SystemHUDKind
    let value: Double
    let isMuted: Bool
    let updatedAt: Date

    var title: String {
        switch kind {
        case .volume: isMuted || value <= 0.0001 ? "Muted" : "Volume"
        case .brightness: "Brightness"
        }
    }

    var symbolName: String {
        switch kind {
        case .volume:
            if isMuted || value <= 0.0001 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return "sun.max.fill"
        }
    }
}
@MainActor
final class SystemHUDController {
    private weak var settings: AppSettings?
    private let liveActivities: LiveActivityStore
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var dismissTask: Task<Void, Never>?

    init(settings: AppSettings, liveActivities: LiveActivityStore) {
        self.settings = settings
        self.liveActivities = liveActivities
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        dismissTask?.cancel()
        dismissTask = nil
        liveActivities.remove(id: LiveActivityStore.systemHUDActivityID)
    }
    private func handle(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let data = event.data1
        let keyCode = Int((data & 0xFFFF0000) >> 16)
        let keyState = Int((data & 0x0000FF00) >> 8)
        guard keyState == 0x0A else { return }

        switch keyCode {
        case 0, 1, 7:
            guard settings?.systemHUDsEnabled == true,
                  settings?.volumeHUDEnabled == true,
                  let snapshot = Self.readSystemVolume() else { return }
            present(snapshot)
        case 2, 3:
            guard settings?.systemHUDsEnabled == true,
                  settings?.brightnessHUDEnabled == true,
                  let value = Self.readDisplayBrightness() else { return }
            present(SystemHUDSnapshot(
                kind: .brightness,
                value: value,
                isMuted: false,
                updatedAt: Date()
            ))
        default:
            break
        }
    }

    private func present(_ snapshot: SystemHUDSnapshot) {
        let value = min(max(snapshot.value, 0), 1)
        liveActivities.update(
            DynamicIslandLiveActivity(
                id: LiveActivityStore.systemHUDActivityID,
                kind: .system,
                title: snapshot.title,
                subtitle: "\(Int((value * 100).rounded()))%",
                symbolName: snapshot.symbolName,
                priority: 200,
                isActive: true,
                progress: value,
                updatedAt: snapshot.updatedAt
            )
        )
        scheduleDismiss()
    }
    private func scheduleDismiss() {
        dismissTask?.cancel()
        let duration = max(0.5, min(settings?.systemHUDDurationSeconds ?? 1.4, 5))
        dismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.liveActivities.remove(id: LiveActivityStore.systemHUDActivityID)
        }
    }

    nonisolated static func readSystemVolume() -> SystemHUDSnapshot? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return nil }

        let volume = readVolumeScalar(deviceID: deviceID)
        guard let volume else { return nil }
        let muted = readMute(deviceID: deviceID) ?? false
        return SystemHUDSnapshot(
            kind: .volume,
            value: Double(volume),
            isMuted: muted,
            updatedAt: Date()
        )
    }
    private nonisolated static func readVolumeScalar(deviceID: AudioObjectID) -> Float32? {
        for element in [kAudioObjectPropertyElementMain, 1, 2] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: UInt32(element)
            )
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var value = Float32.zero
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr {
                return min(max(value, 0), 1)
            }
        }
        return nil
    }

    private nonisolated static func readMute(deviceID: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value = UInt32.zero
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }
    nonisolated static func readDisplayBrightness() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var brightness: Float = 0
            let result = IODisplayGetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                &brightness
            )
            if result == KERN_SUCCESS, brightness.isFinite {
                return Double(min(max(brightness, 0), 1))
            }
        }
        return nil
    }
}

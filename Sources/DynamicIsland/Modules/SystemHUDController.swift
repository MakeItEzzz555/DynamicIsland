import AppKit
import ApplicationServices
import AudioToolbox
import Combine
import CoreAudio
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics
import Intents

enum SystemHUDKind: String, Equatable, Sendable, CaseIterable {
    case volume
    case brightness
    case capsLock
    case battery
    case audioDevice
    case focus
}

struct SystemHUDAccentComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    static func resolve(kind: SystemHUDKind, value: Double, isMuted: Bool = false) -> Self {
        let t = min(max(value, 0), 1)
        switch kind {
        case .volume:
            if isMuted {
                return Self(red: 0.46, green: 0.62, blue: 0.74, opacity: 0.58)
            }
            // Stable light-blue hue; value controls luminance/saturation and glow energy.
            return Self(
                red: 0.38 - (0.08 * t),
                green: 0.70 + (0.14 * t),
                blue: 0.96 + (0.04 * t),
                opacity: 0.55 + (0.45 * t)
            )
        case .brightness:
            // Warm, readable light-yellow without turning orange at low values.
            return Self(
                red: 1.0,
                green: 0.78 + (0.14 * t),
                blue: 0.30 + (0.08 * t),
                opacity: 0.54 + (0.46 * t)
            )
        case .capsLock, .battery, .audioDevice, .focus:
            return Self(red: 1, green: 1, blue: 1, opacity: 0.82)
        }
    }

    var glowStrength: Double { min(max(opacity * 0.92, 0), 1) }
}

enum SystemHUDFormatting {
    static func percentage(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}

struct SystemHUDDescriptor: Equatable, Sendable {
    let kind: SystemHUDKind
    let title: String
    let subtitle: String
    let symbolName: String
    let progress: Double?
    let priority: Int
    let updatedAt: Date
    let preferredDuration: TimeInterval
    let coalescingKey: String

    init(
        kind: SystemHUDKind,
        title: String,
        subtitle: String,
        symbolName: String,
        progress: Double? = nil,
        priority: Int,
        updatedAt: Date = Date(),
        preferredDuration: TimeInterval = 1.4,
        coalescingKey: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.progress = progress.map { min(max($0, 0), 1) }
        self.priority = priority
        self.updatedAt = updatedAt
        self.preferredDuration = preferredDuration
        self.coalescingKey = coalescingKey ?? kind.rawValue
    }
}

struct SystemHUDArbiter: Equatable, Sendable {
    private(set) var current: SystemHUDDescriptor?
    private(set) var generation = 0

    @discardableResult
    mutating func present(_ descriptor: SystemHUDDescriptor) -> Int? {
        if let current,
           current.coalescingKey != descriptor.coalescingKey,
           current.priority > descriptor.priority {
            return nil
        }

        generation &+= 1
        current = descriptor
        return generation
    }

    @discardableResult
    mutating func dismiss(generation expected: Int) -> Bool {
        guard generation == expected, current != nil else { return false }
        generation &+= 1
        current = nil
        return true
    }

    mutating func clear() {
        generation &+= 1
        current = nil
    }
}

struct CapsLockHUDStateTracker: Equatable, Sendable {
    private(set) var lastState: Bool?

    mutating func transition(to enabled: Bool, at date: Date = Date()) -> SystemHUDDescriptor? {
        guard lastState != enabled else { return nil }
        lastState = enabled
        return SystemHUDDescriptor(
            kind: .capsLock,
            title: enabled ? "Caps Lock On" : "Caps Lock Off",
            subtitle: enabled ? "ABC" : "abc",
            symbolName: enabled ? "capslock.fill" : "capslock",
            priority: 130,
            updatedAt: date,
            preferredDuration: 1.1
        )
    }
}

struct FocusHUDStateTracker: Equatable, Sendable {
    private(set) var lastState: Bool?

    mutating func transition(to isFocused: Bool, at date: Date = Date()) -> SystemHUDDescriptor? {
        guard lastState != isFocused else { return nil }
        lastState = isFocused
        return SystemHUDDescriptor(
            kind: .focus,
            title: "Focus",
            subtitle: isFocused ? "On" : "Off",
            symbolName: isFocused ? "moon.fill" : "moon",
            priority: 140,
            updatedAt: date,
            preferredDuration: 1.5
        )
    }
}

enum BatteryHUDBand: Equatable, Sendable {
    case normal
    case low
    case critical
}

struct BatteryHUDStateTracker: Equatable, Sendable {
    private(set) var previous: BatteryActivitySnapshot?
    private(set) var band: BatteryHUDBand = .normal

    mutating func transition(
        to snapshot: BatteryActivitySnapshot,
        statusEnabled: Bool,
        lowBatteryEnabled: Bool,
        at date: Date = Date()
    ) -> SystemHUDDescriptor? {
        let previous = self.previous
        self.previous = snapshot

        let percentage = snapshot.percentage ?? 0
        let nextBand: BatteryHUDBand
        if !snapshot.isPluggedIn && percentage <= 10 {
            nextBand = .critical
        } else if !snapshot.isPluggedIn && percentage <= 20 {
            nextBand = .low
        } else {
            nextBand = .normal
        }

        defer { band = nextBand }

        if lowBatteryEnabled, nextBand != band {
            switch nextBand {
            case .critical:
                return SystemHUDDescriptor(
                    kind: .battery,
                    title: "Critical Battery",
                    subtitle: "\(percentage)%",
                    symbolName: "exclamationmark.triangle.fill",
                    progress: Double(percentage) / 100,
                    priority: 190,
                    updatedAt: date,
                    preferredDuration: 2.5,
                    coalescingKey: "battery-critical"
                )
            case .low:
                return SystemHUDDescriptor(
                    kind: .battery,
                    title: "Low Battery",
                    subtitle: "\(percentage)%",
                    symbolName: "battery.25percent",
                    progress: Double(percentage) / 100,
                    priority: 180,
                    updatedAt: date,
                    preferredDuration: 2.2,
                    coalescingKey: "battery-low"
                )
            case .normal:
                break
            }
        }

        guard statusEnabled, let previous else { return nil }

        if previous.isPluggedIn != snapshot.isPluggedIn {
            if snapshot.isPluggedIn {
                return SystemHUDDescriptor(
                    kind: .battery,
                    title: snapshot.isCharged ? "Battery Full" : "Charging",
                    subtitle: "\(percentage)%",
                    symbolName: snapshot.isCharged ? "battery.100percent" : "battery.100percent.bolt",
                    progress: Double(percentage) / 100,
                    priority: 155,
                    updatedAt: date,
                    preferredDuration: 1.8,
                    coalescingKey: "battery-power-source"
                )
            } else {
                return SystemHUDDescriptor(
                    kind: .battery,
                    title: "On Battery",
                    subtitle: "\(percentage)%",
                    symbolName: "battery.75percent",
                    progress: Double(percentage) / 100,
                    priority: 155,
                    updatedAt: date,
                    preferredDuration: 1.8,
                    coalescingKey: "battery-power-source"
                )
            }
        }

        if !previous.isCharged, snapshot.isCharged {
            return SystemHUDDescriptor(
                kind: .battery,
                title: "Battery Full",
                subtitle: "\(percentage)%",
                symbolName: "battery.100percent",
                progress: Double(percentage) / 100,
                priority: 150,
                updatedAt: date,
                preferredDuration: 1.8,
                coalescingKey: "battery-full"
            )
        }

        return nil
    }
}

enum AudioOutputDeviceKind: Equatable, Sendable {
    case airPods
    case airPodsPro
    case airPodsMax
    case beats
    case headphones
    case earbuds
    case generic

    static func classify(name: String) -> AudioOutputDeviceKind {
        let value = name.lowercased()
        if value.contains("airpods pro") { return .airPodsPro }
        if value.contains("airpods max") { return .airPodsMax }
        if value.contains("airpods") { return .airPods }
        if value.contains("beats") { return .beats }
        if value.contains("earbud") || value.contains("buds") { return .earbuds }
        if value.contains("headphone") || value.contains("headset") || value.contains("wh-") {
            return .headphones
        }
        return .generic
    }

    var symbolName: String {
        switch self {
        case .airPods, .airPodsPro, .earbuds: "airpodspro"
        case .airPodsMax, .beats, .headphones: "headphones"
        case .generic: "speaker.wave.2.fill"
        }
    }
}

struct AudioOutputDeviceSnapshot: Equatable, Sendable {
    let deviceID: AudioObjectID
    let name: String
    let kind: AudioOutputDeviceKind
}

struct AudioOutputHUDStateTracker: Equatable, Sendable {
    private(set) var previousDeviceID: AudioObjectID?

    mutating func transition(
        to snapshot: AudioOutputDeviceSnapshot,
        at date: Date = Date()
    ) -> SystemHUDDescriptor? {
        defer { previousDeviceID = snapshot.deviceID }
        guard let previousDeviceID else { return nil }
        guard previousDeviceID != snapshot.deviceID else { return nil }

        return SystemHUDDescriptor(
            kind: .audioDevice,
            title: snapshot.name,
            subtitle: "Output Changed",
            symbolName: snapshot.kind.symbolName,
            priority: 165,
            updatedAt: date,
            preferredDuration: 1.8
        )
    }
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
        case .capsLock: "Caps Lock"
        case .battery: "Battery"
        case .audioDevice: "Audio Output"
        case .focus: "Focus"
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
        case .capsLock:
            return "capslock"
        case .battery:
            return "battery.100percent"
        case .audioDevice:
            return "headphones"
        case .focus:
            return "moon.fill"
        }
    }
}

extension SystemHUDSnapshot {
    var descriptor: SystemHUDDescriptor {
        let normalized = min(max(value, 0), 1)
        return SystemHUDDescriptor(
            kind: kind,
            title: title,
            subtitle: "\(Int((normalized * 100).rounded()))%",
            symbolName: symbolName,
            progress: normalized,
            priority: 120,
            updatedAt: updatedAt,
            preferredDuration: 1.4
        )
    }
}

enum SystemHUDAccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func request() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum SystemMediaKey {
    static let volumeUp: UInt32 = 0
    static let volumeDown: UInt32 = 1
    static let brightnessUp: UInt32 = 2
    static let brightnessDown: UInt32 = 3
    static let mute: UInt32 = 7

    static let handled: Set<UInt32> = [
        volumeUp, volumeDown, brightnessUp, brightnessDown, mute
    ]
}
private final class SystemMediaKeyInterceptor: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ((UInt32) -> Bool)?
    private var suppressedKeyCodes: Set<UInt32> = []

    var isRunning: Bool {
        guard let eventTap else { return false }
        return CFMachPortIsValid(eventTap)
    }

    func start(handler: @escaping (UInt32) -> Bool) -> Bool {
        if isRunning {
            self.handler = handler
            return true
        }
        guard AXIsProcessTrusted() else { return false }

        let type = CGEventType(rawValue: 14)!
        let mask = CGEventMask(1) << type.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: systemMediaKeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.handler = handler
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return CFMachPortIsValid(tap)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        handler = nil
        suppressedKeyCodes.removeAll()
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            guard AXIsProcessTrusted(), let eventTap else {
                stop()
                return false
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return false
        }

        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {
            return false
        }

        let data = nsEvent.data1
        let keyCode = UInt32((data & 0xFFFF0000) >> 16)
        guard SystemMediaKey.handled.contains(keyCode) else { return false }

        let flags = UInt32(data & 0x0000FFFF)
        let keyState = (flags & 0xFF00) >> 8
        let isKeyDown = keyState == 0x0A || keyState == 0x08
        let isKeyUp = keyState == 0x0B
        let isRepeat = (flags & 0x1) != 0

        if isKeyUp {
            return suppressedKeyCodes.remove(keyCode) != nil
        }
        guard isKeyDown || isRepeat else { return false }

        let didHandle = handler?(keyCode) ?? false
        if didHandle {
            suppressedKeyCodes.insert(keyCode)
        }
        return didHandle
    }
}

private func systemMediaKeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<SystemMediaKeyInterceptor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    let handled = interceptor.handle(type: type, event: event)
    return handled ? nil : Unmanaged.passUnretained(event)
}
private final class SystemMediaControlBackend {
    private let volumeStep: Float32 = 1.0 / 16.0
    private let brightnessStep: Float = 1.0 / 16.0
    private var previousVolumeBeforeMute: Float32 = 0.25

    private var brightnessBundle: CFBundle?
    private var displayServicesGetBrightness:
        (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?
    private var displayServicesSetBrightness:
        (@convention(c) (CGDirectDisplayID, Float) -> Int32)?
    private var coreDisplayGetBrightness:
        (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?
    private var coreDisplaySetBrightness:
        (@convention(c) (CGDirectDisplayID, Double) -> Int32)?

    init() {
        loadBrightnessFramework()
    }

    func perform(keyCode: UInt32) -> SystemHUDSnapshot? {
        switch keyCode {
        case SystemMediaKey.volumeUp:
            return changeVolume(by: volumeStep)
        case SystemMediaKey.volumeDown:
            return changeVolume(by: -volumeStep)
        case SystemMediaKey.mute:
            return toggleMute()
        case SystemMediaKey.brightnessUp:
            return changeBrightness(by: brightnessStep)
        case SystemMediaKey.brightnessDown:
            return changeBrightness(by: -brightnessStep)
        default:
            return nil
        }
    }

    func currentSnapshot(for keyCode: UInt32) -> SystemHUDSnapshot? {
        switch keyCode {
        case SystemMediaKey.volumeUp, SystemMediaKey.volumeDown, SystemMediaKey.mute:
            return readSystemVolume()
        case SystemMediaKey.brightnessUp, SystemMediaKey.brightnessDown:
            guard let value = readBrightness() else { return nil }
            return SystemHUDSnapshot(
                kind: .brightness,
                value: Double(value),
                isMuted: false,
                updatedAt: Date()
            )
        default:
            return nil
        }
    }

    func setVolume(_ value: Double) -> SystemHUDSnapshot? {
        let target = Float32(min(max(value, 0), 1))
        guard writeVolumeScalar(target), let verified = readVolumeScalar() else { return nil }
        if verified > 0.001 {
            _ = setMute(false)
            previousVolumeBeforeMute = verified
        }
        return SystemHUDSnapshot(
            kind: .volume,
            value: Double(verified),
            isMuted: readMute() ?? (verified <= 0.001),
            updatedAt: Date()
        )
    }

    func setBrightness(_ value: Double) -> SystemHUDSnapshot? {
        let target = Float(min(max(value, 0), 1))
        guard writeBrightness(target), let verified = readBrightness() else { return nil }
        return SystemHUDSnapshot(
            kind: .brightness,
            value: Double(verified),
            isMuted: false,
            updatedAt: Date()
        )
    }

    private func changeVolume(by delta: Float32) -> SystemHUDSnapshot? {
        guard let current = readVolumeScalar() else { return nil }
        let target = min(max(current + delta, 0), 1)
        guard writeVolumeScalar(target) else { return nil }
        if target > 0.001 {
            _ = setMute(false)
            previousVolumeBeforeMute = target
        }
        return readSystemVolume()
    }

    private func toggleMute() -> SystemHUDSnapshot? {
        let current = readVolumeScalar() ?? 0
        let muted = readMute() ?? (current <= 0.001)

        if setMute(!muted) {
            if !muted, current > 0.001 {
                previousVolumeBeforeMute = current
            }
            return readSystemVolume()
        }

        if muted || current <= 0.001 {
            let restore = max(previousVolumeBeforeMute, volumeStep)
            guard writeVolumeScalar(restore) else { return nil }
        } else {
            previousVolumeBeforeMute = current
            guard writeVolumeScalar(0) else { return nil }
        }
        return readSystemVolume()
    }
    func currentOutputDeviceID() -> AudioObjectID? {
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
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    func outputDeviceName(deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    private func readSystemVolume() -> SystemHUDSnapshot? {
        guard let volume = readVolumeScalar() else { return nil }
        return SystemHUDSnapshot(
            kind: .volume,
            value: Double(volume),
            isMuted: readMute() ?? (volume <= 0.001),
            updatedAt: Date()
        )
    }

    private func readVolumeScalar() -> Float32? {
        guard let deviceID = currentOutputDeviceID() else { return nil }

        var virtualAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if let value = readScalar(deviceID: deviceID, address: &virtualAddress) {
            return value
        }

        var mainAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if let value = readScalar(deviceID: deviceID, address: &mainAddress) {
            return value
        }

        let channels = [UInt32(1), UInt32(2)].compactMap { element -> Float32? in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            return readScalar(deviceID: deviceID, address: &address)
        }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Float32(channels.count)
    }

    private func readScalar(
        deviceID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Float32? {
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value = Float32.zero
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &value
        ) == noErr, value.isFinite else {
            return nil
        }
        return min(max(value, 0), 1)
    }

    private func writeVolumeScalar(_ value: Float32) -> Bool {
        guard let deviceID = currentOutputDeviceID() else { return false }
        let target = min(max(value, 0), 1)

        var virtualAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if writeScalar(deviceID: deviceID, address: &virtualAddress, value: target),
           let readBack = readScalar(deviceID: deviceID, address: &virtualAddress),
           abs(readBack - target) < 0.03 {
            return true
        }

        var mainAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if writeScalar(deviceID: deviceID, address: &mainAddress, value: target),
           let readBack = readScalar(deviceID: deviceID, address: &mainAddress),
           abs(readBack - target) < 0.03 {
            return true
        }

        var wroteChannel = false
        for element in [UInt32(1), UInt32(2)] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            wroteChannel = writeScalar(
                deviceID: deviceID,
                address: &address,
                value: target
            ) || wroteChannel
        }
        guard wroteChannel, let readBack = readVolumeScalar() else { return false }
        return abs(readBack - target) < 0.05
    }

    private func writeScalar(
        deviceID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        value: Float32
    ) -> Bool {
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else {
            return false
        }
        var value = value
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, size, &value
        ) == noErr
    }
    private func readMute() -> Bool? {
        guard let deviceID = currentOutputDeviceID() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value = UInt32.zero
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &value
        ) == noErr else {
            return nil
        }
        return value != 0
    }

    private func setMute(_ muted: Bool) -> Bool {
        guard let deviceID = currentOutputDeviceID() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else {
            return false
        }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, size, &value
        ) == noErr
    }

    private func changeBrightness(by delta: Float) -> SystemHUDSnapshot? {
        guard let current = readBrightness() else { return nil }
        let target = min(max(current + delta, 0), 1)
        guard writeBrightness(target),
              let verified = readBrightness() else {
            return nil
        }
        return SystemHUDSnapshot(
            kind: .brightness,
            value: Double(verified),
            isMuted: false,
            updatedAt: Date()
        )
    }

    private func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return nil
        }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func readBrightness() -> Float? {
        guard let displayID = builtInDisplayID() else { return nil }

        var value = Float(0.5)
        if let get = displayServicesGetBrightness,
           get(displayID, &value) == 0,
           value.isFinite {
            return min(max(value, 0), 1)
        }
        if let get = coreDisplayGetBrightness,
           get(displayID, &value) == 0,
           value.isFinite {
            return min(max(value, 0), 1)
        }
        return readIOKitBrightness()
    }

    private func writeBrightness(_ value: Float) -> Bool {
        guard let displayID = builtInDisplayID() else { return false }
        let target = min(max(value, 0), 1)

        if let set = displayServicesSetBrightness,
           set(displayID, target) == 0,
           let readBack = readBrightness(),
           abs(readBack - target) < 0.04 {
            return true
        }
        if let set = coreDisplaySetBrightness,
           set(displayID, Double(target)) == 0,
           let readBack = readBrightness(),
           abs(readBack - target) < 0.04 {
            return true
        }
        return writeIOKitBrightness(target)
    }
    private func readIOKitBrightness() -> Float? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var value = Float.zero
            if IODisplayGetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                &value
            ) == KERN_SUCCESS, value.isFinite {
                return min(max(value, 0), 1)
            }
        }
        return nil
    }

    private func writeIOKitBrightness(_ value: Float) -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            if IODisplaySetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                value
            ) == KERN_SUCCESS {
                _ = IODisplayCommitParameters(service, 0)
                var readBack = Float.zero
                if IODisplayGetFloatParameter(
                    service,
                    0,
                    kIODisplayBrightnessKey as CFString,
                    &readBack
                ) == KERN_SUCCESS, abs(readBack - value) < 0.04 {
                    return true
                }
            }
        }
        return false
    }

    private func loadBrightnessFramework() {
        if loadDisplayServices() { return }
        _ = loadCoreDisplay()
    }

    private func loadDisplayServices() -> Bool {
        loadBrightnessBundle(
            path: "/System/Library/PrivateFrameworks/DisplayServices.framework",
            getName: "DisplayServicesGetBrightness",
            setName: "DisplayServicesSetBrightness",
            useDoubleSetter: false
        )
    }

    private func loadCoreDisplay() -> Bool {
        loadBrightnessBundle(
            path: "/System/Library/Frameworks/CoreDisplay.framework",
            getName: "CoreDisplay_Display_GetUserBrightness",
            setName: "CoreDisplay_Display_SetUserBrightness",
            useDoubleSetter: true
        )
    }

    private func loadBrightnessBundle(
        path: String,
        getName: String,
        setName: String,
        useDoubleSetter: Bool
    ) -> Bool {
        guard let url = CFURLCreateWithFileSystemPath(
            kCFAllocatorDefault,
            path as CFString,
            .cfurlposixPathStyle,
            true
        ),
        let bundle = CFBundleCreate(kCFAllocatorDefault, url),
        CFBundleLoadExecutable(bundle) else {
            return false
        }

        guard let getPointer = CFBundleGetFunctionPointerForName(
            bundle, getName as CFString
        ),
        let setPointer = CFBundleGetFunctionPointerForName(
            bundle, setName as CFString
        ) else {
            return false
        }

        brightnessBundle = bundle
        let get = unsafeBitCast(
            getPointer,
            to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self
        )
        if useDoubleSetter {
            coreDisplayGetBrightness = get
            coreDisplaySetBrightness = unsafeBitCast(
                setPointer,
                to: (@convention(c) (CGDirectDisplayID, Double) -> Int32).self
            )
        } else {
            displayServicesGetBrightness = get
            displayServicesSetBrightness = unsafeBitCast(
                setPointer,
                to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self
            )
        }
        return true
    }
}

private final class DefaultAudioOutputObserver: @unchecked Sendable {
    private var listener: AudioObjectPropertyListenerBlock?
    private var handler: (@Sendable () -> Void)?

    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        stop()
        self.handler = handler
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handler?()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        guard status == noErr else {
            self.handler = nil
            return false
        }
        listener = block
        return true
    }

    func stop() {
        guard let listener else {
            handler = nil
            return
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
        self.listener = nil
        handler = nil
    }
}

private final class PowerSourceChangeObserver: @unchecked Sendable {
    private var runLoopSource: CFRunLoopSource?

    func start(handler: @escaping @Sendable () -> Void) -> Bool {
        stop()
        let box = CallbackBox(handler)
        let context = Unmanaged.passRetained(box).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            box.handler()
        }, context)?.takeRetainedValue() else {
            Unmanaged<CallbackBox>.fromOpaque(context).release()
            return false
        }

        sourceContext = context
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        runLoopSource = nil
        if let sourceContext {
            Unmanaged<CallbackBox>.fromOpaque(sourceContext).release()
            self.sourceContext = nil
        }
    }

    deinit { stop() }

    private var sourceContext: UnsafeMutableRawPointer?

    private final class CallbackBox: @unchecked Sendable {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }
}

private final class FocusStatusObserver: @unchecked Sendable {
    private var observation: NSKeyValueObservation?

    func start(handler: @escaping @Sendable (Bool) -> Void) {
        stop()
        let center = INFocusStatusCenter.default
        observation = center.observe(\.focusStatus, options: [.new]) { _, change in
            guard let isFocused = change.newValue?.isFocused else { return }
            handler(isFocused)
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }

    var authorizationStatus: INFocusStatusAuthorizationStatus {
        INFocusStatusCenter.default.authorizationStatus
    }

    var currentState: Bool? {
        INFocusStatusCenter.default.focusStatus.isFocused
    }

    func requestAuthorization(
        completion: @escaping @Sendable (INFocusStatusAuthorizationStatus) -> Void
    ) {
        INFocusStatusCenter.default.requestAuthorization { status in
            completion(status)
        }
    }
}

@MainActor
final class SystemHUDController {
    private weak var settings: AppSettings?
    private let liveActivities: LiveActivityStore
    private let backend = SystemMediaControlBackend()
    private let batteryProvider = BatteryActivityProvider()
    private let interceptor = SystemMediaKeyInterceptor()
    private let audioOutputObserver = DefaultAudioOutputObserver()
    private let powerSourceObserver = PowerSourceChangeObserver()
    private let focusObserver = FocusStatusObserver()

    private var passiveGlobalMonitor: Any?
    private var passiveLocalMonitor: Any?
    private var capsGlobalMonitor: Any?
    private var capsLocalMonitor: Any?

    private var arbiter = SystemHUDArbiter()
    private var capsTracker = CapsLockHUDStateTracker()
    private var batteryTracker = BatteryHUDStateTracker()
    private var audioTracker = AudioOutputHUDStateTracker()
    private var focusTracker = FocusHUDStateTracker()

    private var dismissTask: Task<Void, Never>?
    private var passiveRefreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, liveActivities: LiveActivityStore) {
        self.settings = settings
        self.liveActivities = liveActivities
    }

    func start() {
        guard cancellables.isEmpty else {
            reconfigure()
            return
        }

        settings?.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.reconfigure() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reconfigure() }
            }
            .store(in: &cancellables)

        reconfigure()
    }

    func stop() {
        stopPassiveMonitoring()
        stopCapsLockMonitoring()
        interceptor.stop()
        audioOutputObserver.stop()
        powerSourceObserver.stop()
        focusObserver.stop()
        dismissTask?.cancel()
        passiveRefreshTask?.cancel()
        dismissTask = nil
        passiveRefreshTask = nil
        cancellables.removeAll()
        arbiter.clear()
        liveActivities.remove(id: LiveActivityStore.systemHUDActivityID)
    }

    func reconfigure() {
        guard let settings, settings.systemHUDsEnabled else {
            stopPassiveMonitoring()
            stopCapsLockMonitoring()
            interceptor.stop()
            audioOutputObserver.stop()
            powerSourceObserver.stop()
            focusObserver.stop()
            arbiter.clear()
            liveActivities.remove(id: LiveActivityStore.systemHUDActivityID)
            return
        }

        let volumeEnabled = settings.volumeHUDEnabled
        let brightnessEnabled = settings.brightnessHUDEnabled
        let backend = self.backend

        if settings.replaceMacOSSystemHUDs,
           AXIsProcessTrusted(),
           interceptor.start(handler: { [weak self] keyCode in
               switch keyCode {
               case SystemMediaKey.volumeUp, SystemMediaKey.volumeDown, SystemMediaKey.mute:
                   guard volumeEnabled else { return false }
               case SystemMediaKey.brightnessUp, SystemMediaKey.brightnessDown:
                   guard brightnessEnabled else { return false }
               default:
                   return false
               }
               guard let snapshot = backend.perform(keyCode: keyCode) else { return false }
               Task { @MainActor [weak self] in
                   self?.present(snapshot.descriptor)
               }
               return true
           }) {
            stopPassiveMonitoring()
        } else {
            interceptor.stop()
            startPassiveMonitoring()
        }

        settings.capsLockHUDEnabled ? startCapsLockMonitoring() : stopCapsLockMonitoring()

        if settings.audioDeviceHUDEnabled {
            _ = audioOutputObserver.start { [weak self] in
                Task { @MainActor in self?.handleAudioOutputChange() }
            }
            seedAudioOutputIdentity()
        } else {
            audioOutputObserver.stop()
            audioTracker = AudioOutputHUDStateTracker()
        }

        if settings.batteryStatusHUDEnabled || settings.lowBatteryHUDEnabled {
            _ = powerSourceObserver.start { [weak self] in
                Task { @MainActor in self?.handleBatteryChange() }
            }
            seedBatteryState()
        } else {
            powerSourceObserver.stop()
            batteryTracker = BatteryHUDStateTracker()
        }

        configureFocusObservation(enabled: settings.focusHUDEnabled)
    }

    private func startPassiveMonitoring() {
        guard passiveGlobalMonitor == nil, passiveLocalMonitor == nil else { return }
        passiveGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            Task { @MainActor in self?.handlePassive(event) }
        }
        passiveLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            Task { @MainActor in self?.handlePassive(event) }
            return event
        }
    }

    private func stopPassiveMonitoring() {
        if let passiveGlobalMonitor { NSEvent.removeMonitor(passiveGlobalMonitor) }
        if let passiveLocalMonitor { NSEvent.removeMonitor(passiveLocalMonitor) }
        passiveGlobalMonitor = nil
        passiveLocalMonitor = nil
    }

    private func startCapsLockMonitoring() {
        guard capsGlobalMonitor == nil, capsLocalMonitor == nil else { return }
        capsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            Task { @MainActor in self?.handleCapsLock(event) }
        }
        capsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            Task { @MainActor in self?.handleCapsLock(event) }
            return event
        }
        _ = capsTracker.transition(to: NSEvent.modifierFlags.contains(.capsLock))
    }

    private func stopCapsLockMonitoring() {
        if let capsGlobalMonitor { NSEvent.removeMonitor(capsGlobalMonitor) }
        if let capsLocalMonitor { NSEvent.removeMonitor(capsLocalMonitor) }
        capsGlobalMonitor = nil
        capsLocalMonitor = nil
        capsTracker = CapsLockHUDStateTracker()
    }

    private func handleCapsLock(_ event: NSEvent) {
        guard settings?.capsLockHUDEnabled == true else { return }
        let enabled = event.modifierFlags.contains(.capsLock)
        guard let descriptor = capsTracker.transition(to: enabled) else { return }
        present(descriptor)
    }

    private func handlePassive(_ event: NSEvent) {
        guard event.subtype.rawValue == 8,
              let settings,
              settings.systemHUDsEnabled else { return }

        let data = event.data1
        let keyCode = UInt32((data & 0xFFFF0000) >> 16)
        let keyState = UInt32((data & 0x0000FF00) >> 8)
        guard keyState == 0x0A || keyState == 0x08 else { return }

        switch keyCode {
        case SystemMediaKey.volumeUp, SystemMediaKey.volumeDown, SystemMediaKey.mute:
            guard settings.volumeHUDEnabled else { return }
        case SystemMediaKey.brightnessUp, SystemMediaKey.brightnessDown:
            guard settings.brightnessHUDEnabled else { return }
        default:
            return
        }

        passiveRefreshTask?.cancel()
        passiveRefreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(45)) } catch { return }
            guard !Task.isCancelled,
                  let self,
                  let snapshot = backend.currentSnapshot(for: keyCode) else { return }
            present(snapshot.descriptor)
        }
    }

    private func seedBatteryState() {
        guard let snapshot = batteryProvider.snapshot() else { return }
        _ = batteryTracker.transition(
            to: snapshot,
            statusEnabled: false,
            lowBatteryEnabled: false
        )
    }

    private func handleBatteryChange() {
        guard let settings,
              let snapshot = batteryProvider.snapshot(),
              let descriptor = batteryTracker.transition(
                to: snapshot,
                statusEnabled: settings.batteryStatusHUDEnabled,
                lowBatteryEnabled: settings.lowBatteryHUDEnabled
              ) else { return }
        present(descriptor)
    }

    private func seedAudioOutputIdentity() {
        guard let snapshot = currentAudioOutputSnapshot() else { return }
        _ = audioTracker.transition(to: snapshot)
    }

    private func handleAudioOutputChange() {
        guard settings?.audioDeviceHUDEnabled == true,
              let snapshot = currentAudioOutputSnapshot(),
              let descriptor = audioTracker.transition(to: snapshot) else { return }
        present(descriptor)
    }

    private func currentAudioOutputSnapshot() -> AudioOutputDeviceSnapshot? {
        guard let deviceID = backend.currentOutputDeviceID(),
              let name = backend.outputDeviceName(deviceID: deviceID) else { return nil }
        return AudioOutputDeviceSnapshot(
            deviceID: deviceID,
            name: name,
            kind: AudioOutputDeviceKind.classify(name: name)
        )
    }

    private func configureFocusObservation(enabled: Bool) {
        guard enabled else {
            focusObserver.stop()
            focusTracker = FocusHUDStateTracker()
            return
        }

        switch focusObserver.authorizationStatus {
        case .authorized:
            startFocusObservation()
        case .notDetermined:
            focusObserver.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    if status == .authorized {
                        self.startFocusObservation()
                    } else {
                        self.focusObserver.stop()
                    }
                }
            }
        case .denied, .restricted:
            focusObserver.stop()
        @unknown default:
            focusObserver.stop()
        }
    }

    private func startFocusObservation() {
        focusTracker = FocusHUDStateTracker()
        if let currentState = focusObserver.currentState {
            _ = focusTracker.transition(to: currentState)
        }
        focusObserver.start { [weak self] isFocused in
            Task { @MainActor in
                guard let self,
                      self.settings?.focusHUDEnabled == true,
                      let descriptor = self.focusTracker.transition(to: isFocused) else {
                    return
                }
                self.present(descriptor)
            }
        }
    }

    /// Interactive HUD slider authority. A successful return always reflects
    /// system readback after the write; failures never publish optimistic state.
    @discardableResult
    func setInteractiveValue(kind: SystemHUDKind, value: Double) -> SystemHUDSnapshot? {
        guard let settings, settings.systemHUDsEnabled else { return nil }
        let snapshot: SystemHUDSnapshot?
        switch kind {
        case .volume:
            guard settings.volumeHUDEnabled else { return nil }
            snapshot = backend.setVolume(value)
        case .brightness:
            guard settings.brightnessHUDEnabled else { return nil }
            snapshot = backend.setBrightness(value)
        case .capsLock, .battery, .audioDevice, .focus:
            return nil
        }
        guard let snapshot else { return nil }
        present(snapshot.descriptor)
        return snapshot
    }

    func currentInteractiveSnapshot(kind: SystemHUDKind) -> SystemHUDSnapshot? {
        switch kind {
        case .volume:
            backend.currentSnapshot(for: SystemMediaKey.volumeUp)
        case .brightness:
            backend.currentSnapshot(for: SystemMediaKey.brightnessUp)
        case .capsLock, .battery, .audioDevice, .focus:
            nil
        }
    }

    private func present(_ descriptor: SystemHUDDescriptor) {
        guard let generation = arbiter.present(descriptor) else { return }
        let current = arbiter.current ?? descriptor
        liveActivities.update(
            DynamicIslandLiveActivity(
                id: LiveActivityStore.systemHUDActivityID,
                kind: .system,
                title: current.title,
                subtitle: current.subtitle,
                symbolName: current.symbolName,
                priority: 200,
                isActive: true,
                progress: current.progress,
                updatedAt: current.updatedAt,
                systemHUDKind: current.kind
            )
        )
        scheduleDismiss(generation: generation, descriptor: current)
    }

    private func scheduleDismiss(generation: Int, descriptor: SystemHUDDescriptor) {
        dismissTask?.cancel()
        let configured = settings?.systemHUDDurationSeconds ?? descriptor.preferredDuration
        let requestedDuration: TimeInterval
        switch descriptor.kind {
        case .battery:
            requestedDuration = max(configured, descriptor.preferredDuration)
        default:
            requestedDuration = configured
        }
        let duration = max(0.5, min(requestedDuration, 5))
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            guard arbiter.dismiss(generation: generation) else { return }
            liveActivities.remove(id: LiveActivityStore.systemHUDActivityID)
        }
    }

    nonisolated static func readSystemVolume() -> SystemHUDSnapshot? {
        SystemMediaControlBackend().currentSnapshot(for: SystemMediaKey.volumeUp)
    }

    nonisolated static func readDisplayBrightness() -> Double? {
        SystemMediaControlBackend().currentSnapshot(for: SystemMediaKey.brightnessUp)?.value
    }
}

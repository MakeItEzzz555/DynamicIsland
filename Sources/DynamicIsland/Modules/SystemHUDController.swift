import AppKit
import ApplicationServices
import AudioToolbox
import Combine
import CoreAudio
import CoreGraphics
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
    private func defaultOutputDevice() -> AudioObjectID? {
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
        guard let deviceID = defaultOutputDevice() else { return nil }

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
        guard let deviceID = defaultOutputDevice() else { return false }
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
        guard let deviceID = defaultOutputDevice() else { return nil }
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
        guard let deviceID = defaultOutputDevice() else { return false }
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
@MainActor
final class SystemHUDController {
    private weak var settings: AppSettings?
    private let liveActivities: LiveActivityStore
    private let backend = SystemMediaControlBackend()
    private let interceptor = SystemMediaKeyInterceptor()
    private var globalMonitor: Any?
    private var localMonitor: Any?
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
                DispatchQueue.main.async {
                    self?.reconfigure()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.reconfigure()
                }
            }
            .store(in: &cancellables)

        reconfigure()
    }

    func stop() {
        stopPassiveMonitoring()
        interceptor.stop()
        dismissTask?.cancel()
        passiveRefreshTask?.cancel()
        dismissTask = nil
        passiveRefreshTask = nil
        cancellables.removeAll()
        liveActivities.remove(id: LiveActivityStore.systemHUDActivityID)
    }

    func reconfigure() {
        guard let settings, settings.systemHUDsEnabled else {
            stopPassiveMonitoring()
            interceptor.stop()
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

               guard let snapshot = backend.perform(keyCode: keyCode) else {
                   // Fail open: unsupported or failed mutations stay owned by macOS.
                   return false
               }

               Task { @MainActor [weak self] in
                   self?.present(snapshot)
               }
               return true
           }) {
            stopPassiveMonitoring()
        } else {
            interceptor.stop()
            startPassiveMonitoring()
        }
    }

    private func startPassiveMonitoring() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            Task { @MainActor in self?.handlePassive(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            Task { @MainActor in self?.handlePassive(event) }
            return event
        }
    }

    private func stopPassiveMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handlePassive(_ event: NSEvent) {
        guard event.subtype.rawValue == 8,
              let settings,
              settings.systemHUDsEnabled else {
            return
        }

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
            do {
                try await Task.sleep(for: .milliseconds(45))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  let snapshot = backend.currentSnapshot(for: keyCode) else {
                return
            }
            present(snapshot)
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
        SystemMediaControlBackend().currentSnapshot(for: SystemMediaKey.volumeUp)
    }

    nonisolated static func readDisplayBrightness() -> Double? {
        SystemMediaControlBackend()
            .currentSnapshot(for: SystemMediaKey.brightnessUp)?
            .value
    }
}

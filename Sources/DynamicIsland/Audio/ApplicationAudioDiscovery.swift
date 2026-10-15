import AppKit
import Combine
import CoreAudio

struct ApplicationAudioProcess: Sendable, Equatable {
    let objectID: UInt32
    let pid: Int32
    let bundleIdentifier: String?
    let outputIORunning: Bool
}

enum ApplicationAudioDiscoveryError: Error { case readFailed(OSStatus), oversizedList }

/// HAL process discovery plus per-app gain. While `isGainEnabled` is false
/// (the default) it is read-only and advertises no gain authority. When the
/// user enables Per-App Volume, a slider below 100% routes that app through
/// `ApplicationGainEngine`; 100% releases it to its own direct output.
@MainActor
final class ApplicationAudioDiscovery: ObservableObject, ApplicationVolumeProviding {
    @Published private(set) var outputs: [ApplicationAudioOutput] = []
    /// The last routing problem, phrased for the user; nil when routing is fine.
    @Published private(set) var routingIssue: String?
    var outputsPublisher: AnyPublisher<[ApplicationAudioOutput], Never> { $outputs.eraseToAnyPublisher() }
    private(set) var isGainEnabled = false
    private var generation: UInt64 = 0
    private var processes: [ApplicationAudioProcess] = []
    private let engine: ApplicationGainEngine
    private let defaults: UserDefaults
    private let readProcesses: @Sendable () throws -> [ApplicationAudioProcess]
    /// Apps without a bundle ID get no saved level: they always start at 100%.
    private var unsavedLevels: [UInt32: Double] = [:]
    private var observers: [NSObjectProtocol] = []
    private var halListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var refreshScheduled = false
    /// Latest slider level per process; one in-flight loop applies it, so the
    /// last value wins however many drag requests overlap.
    private var desiredLevels: [UInt32: Double] = [:]
    private var applying: Set<UInt32> = []
    static let levelsKey = "applicationVolumeLevels"

    private final class StallRelay: @unchecked Sendable { weak var owner: ApplicationAudioDiscovery? }

    init(engine: ApplicationGainEngine? = nil, defaults: UserDefaults = .standard,
         readProcesses: @escaping @Sendable () throws -> [ApplicationAudioProcess] = { try ApplicationAudioDiscovery.readHALProcesses() }) {
        self.defaults = defaults
        self.readProcesses = readProcesses
        let relay = StallRelay()
        self.engine = engine ?? ApplicationGainEngine(onStall: { _ in
            Task { @MainActor in relay.owner?.handleStall() }
        })
        relay.owner = self
    }

    /// Slider position 0...1 → linear amplitude. Squaring makes mid-slider about
    /// a quarter of the amplitude (−12 dB), closer to perceived half-loudness.
    nonisolated static func amplitude(forLevel level: Double) -> Double { level * level }

    func refresh() async throws {
        generation &+= 1
        let token = generation
        let read = readProcesses
        do {
            let processes = try await Task.detached(priority: .utility) { try read() }.value
            guard token == generation else { return }
            apply(processes, generation: token)
            await reconcileRouting()
        } catch {
            if token == generation { outputs = [] }
            throw error
        }
    }

    func apply(_ processes: [ApplicationAudioProcess], generation: UInt64) {
        self.generation = generation
        var seen = Set<UInt32>()
        self.processes = processes.filter { $0.pid > 0 && seen.insert($0.objectID).inserted }
        let alive = Set(self.processes.map(\.objectID))
        unsavedLevels = unsavedLevels.filter { alive.contains($0.key) }
        // A row stays while its app plays, or while it is attenuated (a paused
        // app keeps its level, so resuming never blasts at 100%).
        outputs = self.processes.filter { $0.outputIORunning || (isGainEnabled && level(for: $0) < 1) }.map { process in
            let app = NSRunningApplication(processIdentifier: process.pid)
            return ApplicationAudioOutput(identity: .init(pid: process.pid, processObjectIDs: [process.objectID], generation: generation),
                name: app?.localizedName ?? process.bundleIdentifier ?? "Audio process \(process.pid)",
                bundleIdentifier: process.bundleIdentifier ?? app?.bundleIdentifier, applicationURL: app?.bundleURL,
                activity: process.outputIORunning ? .outputIOActive : .idle,
                gain: isGainEnabled ? level(for: process) : nil, controlAvailable: isGainEnabled)
        }
    }

    func requestGain(_ gain: Double, application: ApplicationAudioIdentity) async -> AudioVolumeWriteResult {
        guard gain.isFinite, (0...1).contains(gain) else { return .failed(.invalidValue) }
        guard outputs.contains(where: { $0.identity == application }),
              let process = processes.first(where: { application.processObjectIDs.contains($0.objectID) && $0.pid == application.pid })
        else { return .failed(.staleIdentity) }
        guard isGainEnabled else { return .unsupported }
        let id = process.objectID
        desiredLevels[id] = gain
        guard applying.insert(id).inserted else { return .superseded }
        defer { applying.remove(id); desiredLevels[id] = nil }
        let token = generation
        var applied: Double
        repeat {
            applied = desiredLevels[id] ?? gain
            do {
                try await engine.setGain(Self.amplitude(forLevel: applied), process: id)
            } catch {
                routingIssue = Self.describe(error)
                return .failed(Self.map(error))
            }
        } while desiredLevels[id] != applied && token == generation
        guard token == generation else { return .superseded }
        routingIssue = nil
        store(applied, for: process)
        apply(processes, generation: generation)
        return .verified(volume: applied, muted: applied == 0)
    }

    /// Per-App Volume switch. Off releases every app to its own output.
    func setGainEnabled(_ enabled: Bool) async {
        guard enabled != isGainEnabled else { return }
        isGainEnabled = enabled
        if enabled {
            observeSystemChanges()
            try? await refresh()
        } else {
            stopObserving()
            try? await engine.releaseAll()
            routingIssue = nil
            apply(processes, generation: generation)
        }
    }

    func disableRouting() async {
        generation &+= 1
        stopObserving()
        isGainEnabled = false
        try? await engine.releaseAll()
        processes = []
        outputs = []
    }

    // MARK: Private

    private func level(for process: ApplicationAudioProcess) -> Double {
        if let bundle = process.bundleIdentifier {
            return (defaults.dictionary(forKey: Self.levelsKey)?[bundle] as? Double).map { min(max($0, 0), 1) } ?? 1
        }
        return unsavedLevels[process.objectID] ?? 1
    }

    private func store(_ level: Double, for process: ApplicationAudioProcess) {
        guard let bundle = process.bundleIdentifier else {
            unsavedLevels[process.objectID] = level < 1 ? level : nil
            return
        }
        var levels = defaults.dictionary(forKey: Self.levelsKey) ?? [:]
        levels[bundle] = level < 1 ? level : nil
        defaults.set(levels, forKey: Self.levelsKey)
    }

    /// Re-applies saved levels to live processes (a relaunched app is a new
    /// process object) and releases sessions for processes that exited.
    private func reconcileRouting() async {
        guard isGainEnabled else { return }
        let alive = Set(processes.map(\.objectID))
        for process in await engine.activeProcesses where !alive.contains(process) {
            try? await engine.release(process)
        }
        for process in processes where level(for: process) < 1 {
            do {
                try await engine.setGain(Self.amplitude(forLevel: level(for: process)), process: process.objectID)
            } catch {
                routingIssue = Self.describe(error)
            }
        }
    }

    private func handleStall() {
        routingIssue = "Audio routing stopped responding, so apps were returned to normal output."
        apply(processes, generation: generation)
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            refreshScheduled = false
            try? await refresh()
        }
    }

    private func observeSystemChanges() {
        guard halListeners.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; Task { try? await self.engine.releaseAll() } }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let rerouteOnDeviceChange = selector == kAudioHardwarePropertyDefaultOutputDevice
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if rerouteOnDeviceChange {
                        // Sessions are bound to the old device; rebuild on the new route.
                        Task { try? await self.engine.releaseAll(); self.scheduleRefresh() }
                    } else {
                        self.scheduleRefresh()
                    }
                }
            }
            if AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr {
                halListeners.append((address, block))
            }
        }
    }

    private func stopObserving() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        let system = AudioObjectID(kAudioObjectSystemObject)
        for (saved, block) in halListeners {
            var address = saved
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, block)
        }
        halListeners.removeAll()
    }

    private static func map(_ error: Error) -> NativeAudioError {
        if let error = error as? NativeAudioError { return error }
        return .perApplicationRoutingUnavailable
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case NativeAudioError.permissionDenied:
            "Allow System Audio Recording for DynamicIsland in Privacy & Security to change app volumes."
        case NativeAudioError.unsupportedPlatform:
            "Per-app volume needs macOS 14.2 or later."
        case ApplicationGainError.routeHasInput:
            "Per-app volume is not available on outputs that also have a microphone, such as headsets and AirPods."
        case ApplicationGainError.unsupportedFormat, NativeAudioError.unsupportedFormat:
            "This app's audio format is not supported for per-app volume."
        default:
            "Per-app volume could not change this app. Its audio plays normally."
        }
    }

    nonisolated static func readHALProcesses() throws -> [ApplicationAudioProcess] {
        var address = property(kAudioHardwarePropertyProcessObjectList)
        var bytes: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        let sizing = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &bytes)
        guard sizing == noErr else { throw ApplicationAudioDiscoveryError.readFailed(sizing) }
        guard bytes <= 4096 * MemoryLayout<AudioObjectID>.size,
              bytes % UInt32(MemoryLayout<AudioObjectID>.size) == 0 else { throw ApplicationAudioDiscoveryError.oversizedList }
        guard bytes > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(bytes) / MemoryLayout<AudioObjectID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &bytes, $0.baseAddress!) }
        guard status == noErr else { throw ApplicationAudioDiscoveryError.readFailed(status) }
        let ownPID = UInt32(bitPattern: ProcessInfo.processInfo.processIdentifier)
        return ids.prefix(Int(bytes) / MemoryLayout<AudioObjectID>.size).compactMap { id in
            // Never list (or tap) DynamicIsland itself: that would feed back.
            guard let pid = scalar(id, kAudioProcessPropertyPID), pid != ownPID else { return nil }
            let running = scalar(id, kAudioProcessPropertyIsRunningOutput) ?? 0
            var bundleAddress = property(kAudioProcessPropertyBundleID)
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let result = AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, &bundle)
            let identifier = result == noErr ? bundle?.takeRetainedValue() as String? : nil
            guard scalar(id, kAudioProcessPropertyPID) == pid else { return nil }
            return ApplicationAudioProcess(objectID: id, pid: Int32(bitPattern: pid), bundleIdentifier: identifier,
                                           outputIORunning: running != 0)
        }
    }

    nonisolated private static func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    nonisolated private static func scalar(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = property(selector); var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

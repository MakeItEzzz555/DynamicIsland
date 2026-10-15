import AppKit
import Combine
import CoreAudio
import Darwin

struct ApplicationAudioProcess: Sendable, Equatable {
    let objectID: UInt32
    let pid: Int32
    let bundleIdentifier: String?
    let outputIORunning: Bool
    /// Where the process executable lives; locates the app that owns a helper.
    var executablePath: String? = nil
}

/// All audio processes of one application (or one standalone process), tapped together.
private struct ApplicationAudioGroup {
    let key: String
    let owner: ApplicationAudioOwner?
    let processes: [ApplicationAudioProcess]
    var processIDs: [UInt32] { processes.map(\.objectID) }
    var isRunning: Bool { processes.contains(where: \.outputIORunning) }
    /// Persisted by bundle ID; pid-keyed groups have no stable identity to save.
    var isPersistent: Bool { !key.hasPrefix("pid:") }
    func identity(generation: UInt64) -> ApplicationAudioIdentity {
        ApplicationAudioIdentity(pid: (processes.first(where: \.outputIORunning) ?? processes[0]).pid,
                                 processObjectIDs: processIDs.sorted(), generation: generation)
    }
}

enum ApplicationAudioDiscoveryError: Error { case readFailed(OSStatus), oversizedList }

/// HAL process discovery plus per-app gain. One row per application: helper
/// processes are grouped under the app that owns them, and a slider below 100%
/// routes all of that app's audio processes through `ApplicationGainEngine`;
/// 100% releases it to its own direct output. While `isGainEnabled` is false
/// (the default) it is read-only and advertises no gain authority.
@MainActor
final class ApplicationAudioDiscovery: ObservableObject, ApplicationVolumeProviding {
    @Published private(set) var outputs: [ApplicationAudioOutput] = []
    /// The last routing problem, phrased for the user; nil when routing is fine.
    @Published private(set) var routingIssue: String?
    var outputsPublisher: AnyPublisher<[ApplicationAudioOutput], Never> { $outputs.eraseToAnyPublisher() }
    private(set) var isGainEnabled = false
    private var generation: UInt64 = 0
    /// Slider loops survive discovery refreshes, but never an off/on routing transition.
    private var routingGeneration: UInt64 = 0
    private var processes: [ApplicationAudioProcess] = []
    private var groups: [ApplicationAudioGroup] = []
    private let engine: ApplicationGainEngine
    private let defaults: UserDefaults
    private let readProcesses: @Sendable () throws -> [ApplicationAudioProcess]
    private let resolveOwners: @MainActor ([ApplicationAudioProcess]) -> [UInt32: ApplicationAudioOwner]
    /// Apps without a bundle ID get no saved level: they always start at 100%.
    private var unsavedLevels: [String: Double] = [:]
    private var observers: [NSObjectProtocol] = []
    private var halListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var refreshScheduled = false
    /// Latest slider level per process; one in-flight loop applies it, so the
    /// last value wins however many drag requests overlap.
    private var desiredLevels: [String: Double] = [:]
    private var applying: [String: UInt64] = [:]
    static let levelsKey = "applicationVolumeLevels"

    private final class StallRelay: @unchecked Sendable { weak var owner: ApplicationAudioDiscovery? }

    init(engine: ApplicationGainEngine? = nil, defaults: UserDefaults = .standard,
         readProcesses: @escaping @Sendable () throws -> [ApplicationAudioProcess] = { try ApplicationAudioDiscovery.readHALProcesses() },
         resolveOwners: @escaping @MainActor ([ApplicationAudioProcess]) -> [UInt32: ApplicationAudioOwner] = ApplicationAudioOwnership.liveOwners) {
        self.defaults = defaults
        self.readProcesses = readProcesses
        self.resolveOwners = resolveOwners
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
            if token == generation { outputs = []; groups = [] }
            throw error
        }
    }

    func apply(_ processes: [ApplicationAudioProcess], generation: UInt64) {
        self.generation = generation
        var seen = Set<UInt32>()
        self.processes = processes.filter { $0.pid > 0 && seen.insert($0.objectID).inserted }
        groups = makeGroups(self.processes)
        let alive = Set(groups.map(\.key))
        unsavedLevels = unsavedLevels.filter { alive.contains($0.key) }
        publishOutputs()
    }

    /// Rebuilds the rows from the current groups (no process re-read), so a
    /// slider drag can show its level at once without resolving owners again.
    private func publishOutputs() {
        // A row stays while its app plays, or while it is attenuated (a paused
        // app keeps its level, so resuming never blasts at 100%).
        outputs = groups.filter { $0.isRunning || (isGainEnabled && level(for: $0) < 1) }.map { group in
            let lead = group.processes.first(where: \.outputIORunning) ?? group.processes[0]
            let app = NSRunningApplication(processIdentifier: lead.pid)
            let bundle = group.owner?.bundleIdentifier ?? lead.bundleIdentifier
            return ApplicationAudioOutput(identity: group.identity(generation: generation),
                name: group.owner?.name ?? app?.localizedName ?? bundle ?? "Audio process \(lead.pid)",
                bundleIdentifier: bundle, applicationURL: group.owner?.url ?? app?.bundleURL,
                activity: group.isRunning ? .outputIOActive : .idle,
                gain: isGainEnabled ? level(for: group) : nil, controlAvailable: isGainEnabled)
        }
    }

    func requestGain(_ gain: Double, application: ApplicationAudioIdentity) async -> AudioVolumeWriteResult {
        guard gain.isFinite, (0...1).contains(gain) else { return .failed(.invalidValue) }
        guard outputs.contains(where: { $0.identity == application }),
              let group = groups.first(where: { $0.identity(generation: application.generation) == application })
        else { return .failed(.staleIdentity) }
        guard isGainEnabled else { return .unsupported }
        let key = group.key
        let routingToken = routingGeneration
        desiredLevels[key] = gain
        publishOutputs()
        guard applying[key] == nil else { return .superseded }
        applying[key] = routingToken
        defer {
            if applying[key] == routingToken { applying[key] = nil; desiredLevels[key] = nil }
        }
        let token = generation
        var applied: Double
        repeat {
            guard isGainEnabled, routingToken == routingGeneration else { return .superseded }
            applied = desiredLevels[key] ?? gain
            // Re-read the members each pass: helper processes come and go while a slider is dragged.
            let members = (groups.first { $0.key == key } ?? group).processIDs
            do {
                try await engine.setGain(Self.amplitude(forLevel: applied), application: key, processes: members)
            } catch {
                guard isGainEnabled, routingToken == routingGeneration else { return .superseded }
                routingIssue = Self.describe(error)
                desiredLevels[key] = nil
                publishOutputs() // the row returns to the level that is really playing
                return .failed(Self.map(error))
            }
            guard isGainEnabled, routingToken == routingGeneration else { return .superseded }
        } while desiredLevels[key] != applied
        // The engine already plays this level, so keep it even if a refresh superseded the request.
        store(applied, for: group)
        guard token == generation else { return .superseded }
        routingIssue = nil
        publishOutputs()
        return .verified(volume: applied, muted: applied == 0)
    }

    /// Per-App Volume switch. Off releases every app to its own output.
    func setGainEnabled(_ enabled: Bool) async {
        guard enabled != isGainEnabled else { return }
        routingGeneration &+= 1
        generation &+= 1
        let routingToken = routingGeneration
        desiredLevels.removeAll()
        applying.removeAll()
        isGainEnabled = enabled
        if enabled {
            observeSystemChanges()
            try? await refresh()
        } else {
            stopObserving()
            try? await engine.releaseAll()
            guard routingToken == routingGeneration else { return }
            routingIssue = nil
            apply(processes, generation: generation)
        }
    }

    func disableRouting() async {
        generation &+= 1
        routingGeneration &+= 1
        let routingToken = routingGeneration
        desiredLevels.removeAll()
        applying.removeAll()
        stopObserving()
        isGainEnabled = false
        try? await engine.releaseAll()
        guard routingToken == routingGeneration else { return }
        processes = []
        groups = []
        outputs = []
    }

    // MARK: Private

    private func makeGroups(_ processes: [ApplicationAudioProcess]) -> [ApplicationAudioGroup] {
        let owners = resolveOwners(processes)
        // A standalone process keeps its bundle ID as identity unless several share it
        // (one WebKit GPU service per client app): those stay separate.
        var standalone: [String: Int] = [:]
        for process in processes where owners[process.objectID] == nil { process.bundleIdentifier.map { standalone[$0, default: 0] += 1 } }
        var order: [String] = []
        var members: [String: [ApplicationAudioProcess]] = [:]
        var ownerOf: [String: ApplicationAudioOwner] = [:]
        for process in processes {
            let owner = owners[process.objectID]
            let key = owner?.bundleIdentifier ?? process.bundleIdentifier.flatMap { standalone[$0] == 1 ? $0 : nil } ?? "pid:\(process.pid)"
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(process)
            ownerOf[key] = owner
        }
        return order.map { ApplicationAudioGroup(key: $0, owner: ownerOf[$0], processes: members[$0] ?? []) }
    }

    private func level(for group: ApplicationAudioGroup) -> Double {
        if let desired = desiredLevels[group.key] { return desired }
        if group.isPersistent {
            return (defaults.dictionary(forKey: Self.levelsKey)?[group.key] as? Double).map { min(max($0, 0), 1) } ?? 1
        }
        return unsavedLevels[group.key] ?? 1
    }

    private func store(_ level: Double, for group: ApplicationAudioGroup) {
        guard group.isPersistent else {
            unsavedLevels[group.key] = level < 1 ? level : nil
            return
        }
        var levels = defaults.dictionary(forKey: Self.levelsKey) ?? [:]
        levels[group.key] = level < 1 ? level : nil
        defaults.set(levels, forKey: Self.levelsKey)
    }

    /// Re-applies saved levels to live applications (a relaunched app is a new
    /// process object), follows helper processes that came or went, and
    /// releases sessions for applications that exited.
    private func reconcileRouting() async {
        guard isGainEnabled else { return }
        let routingToken = routingGeneration
        let token = generation
        let live = Set(groups.map(\.key))
        for key in await engine.activeApplications where !live.contains(key) {
            guard isGainEnabled, routingToken == routingGeneration, token == generation else { return }
            try? await engine.release(key)
        }
        for group in groups {
            guard isGainEnabled, routingToken == routingGeneration, token == generation else { return }
            do {
                try await engine.setGain(Self.amplitude(forLevel: level(for: group)), application: group.key, processes: group.processIDs)
            } catch {
                guard isGainEnabled, routingToken == routingGeneration, token == generation else { return }
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
            // Short: a new helper of an attenuated app plays at unity until the
            // refresh re-taps it. The flag above already coalesces bursts.
            try? await Task.sleep(for: .milliseconds(20))
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
                                           outputIORunning: running != 0, executablePath: executablePath(pid: Int32(bitPattern: pid)))
        }
    }

    nonisolated private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
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

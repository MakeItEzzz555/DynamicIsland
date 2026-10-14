import AppKit
import CoreAudio

struct MeetingAudioProcess: Equatable, Sendable {
    let bundleIdentifier: String
    let pid: pid_t
    let inputActive: Bool
}

/// Reads only CoreAudio process metadata. No audio capture, process taps or permission requests.
final class MeetingAudioObservation: @unchecked Sendable {
    static let supportedApplications: Set<String> = ["us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2",
        "com.apple.FaceTime", "com.cisco.webexmeetingsapp", "com.tinyspeck.slackmacgap"]
    private let queue = DispatchQueue(label: "DynamicIsland.MeetingAudioObservation")
    private let receive: @Sendable (Result<[MeetingAudioProcess], MeetingAudioError>) -> Void
    private var listeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var stopped = true
    private var refreshPending = false

    enum MeetingAudioError: Error, Sendable { case unavailable, readFailed(OSStatus), listenerFailed(OSStatus) }

    init(receive: @escaping @Sendable (Result<[MeetingAudioProcess], MeetingAudioError>) -> Void) { self.receive = receive }

    static func isSupported() -> Bool {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        return AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &address)
    }

    deinit {
        for (object, listener) in listeners {
            var address = Self.address(object == AudioObjectID(kAudioObjectSystemObject)
                ? kAudioHardwarePropertyProcessObjectList : kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
        }
    }

    func start() {
        queue.async { [self] in
            guard stopped else { return }
            stopped = false
            refreshOnQueue()
        }
    }

    func refresh() { queue.async { [self] in if !stopped { refreshOnQueue() } } }

    func stop() {
        queue.async { [self] in
            stopped = true
            for object in Array(listeners.keys) { removeListener(object) }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private func addListener(_ object: AudioObjectID) throws {
        guard listeners[object] == nil else { return }
        var address = Self.address(object == AudioObjectID(kAudioObjectSystemObject)
            ? kAudioHardwarePropertyProcessObjectList : kAudioProcessPropertyIsRunningInput)
        let listener: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            // CoreAudio already delivers this block on our serial queue.
            guard let self, !self.stopped, !self.refreshPending else { return }
            self.refreshPending = true
            self.queue.async { [weak self] in
                guard let self else { return }
                self.refreshPending = false
                if !self.stopped { self.refreshOnQueue() }
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, listener)
        guard status == noErr else { throw MeetingAudioError.listenerFailed(status) }
        listeners[object] = listener
    }

    private func removeListener(_ object: AudioObjectID) {
        guard let listener = listeners.removeValue(forKey: object) else { return }
        var address = Self.address(object == AudioObjectID(kAudioObjectSystemObject)
            ? kAudioHardwarePropertyProcessObjectList : kAudioProcessPropertyIsRunningInput)
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
    }

    private func integer(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size), address = Self.address(selector)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, size == MemoryLayout<UInt32>.size else { throw MeetingAudioError.readFailed(status) }
        return value
    }

    private func bundle(_ object: AudioObjectID) throws -> String? {
        var value: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = Self.address(kAudioProcessPropertyBundleID)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr else { throw MeetingAudioError.readFailed(status) }
        return value?.takeRetainedValue() as String?
    }

    private func refreshOnQueue() {
        do {
            guard Self.isSupported() else { throw MeetingAudioError.unavailable }
            try addListener(AudioObjectID(kAudioObjectSystemObject))
            var address = Self.address(kAudioHardwarePropertyProcessObjectList), size: UInt32 = 0
            var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
            guard status == noErr, size % UInt32(MemoryLayout<AudioObjectID>.size) == 0, size <= 65536 else {
                throw MeetingAudioError.readFailed(status)
            }
            var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            if size > 0 {
                status = objects.withUnsafeMutableBytes {
                    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
                }
                guard status == noErr else { throw MeetingAudioError.readFailed(status) }
                objects = Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
            }
            var processes: [MeetingAudioProcess] = [], observed: Set<AudioObjectID> = [AudioObjectID(kAudioObjectSystemObject)]
            for object in objects {
                guard let identifier = try bundle(object), Self.supportedApplications.contains(identifier) else { continue }
                let pid = pid_t(bitPattern: try integer(object, kAudioProcessPropertyPID))
                let input: UInt32 = try integer(object, kAudioProcessPropertyIsRunningInput)
                try addListener(object); observed.insert(object)
                processes.append(.init(bundleIdentifier: identifier, pid: pid, inputActive: input != 0))
            }
            for object in Set(listeners.keys).subtracting(observed) { removeListener(object) }
            receive(.success(processes))
        } catch let error as MeetingAudioError { receive(.failure(error)) }
        catch { receive(.failure(.unavailable)) }
    }
}

@MainActor
final class MeetingPresenceProvider: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var presence = MeetingPresenceReducer().presence
    private var reducer = MeetingPresenceReducer()
    private var observation: MeetingAudioObservation?
    private var validation: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var generation = 0
    private var suspended = false
    private let running: (String, pid_t) -> Bool
    private let now: () -> Date

    init(running: @escaping (String, pid_t) -> Bool = { identifier, pid in
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains { $0.processIdentifier == pid }
    }, now: @escaping () -> Date = Date.init) { self.running = running; self.now = now }

    func setEnabled(_ enabled: Bool) {
        if self.enabled == enabled { return }
        stop()
        self.enabled = enabled
        guard enabled else { return }
        let token = generation
        observation = MeetingAudioObservation { [weak self] result in
            let observedAt = Date()
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.enabled, !self.suspended else { return }
                self.consume(result, observedAt: observedAt)
            }
        }
        observation?.start()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let sleeping = notification.name == NSWorkspace.willSleepNotification
                Task { @MainActor [weak self] in self?.setSuspended(sleeping) }
            })
        }
    }

    func stop() {
        generation += 1; enabled = false; suspended = false
        validation?.cancel(); validation = nil
        observation?.stop(); observation = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; workspaceObservers = []
        reducer.reset(now: now()); publish()
    }

    func checkAgain() { if enabled { observation?.refresh() } }

    private func setSuspended(_ value: Bool) {
        guard enabled else { return }
        suspended = value
        validation?.cancel(); validation = nil
        if value { observation?.stop(); reducer.reset(now: now()); publish() }
        else { observation?.start() }
    }

    /// Testable normalized input, with PID and application identity both required.
    func consume(_ result: Result<[MeetingAudioProcess], MeetingAudioObservation.MeetingAudioError>, observedAt: Date? = nil) {
        let time = now(), observedAt = observedAt ?? now()
        guard observedAt <= time, time.timeIntervalSince(observedAt) <= MeetingPresenceReducer.staleInterval,
              observedAt >= reducer.presence.observedAt else { reducer.expire(now: time); publish(); return }
        validation?.cancel(); validation = nil
        switch result {
        case .success(let processes):
            let candidates = processes.filter { MeetingAudioObservation.supportedApplications.contains($0.bundleIdentifier)
                && $0.inputActive && running($0.bundleIdentifier, $0.pid) }.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
            let selected = candidates.first { $0.bundleIdentifier == reducer.presence.bundleIdentifier } ?? candidates.first
            if let selected {
                reducer.consume(.init(bundleIdentifier: selected.bundleIdentifier, applicationRunning: true,
                    audioInputActive: true, providerConfirmed: false, authoritativeStartedAt: nil, observedAt: observedAt), now: time)
            } else { reducer.reset(now: time) }
        case .failure:
            reducer.unavailable(reason: "Audio process activity is unavailable. No meeting state can be verified.", now: time)
        }
        publish()
        guard enabled, !suspended else { return }
        let token = generation
        // Event listeners provide changes; one bounded validation checks sustained or stale evidence.
        let delay = presence.state == .possibleMeeting ? MeetingPresenceReducer.confirmationDwell : MeetingPresenceReducer.staleInterval / 2
        validation = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.reducer.expire(now: self.now()); self.publish(); self.observation?.refresh()
            // A fresh response cancels this task; an unresponsive reader cannot keep stale presence alive.
            try? await Task.sleep(for: .seconds(MeetingPresenceReducer.staleInterval - delay + 0.05))
            guard !Task.isCancelled, self.generation == token else { return }
            self.reducer.expire(now: self.now()); self.publish()
        }
    }

    private func publish() { if presence != reducer.presence { presence = reducer.presence } }
}

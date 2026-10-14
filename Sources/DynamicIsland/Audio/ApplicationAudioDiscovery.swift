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

/// Read-only HAL discovery. Output IO is not proof of audible samples.
@MainActor
final class ApplicationAudioDiscovery: ApplicationVolumeProviding {
    @Published private(set) var outputs: [ApplicationAudioOutput] = []
    var outputsPublisher: AnyPublisher<[ApplicationAudioOutput], Never> { $outputs.eraseToAnyPublisher() }
    private var generation: UInt64 = 0

    func refresh() async throws {
        generation &+= 1
        let token = generation
        do {
            let processes = try await Task.detached(priority: .utility) { try Self.readProcesses() }.value
            guard token == generation else { return }
            apply(processes, generation: token)
        } catch {
            if token == generation { outputs = [] }
            throw error
        }
    }

    func apply(_ processes: [ApplicationAudioProcess], generation: UInt64) {
        self.generation = generation
        var seen = Set<UInt32>()
        outputs = processes.filter { $0.pid > 0 && $0.outputIORunning && seen.insert($0.objectID).inserted }.map { process in
            let app = NSRunningApplication(processIdentifier: process.pid)
            return ApplicationAudioOutput(identity: .init(pid: process.pid, processObjectIDs: [process.objectID], generation: generation),
                name: app?.localizedName ?? process.bundleIdentifier ?? "Audio process \(process.pid)",
                bundleIdentifier: process.bundleIdentifier ?? app?.bundleIdentifier, applicationURL: app?.bundleURL,
                activity: .outputIOActive, gain: nil, controlAvailable: false)
        }
    }

    func requestGain(_ gain: Double, application: ApplicationAudioIdentity) async -> AudioVolumeWriteResult {
        guard gain.isFinite, (0...1).contains(gain) else { return .failed(.invalidValue) }
        guard outputs.contains(where: { $0.identity == application }) else { return .failed(.staleIdentity) }
        return .unsupported
    }

    func disableRouting() async { generation &+= 1; outputs = [] }

    nonisolated private static func readProcesses() throws -> [ApplicationAudioProcess] {
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
        return ids.prefix(Int(bytes) / MemoryLayout<AudioObjectID>.size).compactMap { id in
            guard let pid = scalar(id, kAudioProcessPropertyPID),
                  let running = scalar(id, kAudioProcessPropertyIsRunningOutput), running != 0 else { return nil }
            var bundleAddress = property(kAudioProcessPropertyBundleID)
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let result = AudioObjectGetPropertyData(id, &bundleAddress, 0, nil, &bundleSize, &bundle)
            let identifier = result == noErr ? bundle?.takeRetainedValue() as String? : nil
            guard scalar(id, kAudioProcessPropertyPID) == pid else { return nil }
            return ApplicationAudioProcess(objectID: id, pid: Int32(bitPattern: pid), bundleIdentifier: identifier, outputIORunning: true)
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

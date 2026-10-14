import Combine
import Foundation

/// Fixed-size value; audio callbacks do not allocate an Array to publish bands.
struct AudioSpectrumFrame: Sendable, Equatable {
    let sequence: UInt64
    let hostTime: UInt64
    let sampleRate: Double
    let bands: SIMD8<Float>
    let rms: Float
    let peak: Float
    let hasSignal: Bool
}

enum NativeAudioOperation: String, Sendable {
    case createTap, readFormat, createAggregate, createIOProc, startDevice, stopDevice
    case destroyIOProc, destroyAggregate, destroyTap
}

enum NativeAudioError: Error, Sendable, Equatable {
    case unsupportedPlatform
    case unsupportedFormat
    case permissionDenied
    case noFrames
    case operationFailed(NativeAudioOperation, Int32)
    case invalidValue
    case staleIdentity
    case perApplicationRoutingUnavailable
}

enum AudioCapturePermission: Sendable, Equatable {
    /// No public TCC preflight is used; this is not a claim about persisted permission.
    case notVerified
    case accessEstablished
    case denied
}

enum AudioCaptureAvailability: Sendable, Equatable {
    case disabled, starting, capturing, suspended
    case failed(NativeAudioError)
}

enum AudioPlaybackEvidence: Sendable, Equatable {
    /// Silence does not establish that a media player is paused.
    case unknown, silent, signalPresent
}

struct AudioSpectrumPresentation: Sendable, Equatable {
    var availability: AudioCaptureAvailability = .disabled
    var permission: AudioCapturePermission = .notVerified
    var playbackEvidence: AudioPlaybackEvidence = .unknown
    var frame: AudioSpectrumFrame?
}

@MainActor
protocol LiveSpectrumProviding: AnyObject {
    var presentation: AudioSpectrumPresentation { get }
    var presentationPublisher: AnyPublisher<AudioSpectrumPresentation, Never> { get }
    /// Explicit permission intent. Instantiation/subscription never starts capture.
    func startFromUserAction()
    func stop()
    func shutdown() async
}

struct AudioOutputIdentity: Sendable, Equatable, Hashable {
    let deviceID: UInt32
    let uid: String
    let generation: UInt64
}

struct AudioOutputCapabilities: Sendable, Equatable {
    let canReadVolume: Bool
    let canSetVolume: Bool
    let canReadMute: Bool
    let canSetMute: Bool
}

struct AudioOutputDevice: Sendable, Equatable, Identifiable {
    var id: AudioOutputIdentity { identity }
    let identity: AudioOutputIdentity
    let name: String
    let transport: AudioOutputTransport
    let capabilities: AudioOutputCapabilities
}

enum AudioOutputTransport: Sendable, Equatable {
    case builtIn, usb, bluetooth, hdmi, airPlay, other
}

struct SystemAudioVolumeObservation: Sendable, Equatable {
    let output: AudioOutputDevice
    let volume: Double?
    let muted: Bool?
    let observedAt: Date
    let source: Source
    enum Source: Sendable { case externalChange, verifiedWrite, initialRead }
}

enum AudioVolumeWriteResult: Sendable, Equatable {
    case verified(volume: Double?, muted: Bool?)
    case superseded
    case unsupported
    case failed(NativeAudioError)
}

@MainActor
protocol SystemVolumeProviding: AnyObject {
    var observation: SystemAudioVolumeObservation? { get }
    var observationPublisher: AnyPublisher<SystemAudioVolumeObservation?, Never> { get }
    func requestVolume(_ value: Double, output: AudioOutputIdentity) async -> AudioVolumeWriteResult
    func requestMute(_ muted: Bool, output: AudioOutputIdentity) async -> AudioVolumeWriteResult
}

struct ApplicationAudioIdentity: Sendable, Hashable {
    let pid: Int32
    let processObjectIDs: [UInt32]
    let generation: UInt64
}

struct ApplicationAudioOutput: Sendable, Equatable, Identifiable {
    var id: ApplicationAudioIdentity { identity }
    let identity: ApplicationAudioIdentity
    let name: String
    let bundleIdentifier: String?
    /// Views resolve their own native icon from this URL, outside audio callbacks.
    let applicationURL: URL?
    let activity: Activity
    let gain: Double?
    let controlAvailable: Bool
    enum Activity: Sendable { case outputActive, idle, unknown }
}

@MainActor
protocol ApplicationVolumeProviding: AnyObject {
    var outputs: [ApplicationAudioOutput] { get }
    var outputsPublisher: AnyPublisher<[ApplicationAudioOutput], Never> { get }
    func requestGain(_ gain: Double, application: ApplicationAudioIdentity) async -> AudioVolumeWriteResult
    func disableRouting() async
}

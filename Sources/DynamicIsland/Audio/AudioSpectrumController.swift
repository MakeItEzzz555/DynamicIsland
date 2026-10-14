import AppKit
import Combine
import Foundation

@MainActor
final class AudioSpectrumController: ObservableObject, LiveSpectrumProviding {
    @Published private(set) var presentation = AudioSpectrumPresentation()
    var presentationPublisher: AnyPublisher<AudioSpectrumPresentation, Never> { $presentation.eraseToAnyPublisher() }
    private let backend: any AudioSpectrumCaptureBackend
    private let now: () -> Double
    private var generation: UInt64 = 0
    private var startTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var mailbox: AudioSpectrumMailbox?
    private var publicationTask: Task<Void, Never>?
    private var lastFrameAt: Double = 0
    private var sequence: UInt64 = 0
    private var subscriptions: Set<AnyCancellable> = []

    init(backend: any AudioSpectrumCaptureBackend = CoreAudioSpectrumBackend(),
         now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, observeSystemEvents: Bool = true) {
        self.backend = backend
        self.now = now
        if observeSystemEvents {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
                center.publisher(for: name).receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        MainActor.assumeIsolated { self?.suspend() }
                    }.store(in: &subscriptions)
            }
        }
    }

    func startFromUserAction() {
        guard presentation.availability != .starting, presentation.availability != .capturing else { return }
        generation &+= 1
        let current = generation
        lastFrameAt = now(); sequence = 0
        presentation = AudioSpectrumPresentation(availability: .starting)
        startTask = Task { [weak self, backend] in
            do {
                let stream = try await backend.start(generation: current)
                guard let self, self.generation == current, !Task.isCancelled else {
                    try? await backend.stop(generation: current)
                    return
                }
                self.mailbox = stream
                self.publicationTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled, self?.generation == current {
                        self?.refreshPresentation()
                        do { try await Task.sleep(for: .nanoseconds(33_333_333)) }
                        catch { return }
                    }
                }
                self.refreshPresentation()
            } catch {
                guard let self, self.generation == current else { return }
                let error = (error as? NativeAudioError) ?? .unsupportedFormat
                self.presentation = AudioSpectrumPresentation(availability: .failed(error),
                    permission: error == .permissionDenied ? .denied : .notVerified)
            }
        }
    }

    func refreshPresentation() {
        guard let mailbox else { return }
        let snapshot = mailbox.snapshot()
        if snapshot.invalidated { suspend(); return }
        if let frame = snapshot.frame, frame.sequence != sequence {
            sequence = frame.sequence
            lastFrameAt = now()
            presentation = AudioSpectrumPresentation(availability: .capturing,
                permission: frame.hasSignal || presentation.permission == .accessEstablished ? .accessEstablished : .notVerified,
                playbackEvidence: frame.hasSignal ? .signalPresent : .silent, frame: frame)
        } else if now() - lastFrameAt >= 2 {
            stop(with: .failed(.noFrames))
        }
    }

    func stop() { stop(with: .disabled) }
    func suspend() {
        guard presentation.availability == .starting || presentation.availability == .capturing else { return }
        stop(with: .suspended)
    }

    private func stop(with availability: AudioCaptureAvailability) {
        let old = generation
        generation &+= 1
        let current = generation
        startTask?.cancel(); startTask = nil
        publicationTask?.cancel(); publicationTask = nil
        mailbox = nil
        presentation = AudioSpectrumPresentation(availability: availability)
        let previous = teardownTask
        teardownTask = Task { [weak self, backend] in
            await previous?.value
            do { try await backend.stop(generation: old) }
            catch {
                guard let self, self.generation == current else { return }
                self.presentation.availability = .failed((error as? NativeAudioError) ?? .unsupportedFormat)
            }
        }
    }

    func shutdown() async {
        let old = generation
        generation &+= 1
        let pendingStart = startTask
        let pendingPublication = publicationTask
        startTask?.cancel(); startTask = nil
        publicationTask?.cancel(); publicationTask = nil
        mailbox = nil
        subscriptions.removeAll()
        presentation = AudioSpectrumPresentation()
        await pendingStart?.value
        await pendingPublication?.value
        await teardownTask?.value
        teardownTask = nil
        do { try await backend.stop(generation: old) }
        catch { presentation.availability = .failed((error as? NativeAudioError) ?? .unsupportedFormat) }
    }

    deinit { publicationTask?.cancel() }
}

import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum ScreenRecordingAreaGeometry {
    static func sourceRect(fromAppKitLocalRect rect: CGRect, displayHeight: CGFloat) -> CGRect {
        let standardized = rect.standardized
        return CGRect(
            x: standardized.minX,
            y: max(displayHeight - standardized.maxY, 0),
            width: standardized.width,
            height: standardized.height
        )
    }
}

enum ScreenRecordingPhase: String, Equatable, Sendable {
    case idle
    case preparing
    case recording
    case paused
    case finalizing
    case saved
    case failed
}

enum ScreenRecordingError: LocalizedError, Equatable {
    case permissionDenied
    /// Access was requested or an entry exists, but this process still
    /// cannot capture (needs relaunch, or a rebuilt ad-hoc app needs a
    /// fresh System Settings entry).
    case permissionNotActive
    case noDisplay
    case noWindow
    case invalidArea
    case captureUnavailable(String)
    case writerSetupFailed(String)
    case noVideoSamples
    case finalizationFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Screen Recording permission is required"
        case .permissionNotActive: "Screen Recording permission isn't active for this copy of DynamicIsland"
        case .noDisplay: "The selected display is no longer available"
        case .noWindow: "The selected window is no longer available"
        case .invalidArea: "Select a larger recording area"
        case .captureUnavailable(let message): "Screen capture is unavailable: \(message)"
        case .writerSetupFailed(let message): "Recorder could not start: \(message)"
        case .noVideoSamples: "No video frames were captured"
        case .finalizationFailed(let message): "Recording could not be finalized: \(message)"
        case .invalidOutput: "The recording file did not contain a valid video track"
        }
    }
}

struct ScreenRecordingStateMachine: Equatable, Sendable {
    private(set) var phase: ScreenRecordingPhase = .idle

    mutating func beginPreparing() -> Bool {
        guard phase == .idle || phase == .saved || phase == .failed else { return false }
        phase = .preparing
        return true
    }

    mutating func didStart() -> Bool {
        guard phase == .preparing else { return false }
        phase = .recording
        return true
    }

    mutating func pause() -> Bool {
        guard phase == .recording else { return false }
        phase = .paused
        return true
    }

    mutating func resume() -> Bool {
        guard phase == .paused else { return false }
        phase = .recording
        return true
    }

    mutating func beginFinalizing() -> Bool {
        guard phase == .recording || phase == .paused else { return false }
        phase = .finalizing
        return true
    }

    mutating func didSave() -> Bool {
        guard phase == .finalizing else { return false }
        phase = .saved
        return true
    }

    mutating func fail() { phase = .failed }
    mutating func reset() { phase = .idle }
}

/// Source timestamp authority for production retiming and deterministic tests.
/// Paused source time is removed from the output timeline.
/// Two timelines: ScreenCaptureKit sample timestamps (host clock) and the
/// recording session timeline (active elapsed time, pauses excluded).
///
/// ScreenCaptureKit only delivers complete frames when the screen changes, so
/// pause, resume and stop are measured at the host-clock time the user acted,
/// never at the last or next changed frame. A static screen therefore keeps
/// accumulating active time with no new frames.
struct ScreenRecordingTimelineClock: Equatable, Sendable {
    private(set) var sourceOrigin: TimeInterval?
    /// Sum of completed pause intervals.
    private(set) var pausedDuration: TimeInterval = 0
    private(set) var isPaused = false
    private var pauseStartedAt: TimeInterval?
    /// Samples captured before this host time belong to a pause that ended.
    private var resumedAt: TimeInterval?
    /// Host time the user pressed Stop; later samples are not recorded.
    private(set) var stoppedAt: TimeInterval?

    /// Host-clock "now", the same clock ScreenCaptureKit stamps samples with.
    static func hostNow() -> TimeInterval {
        CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
    }

    mutating func pause(at now: TimeInterval) {
        guard !isPaused, now.isFinite else { return }
        isPaused = true
        pauseStartedAt = now
    }

    mutating func resume(at now: TimeInterval) {
        guard isPaused, now.isFinite else { return }
        isPaused = false
        if let pauseStartedAt, sourceOrigin != nil {
            pausedDuration += max(now - max(pauseStartedAt, sourceOrigin ?? pauseStartedAt), 0)
        }
        pauseStartedAt = nil
        resumedAt = now
    }

    mutating func stop(at now: TimeInterval) {
        guard stoppedAt == nil, now.isFinite else { return }
        stoppedAt = now
    }

    mutating func adjustedTime(
        sourceTime: TimeInterval,
        establishesOrigin: Bool
    ) -> TimeInterval? {
        guard sourceTime.isFinite else { return nil }
        if let stoppedAt, sourceTime >= stoppedAt { return nil }

        if isPaused {
            // Only samples captured before the pause began (in flight) count.
            guard let pauseStartedAt, sourceTime < pauseStartedAt else { return nil }
        } else if let resumedAt, sourceTime < resumedAt {
            // Captured during the pause, delivered after resume.
            return nil
        }

        if sourceOrigin == nil {
            guard establishesOrigin, !isPaused else { return nil }
            sourceOrigin = sourceTime
        }
        guard let sourceOrigin else { return nil }
        return max(sourceTime - sourceOrigin - pausedDuration, 0)
    }

    /// Active recorded time at `now`; frozen at the pause boundary while paused.
    func activeDuration(at now: TimeInterval) -> TimeInterval {
        guard let sourceOrigin else { return 0 }
        var effectiveNow = isPaused ? (pauseStartedAt ?? now) : now
        if let stoppedAt { effectiveNow = min(effectiveNow, stoppedAt) }
        return max(effectiveNow - sourceOrigin - pausedDuration, 0)
    }

    /// Writer session end for a stop at `now`: the active recording end, never
    /// earlier than the last appended frame. Nil when no video ever arrived.
    func sessionEndTime(at now: TimeInterval, lastVideoEnd: TimeInterval) -> TimeInterval? {
        guard sourceOrigin != nil else { return nil }
        return max(activeDuration(at: now), lastVideoEnd)
    }
}

final class ScreenRecordingStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "DynamicIsland.ScreenRecording", qos: .userInitiated)

    var onFirstVideoFrame: (() -> Void)?
    var onTimeline: ((TimeInterval) -> Void)?
    var onPreview: ((CGImage) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let outputURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let videoAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private var clock = ScreenRecordingTimelineClock()
    private var sessionStarted = false
    private var finished = false
    private var firstFrameReported = false
    /// End of the last appended video frame on the session timeline.
    private var lastVideoEnd: TimeInterval = 0
    /// Publishes the active duration while the screen is static (no frames).
    private var timelineTicker: DispatchSourceTimer?
    private var lastVideoPresentationTime: TimeInterval = -.infinity
    private var lastPreviewTime: TimeInterval = -.infinity

    init(
        outputURL: URL,
        width: Int,
        height: Int,
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool
    ) throws {
        self.outputURL = outputURL
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw ScreenRecordingError.writerSetupFailed(error.localizedDescription)
        }

        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: max(width, 1),
                AVVideoHeightKey: max(height, 1),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: Self.videoBitRate(width: width, height: height),
                    AVVideoMaxKeyFrameIntervalKey: 120,
                    AVVideoExpectedSourceFrameRateKey: 60
                ]
            ]
        )
        videoInput.expectsMediaDataInRealTime = true
        videoAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: max(width, 1),
                kCVPixelBufferHeightKey as String: max(height, 1)
            ]
        )

        if capturesSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 2))
            input.expectsMediaDataInRealTime = true
            systemAudioInput = input
        } else {
            systemAudioInput = nil
        }

        if capturesMicrophone {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 1))
            input.expectsMediaDataInRealTime = true
            microphoneInput = input
        } else {
            microphoneInput = nil
        }

        super.init()

        guard writer.canAdd(videoInput) else {
            throw ScreenRecordingError.writerSetupFailed("H.264 video input is unavailable")
        }
        writer.add(videoInput)

        if let systemAudioInput {
            guard writer.canAdd(systemAudioInput) else {
                throw ScreenRecordingError.writerSetupFailed("System-audio input is unavailable")
            }
            writer.add(systemAudioInput)
        }

        if let microphoneInput {
            guard writer.canAdd(microphoneInput) else {
                throw ScreenRecordingError.writerSetupFailed("Microphone input is unavailable")
            }
            writer.add(microphoneInput)
        }

        guard writer.startWriting() else {
            throw ScreenRecordingError.writerSetupFailed(
                writer.error?.localizedDescription ?? "AVAssetWriter refused to start"
            )
        }
    }

    /// Applies the pause at the host time it was requested and returns the
    /// frozen active duration, so the UI shows the exact pause boundary.
    @discardableResult
    func pause() -> TimeInterval {
        let now = ScreenRecordingTimelineClock.hostNow()
        return queue.sync {
            clock.pause(at: now)
            return clock.activeDuration(at: now)
        }
    }

    func resume() {
        let now = ScreenRecordingTimelineClock.hostNow()
        queue.async { [weak self] in self?.clock.resume(at: now) }
    }

    /// Marks the Stop boundary before SCStream shutdown, so frames captured
    /// during stopCapture's round trip are not recorded.
    func markStopRequested(at now: TimeInterval) {
        queue.async { [weak self] in self?.clock.stop(at: now) }
    }

    private func startTimelineTickerIfNeeded() {
        guard timelineTicker == nil else { return }
        let ticker = DispatchSource.makeTimerSource(queue: queue)
        ticker.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        ticker.setEventHandler { [weak self] in
            guard let self, !self.finished else { return }
            self.onTimeline?(self.clock.activeDuration(at: ScreenRecordingTimelineClock.hostNow()))
        }
        timelineTicker = ticker
        ticker.resume()
    }

    private func stopTimelineTicker() {
        timelineTicker?.cancel()
        timelineTicker = nil
    }

    /// Stops accepting samples and cancels an unfinished writer without deleting
    /// its temporary output. Runtime failures must release ScreenCaptureKit /
    /// AVAssetWriter resources even when there is no valid movie to finalize.
    func cancel() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if !self.finished {
                    self.finished = true
                    self.stopTimelineTicker()
                    self.writer.cancelWriting()
                }
                continuation.resume()
            }
        }
    }

    /// Finalizes the movie. `stoppedAt` is the host-clock time the user
    /// pressed Stop; the session ends at the active recording time then, so
    /// static periods (no new frames) keep their real duration and the last
    /// frame is held by AVAssetWriter until that point.
    func finish(stoppedAt: TimeInterval = ScreenRecordingTimelineClock.hostNow()) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ScreenRecordingError.finalizationFailed("Recorder disappeared"))
                    return
                }
                guard !self.finished else {
                    continuation.resume(returning: self.outputURL)
                    return
                }
                self.finished = true
                self.stopTimelineTicker()
                self.clock.stop(at: stoppedAt)
                guard self.sessionStarted,
                      let sessionEnd = self.clock.sessionEndTime(at: stoppedAt, lastVideoEnd: self.lastVideoEnd),
                      sessionEnd > 0 else {
                    self.writer.cancelWriting()
                    continuation.resume(throwing: ScreenRecordingError.noVideoSamples)
                    return
                }

                self.writer.endSession(atSourceTime: CMTime(seconds: sessionEnd, preferredTimescale: 60_000))
                self.videoInput.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.microphoneInput?.markAsFinished()
                self.writer.finishWriting { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: ScreenRecordingError.finalizationFailed("Recorder disappeared"))
                        return
                    }
                    if self.writer.status == .completed {
                        continuation.resume(returning: self.outputURL)
                    } else {
                        continuation.resume(
                            throwing: ScreenRecordingError.finalizationFailed(
                                self.writer.error?.localizedDescription ?? "AVAssetWriter did not complete"
                            )
                        )
                    }
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFailure?(error)
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard !finished,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        if type == .screen {
            guard let attachmentArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let attachment = attachmentArray.first,
            let rawStatus = attachment[SCStreamFrameInfo.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus),
            status == .complete else {
                return
            }
        }

        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let sourceSeconds = CMTimeGetSeconds(sourcePTS)
        guard sourceSeconds.isFinite else { return }

        guard let adjustedSeconds = clock.adjustedTime(
            sourceTime: sourceSeconds,
            establishesOrigin: type == .screen
        ) else {
            return
        }

        if !sessionStarted {
            guard type == .screen else { return }
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }

        switch type {
        case .screen:
            // AVAssetWriter requires strictly increasing video timestamps. SCK
            // may emit multiple complete samples with an identical source PTS
            // around display refresh/transition boundaries; dropping duplicates
            // is preferable to corrupting the writer timeline.
            guard adjustedSeconds > lastVideoPresentationTime + 0.000_001,
                  videoInput.isReadyForMoreMediaData,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            let presentationTime = CMTime(
                seconds: adjustedSeconds,
                preferredTimescale: max(sourcePTS.timescale, 60_000)
            )
            guard videoAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                onFailure?(writer.error ?? ScreenRecordingError.finalizationFailed("Video append failed"))
                return
            }

            lastVideoPresentationTime = adjustedSeconds
            let sourceDuration = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
            let frameDuration = sourceDuration.isFinite && sourceDuration > 0 ? sourceDuration : (1.0 / 60.0)
            lastVideoEnd = max(lastVideoEnd, adjustedSeconds + frameDuration)

            if !firstFrameReported {
                firstFrameReported = true
                onFirstVideoFrame?()
                onTimeline?(0)
                startTimelineTickerIfNeeded()
            }

            if adjustedSeconds - lastPreviewTime >= 0.20 {
                lastPreviewTime = adjustedSeconds
                emitPreview(sampleBuffer)
            }

        case .audio:
            guard let retimed = Self.retime(
                sampleBuffer,
                sourceSeconds: sourceSeconds,
                adjustedSeconds: adjustedSeconds
            ) else { return }
            if let systemAudioInput, systemAudioInput.isReadyForMoreMediaData {
                if !systemAudioInput.append(retimed) {
                    onFailure?(writer.error ?? ScreenRecordingError.finalizationFailed("System-audio append failed"))
                }
            }

        case .microphone:
            guard let retimed = Self.retime(
                sampleBuffer,
                sourceSeconds: sourceSeconds,
                adjustedSeconds: adjustedSeconds
            ) else { return }
            if #available(macOS 15.0, *),
               let microphoneInput,
               microphoneInput.isReadyForMoreMediaData,
               !microphoneInput.append(retimed) {
                onFailure?(writer.error ?? ScreenRecordingError.finalizationFailed("Microphone append failed"))
            }

        @unknown default:
            break
        }
    }

    private func emitPreview(_ buffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        onPreview?(cgImage)
    }

    private static func retime(
        _ sampleBuffer: CMSampleBuffer,
        sourceSeconds: TimeInterval,
        adjustedSeconds: TimeInterval
    ) -> CMSampleBuffer? {
        let delta = max(sourceSeconds - adjustedSeconds, 0)
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let offset = CMTime(
            seconds: delta,
            preferredTimescale: max(sourcePTS.timescale, 600)
        )

        var needed = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &needed
        ) == noErr, needed > 0 else {
            return nil
        }

        var timing = Array(
            repeating: CMSampleTimingInfo(
                duration: .invalid,
                presentationTimeStamp: .invalid,
                decodeTimeStamp: .invalid
            ),
            count: needed
        )
        var count = needed
        let readStatus = timing.withUnsafeMutableBufferPointer { pointer in
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: needed,
                arrayToFill: pointer.baseAddress,
                entriesNeededOut: &count
            )
        }
        guard readStatus == noErr else { return nil }

        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMTimeSubtract(
                    timing[index].presentationTimeStamp,
                    offset
                )
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeSubtract(
                    timing[index].decodeTimeStamp,
                    offset
                )
            }
        }

        var copy: CMSampleBuffer?
        let copyStatus = timing.withUnsafeMutableBufferPointer { pointer in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: count,
                sampleTimingArray: pointer.baseAddress!,
                sampleBufferOut: &copy
            )
        }
        guard copyStatus == noErr else { return nil }
        return copy
    }

    private static func videoBitRate(width: Int, height: Int) -> Int {
        let pixels = max(width * height, 1)
        return min(max(pixels * 5, 8_000_000), 48_000_000)
    }

    private static func audioSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 1 ? 128_000 : 192_000
        ]
    }
}

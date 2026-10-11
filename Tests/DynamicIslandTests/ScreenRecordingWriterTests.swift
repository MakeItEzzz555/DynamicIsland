import AVFoundation
import ScreenCaptureKit
import XCTest
@testable import DynamicIsland

final class ScreenRecordingWriterTests: XCTestCase {
    func testSingleStaticFrameHasThreeSecondPlayableVideoTrack() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("static-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try ScreenRecordingStreamOutput(outputURL: url, width: 64, height: 48,
            capturesSystemAudio: false, capturesMicrophone: false)
        let origin = ScreenRecordingTimelineClock.hostNow()
        let sample = try sample(at: origin)
        output.queue.sync { output.consume(sample, type: .screen) }
        // No sleeps, permission, source enumeration or extra video frames.
        _ = try await output.finish(stoppedAt: origin + 3)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let range = try await track.load(.timeRange)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(CMTimeGetSeconds(duration), 3, accuracy: 0.05)
        XCTAssertEqual(CMTimeGetSeconds(range.duration), 3, accuracy: 0.05)
        XCTAssertEqual(size, CGSize(width: 64, height: 48))
        let reader = try AVAssetReader(asset: asset)
        let video = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(video)
        XCTAssertTrue(reader.startReading())
        XCTAssertNotNil(video.copyNextSampleBuffer())
        reader.cancelReading()
    }

    func testFailedStartWithoutVideoCancelsWriter() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-video-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let output = try ScreenRecordingStreamOutput(outputURL: url, width: 64, height: 48,
            capturesSystemAudio: false, capturesMicrophone: false)
        do {
            _ = try await output.finish()
            XCTFail("No video must never finalize successfully")
        } catch { XCTAssertEqual(error as? ScreenRecordingError, .noVideoSamples) }
        await output.cancel()
    }

    private func sample(at time: TimeInterval) throws -> CMSampleBuffer {
        var pixel: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 100, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 60_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: buffer, formatDescription: try XCTUnwrap(format), sampleTiming: &timing,
            sampleBufferOut: &sample), noErr)
        let result = try XCTUnwrap(sample)
        let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(result, createIfNecessary: true))
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dictionary, Unmanaged.passUnretained(SCStreamFrameInfo.status.rawValue as CFString).toOpaque(),
            Unmanaged.passUnretained(NSNumber(value: SCFrameStatus.complete.rawValue)).toOpaque())
        return result
    }
}

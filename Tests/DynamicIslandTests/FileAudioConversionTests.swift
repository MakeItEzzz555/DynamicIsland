@preconcurrency import AVFoundation
import CryptoKit
import XCTest
@testable import DynamicIsland

@MainActor
final class FileAudioConversionTests: XCTestCase {
    func testExplicitOutputFolderPublishesValidatedAudioAndFailureLeavesSourceIntact() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("audio-destination-\(UUID().uuidString)")
        let destination = root.appendingPathComponent("chosen", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeAudio(root); let original = try Data(contentsOf: source)
        let output = try await FileAudioConversion.convert(source, to: .wav, outputDirectory: destination)
        XCTAssertEqual(output.deletingLastPathComponent(), destination)
        XCTAssertGreaterThan(try AVAudioFile(forReading: output).length, 0)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let invalid = root.appendingPathComponent("missing")
        do { _ = try await FileAudioConversion.convert(source, to: .wav, outputDirectory: invalid); XCTFail("Missing folder must reject") }
        catch { XCTAssertEqual(try Data(contentsOf: source), original) }
        do { _ = try await FileAudioConversion.convert(source, to: .wav, outputDirectory: source); XCTFail("File is not a folder") }
        catch { XCTAssertEqual(try Data(contentsOf: source), original) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).count, 1)
    }
    func testNativeAudioTargetsProduceDecodedCodecAndDurationWithoutModifyingOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audio-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeAudio(directory)
        let original = try Data(contentsOf: source)
        let hasAudio = await FileAudioConversion.hasAudio(source)
        XCTAssertTrue(hasAudio)
        XCTAssertEqual(FileAudioFormat.allCases.map(\.rawValue), ["M4A", "MP3", "WAV", "FLAC", "AIFF", "ALAC"])
        var verified: [String] = []
        for format in FileAudioFormat.allCases where format.canEncode {
            let converted = try await FileAudioConversion.convert(source, to: format)
            XCTAssertNotEqual(converted, source)
            let file = try AVAudioFile(forReading: converted)
            XCTAssertEqual(file.fileFormat.streamDescription.pointee.mFormatID, format.codec)
            XCTAssertEqual(file.fileFormat.channelCount, 1)
            XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 1, accuracy: 0.15)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024))
            try file.read(into: buffer); XCTAssertGreaterThan(buffer.frameLength, 0)
            XCTAssertEqual(try Data(contentsOf: source), original)
            verified.append(format.rawValue)
        }
        XCTAssertTrue(verified.contains("WAV")); XCTAssertTrue(verified.contains("AIFF"))
        print("Native audio verified: \(verified.joined(separator: ", ")); unavailable: \(FileAudioFormat.allCases.filter { !$0.canEncode }.map(\.rawValue).joined(separator: ", "))")
    }
    func testCorruptNoAudioAndCancelledConversionDoNotLeaveOutputOrChangeInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audio-errors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = directory.appendingPathComponent("corrupt.wav")
        let bytes = Data("not audio".utf8); try bytes.write(to: invalid)
        let invalidHasAudio = await FileAudioConversion.hasAudio(invalid)
        XCTAssertFalse(invalidHasAudio)
        do { _ = try await FileAudioConversion.convert(invalid, to: .wav); XCTFail("Corrupt input accepted") } catch {}
        let source = try makeAudio(directory)
        let task = Task { try await FileAudioConversion.convert(source, to: .wav) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled input accepted") } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error") }
        XCTAssertEqual(try Data(contentsOf: invalid), bytes)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), ["corrupt.wav", "synthetic.wav"])
    }
    func testContextualRequestOnlyContainsAcceptedFilesAndStaleDismissCannotDropNewRequest() throws {
        let settings = AppSettings(defaults: SettingsPreviewDefaults())
        let store = FileShelfStore(settings: settings, defaults: SettingsPreviewDefaults(), ownership: TemporaryFileOwnershipLedger(temporaryRoots: []))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("file-request-\(UUID().uuidString).txt")
        try Data("synthetic".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        store.add([file]); XCTAssertNil(store.fileActionRequest)
        store.requestFileActions(for: [file, URL(fileURLWithPath: "/not-accepted")])
        XCTAssertEqual(store.fileActionRequest?.urls, [file]); let old = store.fileActionRequest?.id
        store.requestFileActions(for: [file]); store.dismissFileActions(old)
        XCTAssertNotNil(store.fileActionRequest)
        store.dismissFileActions(store.fileActionRequest?.id); XCTAssertNil(store.fileActionRequest)
    }
    func testAudioExtractionFromRealVideoPreservesStereoDurationAndOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("audio-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = try makeAudio(directory, channels: 2)
        let silent = directory.appendingPathComponent("silent.mov")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        XCTAssertTrue(writer.canAdd(input)); writer.add(input)
        XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        let deadline = Date().addingTimeInterval(10)
        for frame in 0..<3 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
                guard writer.status == .writing, Date() < deadline else { throw FileAudioConversionError.invalidOutput }
            }
            var pixel: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &pixel), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(32 + frame * 30), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adapter.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 2)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: audio)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 48_000))
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: XCTUnwrap(videoTracks.first), at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: XCTUnwrap(audioTracks.first), at: .zero)
        let source = directory.appendingPathComponent("synthetic-video.mov")
        let export = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        export.outputURL = source; export.outputFileType = .mov
        await export.export()
        XCTAssertEqual(export.status, .completed)
        let original = try Data(contentsOf: source)
        let sourceTracks = try await AVURLAsset(url: source).loadTracks(withMediaType: .video)
        XCTAssertEqual(sourceTracks.count, 1)
        for format in [FileAudioFormat.m4a, .wav, .flac, .aiff, .alac] where format.canEncode {
            let output = try await FileAudioConversion.convert(source, to: format)
            let decoded = try AVAudioFile(forReading: output)
            XCTAssertEqual(decoded.fileFormat.channelCount, 2)
            XCTAssertEqual(decoded.fileFormat.streamDescription.pointee.mFormatID, format.codec)
            XCTAssertEqual(Double(decoded.length) / decoded.fileFormat.sampleRate, 1, accuracy: 0.15)
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
    private func makeAudio(_ directory: URL, channels: AVAudioChannelCount = 1) throws -> URL {
        let source = directory.appendingPathComponent("synthetic.wav")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let samples = buffer.mutableAudioBufferList.pointee.mBuffers.mData!.assumingMemoryBound(to: Float.self)
        for i in 0..<(48_000 * Int(channels)) { samples[i] = Float(sin(Double(i / Int(channels)) * 2 * .pi * 440 / 48_000) * 0.2) }
        var file: AVAudioFile? = try AVAudioFile(forWriting: source, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: channels, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: true)
        try file?.write(from: buffer); file = nil
        return source
    }
}

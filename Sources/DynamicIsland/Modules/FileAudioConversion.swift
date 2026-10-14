@preconcurrency import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

/// Native encoders are queried; a decoder's presence never implies encoding support.
enum FileAudioFormat: String, CaseIterable, Identifiable, Sendable {
    case m4a = "M4A", mp3 = "MP3", wav = "WAV", flac = "FLAC", aiff = "AIFF", alac = "ALAC"
    var id: String { rawValue }
    var codec: AudioFormatID {
        switch self {
        case .m4a: kAudioFormatMPEG4AAC
        case .mp3: kAudioFormatMPEGLayer3
        case .wav, .aiff: kAudioFormatLinearPCM
        case .flac: kAudioFormatFLAC
        case .alac: kAudioFormatAppleLossless
        }
    }
    var extensionName: String { self == .alac ? "m4a" : rawValue.lowercased() }
    var canEncode: Bool {
        if codec == kAudioFormatLinearPCM { return true }
        var type = codec, size: UInt32 = 0
        guard AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, UInt32(MemoryLayout.size(ofValue: type)), &type, &size) == noErr else { return false }
        var descriptions = [AudioClassDescription](repeating: AudioClassDescription(), count: Int(size) / MemoryLayout<AudioClassDescription>.stride)
        return descriptions.withUnsafeMutableBytes { bytes in
            AudioFormatGetProperty(kAudioFormatProperty_Encoders, UInt32(MemoryLayout.size(ofValue: type)), &type, &size, bytes.baseAddress) == noErr && size > 0
        }
    }
}

enum FileAudioConversionError: LocalizedError {
    case unavailable, noAudio, unsupportedChannels, invalidOutput
    var errorDescription: String? {
        switch self {
        case .unavailable: "This Mac does not provide this audio encoder."
        case .noAudio: "The file does not contain a readable audio track."
        case .unsupportedChannels: "This conversion supports mono or stereo audio."
        case .invalidOutput: "The converted audio could not be validated."
        }
    }
}

enum FileAudioConversion {
    static func hasAudio(_ url: URL) async -> Bool {
        guard url.isFileURL else { return false }
        return (try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio).isEmpty) == false
    }
    static func convert(_ source: URL, to format: FileAudioFormat, outputDirectory: URL? = nil) async throws -> URL {
        let worker = Task.detached(priority: .userInitiated) { try await perform(source, format: format, outputDirectory: outputDirectory) }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    private static func perform(_ source: URL, format: FileAudioFormat, outputDirectory: URL?) async throws -> URL {
        guard source.isFileURL, format.canEncode else { throw FileAudioConversionError.unavailable }
        let outputFolder = try FileConversionController.checkedOutputDirectory(outputDirectory, source: source)
        try Task.checkCancellation()
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let description = try await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { throw FileAudioConversionError.noAudio }
        let channels = asbd.mChannelsPerFrame, sampleRate = asbd.mSampleRate
        guard channels > 0, channels <= 2, sampleRate.isFinite, sampleRate > 0 else { throw FileAudioConversionError.unsupportedChannels }
        let job = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DynamicIsland-Audio-\(job)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent("output.\(format.extensionName)")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw FileAudioConversionError.noAudio }
        reader.add(output)
        guard reader.startReading() else { throw FileAudioConversionError.noAudio }
        defer { reader.cancelReading() }
        var encoding: [String: Any] = [AVFormatIDKey: format.codec, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
        if format.codec == kAudioFormatLinearPCM {
            encoding[AVLinearPCMBitDepthKey] = 16
            encoding[AVLinearPCMIsFloatKey] = false
            encoding[AVLinearPCMIsBigEndianKey] = format == .aiff
            encoding[AVLinearPCMIsNonInterleaved] = false
        } else if format == .m4a || format == .mp3 { encoding[AVEncoderBitRateKey] = 192_000 }
        else if format == .alac { encoding[AVEncoderBitDepthHintKey] = 16 }
        var file: AVAudioFile? = try AVAudioFile(forWriting: temporary, settings: encoding, commonFormat: .pcmFormatFloat32, interleaved: true)
        var frames: AVAudioFramePosition = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0, let block = CMSampleBufferGetDataBuffer(sample), let file,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)) else { throw FileAudioConversionError.noAudio }
            buffer.frameLength = AVAudioFrameCount(count)
            let bytes = count * Int(channels) * MemoryLayout<Float>.size
            guard let memory = buffer.mutableAudioBufferList.pointee.mBuffers.mData,
                  CMBlockBufferGetDataLength(block) == bytes,
                  CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: memory) == kCMBlockBufferNoErr else { throw FileAudioConversionError.noAudio }
            try file.write(from: buffer); frames += AVAudioFramePosition(count)
        }
        guard reader.status == .completed, frames > 0 else { throw FileAudioConversionError.noAudio }
        file = nil // Close/finalize the container before decoding it.
        try Task.checkCancellation()
        let check = try AVAudioFile(forReading: temporary)
        guard check.length > 0, check.fileFormat.channelCount == channels,
              check.fileFormat.streamDescription.pointee.mFormatID == format.codec,
              abs(Double(check.length) / check.fileFormat.sampleRate - Double(frames) / sampleRate) < 0.15 else { throw FileAudioConversionError.invalidOutput }
        let name = source.deletingPathExtension().lastPathComponent + " \(format.rawValue) \(job.prefix(8)).\(format.extensionName)"
        let destination = outputFolder.appendingPathComponent(name)
        try Task.checkCancellation()
        // Stage beside the destination so publication is an exclusive same-volume move.
        let staging = outputFolder.appendingPathComponent(".DynamicIsland-Audio-\(job)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let ready = staging.appendingPathComponent("output")
        try FileManager.default.copyItem(at: temporary, to: ready)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: ready, to: destination)
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        }
        return destination
    }
}

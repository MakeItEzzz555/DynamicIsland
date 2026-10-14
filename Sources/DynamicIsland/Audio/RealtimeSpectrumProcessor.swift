import Accelerate
import CoreAudio
import Darwin
import os

/// UI readers copy only values. The audio writer tries once and drops a publish rather than waiting.
final class AudioSpectrumMailbox: @unchecked Sendable {
    struct Snapshot: Sendable {
        var frame: AudioSpectrumFrame?
        var invalidated = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: Snapshot())
    func publish(_ frame: AudioSpectrumFrame) {
        _ = lock.withLockIfAvailable { if !$0.invalidated { $0.frame = frame } }
    }
    func snapshot() -> Snapshot { lock.withLock { $0 } }
    func invalidate() { lock.withLock { $0.invalidated = true; $0.frame = nil } }
}

/// One IOProc writer owns all scratch storage. Allocation and FFT setup occur before AudioDeviceStart.
final class RealtimeSpectrumProcessor: @unchecked Sendable {
    static let size = 2048
    static let hop = 512
    let sampleRate: Double
    let mailbox: AudioSpectrumMailbox
    let bandEdges: [Double]
    private let ranges: [Range<Int>]
    private let fft: FFTSetup
    private let ringL: UnsafeMutablePointer<Float>
    private let ringR: UnsafeMutablePointer<Float>
    private let window: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>
    private let powers: UnsafeMutablePointer<Float>
    private let spectralScale: Float
    private var write = 0
    private var filled = 0
    private var hopSamples = 0
    private var sequence: UInt64 = 0
    private var smoothed = SIMD8<Float>.zero
    private var reference: Float = 0.5

    init(sampleRate: Double, mailbox: AudioSpectrumMailbox = AudioSpectrumMailbox()) throws {
        guard sampleRate.isFinite, sampleRate >= 8_000, sampleRate <= 384_000,
              let fft = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2)) else {
            throw NativeAudioError.unsupportedFormat
        }
        self.sampleRate = sampleRate
        self.mailbox = mailbox
        self.fft = fft
        ringL = .allocate(capacity: Self.size); ringL.initialize(repeating: 0, count: Self.size)
        ringR = .allocate(capacity: Self.size); ringR.initialize(repeating: 0, count: Self.size)
        window = .allocate(capacity: Self.size)
        scratch = .allocate(capacity: Self.size)
        real = .allocate(capacity: Self.size / 2)
        imaginary = .allocate(capacity: Self.size / 2)
        powers = .allocate(capacity: Self.size / 2)
        vDSP_hann_window(window, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
        var sum: Float = 0
        vDSP_sve(window, 1, &sum, vDSP_Length(Self.size))
        spectralScale = 1 / (sum * sum)
        let upper = min(12_000, sampleRate * 0.48)
        let edges = (0...8).map { 40 * pow(upper / 40, Double($0) / 8) }
        bandEdges = edges
        let binHz = sampleRate / Double(Self.size)
        ranges = (0..<8).map {
            let low = min(Self.size / 2, max(1, Int(ceil(edges[$0] / binHz))))
            let high = min(Self.size / 2, max(low, Int(ceil(edges[$0 + 1] / binHz))))
            return low..<high
        }
    }

    deinit {
        vDSP_destroy_fftsetup(fft)
        ringL.deallocate(); ringR.deallocate(); window.deallocate(); scratch.deallocate()
        real.deallocate(); imaginary.deallocate(); powers.deallocate()
    }

    /// Float32 mono/stereo, interleaved or planar. No intermediate audio arrays or queued buffers.
    func consume(_ input: UnsafePointer<AudioBufferList>, hostTime: UInt64) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let bytes = first.mData, first.mNumberChannels > 0 else { return }
        let channels = Int(first.mNumberChannels)
        guard channels <= 2 else { return }
        let left = bytes.assumingMemoryBound(to: Float.self)
        var right = left
        var rightStride = channels
        var rightOffset = channels == 2 ? 1 : 0
        var frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        if channels == 1, buffers.count >= 2 {
            let second = buffers[1]
            guard second.mNumberChannels == 1, let data = second.mData else { return }
            right = data.assumingMemoryBound(to: Float.self)
            rightStride = 1; rightOffset = 0
            frames = min(frames, Int(second.mDataByteSize) / MemoryLayout<Float>.size)
        }
        for i in 0..<frames {
            append(left[i * channels], right[i * rightStride + rightOffset], hostTime: hostTime)
        }
    }

    /// Synthetic tests use the identical sample/DSP path; not a production simulated source.
    func consume(left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>? = nil, hostTime: UInt64 = 0) {
        let count = min(left.count, right?.count ?? left.count)
        for i in 0..<count { append(left[i], right?[i] ?? left[i], hostTime: hostTime) }
    }

    private func append(_ left: Float, _ right: Float, hostTime: UInt64) {
        ringL[write] = left.isFinite ? min(1, max(-1, left)) : 0
        ringR[write] = right.isFinite ? min(1, max(-1, right)) : 0
        write = (write + 1) % Self.size
        filled = min(Self.size, filled + 1)
        hopSamples += 1
        if filled == Self.size, hopSamples >= Self.hop {
            hopSamples = 0
            analyze(hostTime: hostTime)
        }
    }

    private func analyze(hostTime: UInt64) {
        var total: Double = 0
        var peak: Float = 0
        var energies = SIMD8<Float>.zero
        for channel in 0..<2 {
            let ring = channel == 0 ? ringL : ringR
            for i in 0..<Self.size {
                let value = ring[(write + i) % Self.size]
                total += Double(value * value)
                peak = max(peak, abs(value))
                scratch[i] = value * window[i]
            }
            var split = DSPSplitComplex(realp: real, imagp: imaginary)
            scratch.withMemoryRebound(to: DSPComplex.self, capacity: Self.size / 2) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.size / 2))
            }
            vDSP_fft_zrip(fft, &split, 1, 11, FFTDirection(FFT_FORWARD))
            vDSP_zvmags(&split, 1, powers, 1, vDSP_Length(Self.size / 2))
            for band in 0..<8 {
                var power: Float = 0
                for bin in ranges[band] { power += powers[bin] }
                energies[band] += power * spectralScale * 0.5
            }
        }
        let rms = Float(sqrt(total / Double(Self.size * 2)))
        let signal = rms >= 0.0001
        let dt = Float(Self.hop) / Float(sampleRate)
        var loudest: Float = 0
        for i in 0..<8 { energies[i] = sqrt(max(0, energies[i])); loudest = max(loudest, energies[i]) }
        let referenceTarget = max(0.5, min(1, loudest))
        reference += (referenceTarget - reference) * (1 - exp(-dt / (referenceTarget > reference ? 0.6 : 3)))
        let gain = min(2, 1 / reference)
        for band in 0..<8 {
            let tilt = pow(Float(10), Float(band) / 7 * 3 / 20) // bounded +3 dB treble compensation
            let energy = energies[band] * gain * tilt
            var target: Float = signal && energy > 0.0002 ? max(0, min(1, (20 * log10(energy) + 60) / 60)) : 0
            target = min(1, target + min(0.08, max(0, target - smoothed[band]) * 0.15))
            let time: Float = target > smoothed[band] ? 0.025 : 0.18
            smoothed[band] += (target - smoothed[band]) * (1 - exp(-dt / time))
            if smoothed[band] < 0.0001 { smoothed[band] = 0 }
        }
        sequence &+= 1
        mailbox.publish(AudioSpectrumFrame(sequence: sequence, hostTime: hostTime, sampleRate: sampleRate,
            bands: smoothed, rms: min(1, rms), peak: min(1, peak), hasSignal: signal))
    }
}

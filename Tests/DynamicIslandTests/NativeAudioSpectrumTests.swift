import CoreAudio
import XCTest
@testable import DynamicIsland

final class NativeAudioSpectrumTests: XCTestCase {
    func testLogBandsIdentifySinesAt44100And48000() throws {
        for rate in [44_100.0, 48_000.0] {
            for band in 0..<8 {
                let dsp = try RealtimeSpectrumProcessor(sampleRate: rate)
                let center = sqrt(dsp.bandEdges[band] * dsp.bandEdges[band + 1])
                let hz = (center * Double(RealtimeSpectrumProcessor.size) / rate).rounded() * rate / Double(RealtimeSpectrumProcessor.size)
                feed(dsp, hz: hz, amplitude: 0.3, frames: 12_288)
                let frame = try XCTUnwrap(dsp.mailbox.snapshot().frame)
                let largest = (0..<8).max { frame.bands[$0] < frame.bands[$1] }
                XCTAssertEqual(largest, band, "rate=\(rate) frequency=\(hz) bands=\(frame.bands)")
                XCTAssertEqual(frame.rms, 0.3 / sqrt(2), accuracy: 0.015)
                XCTAssertEqual(frame.peak, 0.3, accuracy: 0.003)
                XCTAssertTrue(frame.hasSignal)
            }
        }
    }

    func testSilenceTransientReleaseAndFiniteBounds() throws {
        let dsp = try RealtimeSpectrumProcessor(sampleRate: 48_000)
        feed(dsp, hz: 1000, amplitude: 0, frames: 4096)
        XCTAssertEqual(dsp.mailbox.snapshot().frame?.bands, .zero)
        feed(dsp, hz: 1000, amplitude: 0.5, frames: 4096)
        let active = try XCTUnwrap(dsp.mailbox.snapshot().frame)
        XCTAssertGreaterThan(active.bands[4], 0.5)
        feed(dsp, hz: 1000, amplitude: 0, frames: 48_000)
        let silent = try XCTUnwrap(dsp.mailbox.snapshot().frame)
        XCTAssertFalse(silent.hasSignal)
        XCTAssertLessThan(silent.bands[4], 0.02)
        let malformed: [Float] = [.nan, .infinity, -.infinity, 1e30, -1e30]
        for _ in 0..<1000 { malformed.withUnsafeBufferPointer { dsp.consume(left: $0) } }
        let bounded = try XCTUnwrap(dsp.mailbox.snapshot().frame)
        for v in [bounded.rms, bounded.peak] + (0..<8).map({ bounded.bands[$0] }) {
            XCTAssertTrue(v.isFinite); XCTAssertTrue((0...1).contains(v))
        }
    }

    func testStereoOppositePhaseIsNotCancelledAndRightOnlyIsMeasured() throws {
        for mode in [0, 1] {
            let dsp = try RealtimeSpectrumProcessor(sampleRate: 48_000)
            let left = (0..<12_288).map { mode == 0 ? Float(0.4 * sin(2 * .pi * 1000 * Double($0) / 48_000)) : 0 }
            let right = (0..<12_288).map { Float(-0.4 * sin(2 * .pi * 1000 * Double($0) / 48_000)) }
            left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { dsp.consume(left: l, right: $0) } }
            let frame = try XCTUnwrap(dsp.mailbox.snapshot().frame)
            XCTAssertTrue(frame.hasSignal)
            XCTAssertGreaterThan(frame.bands[4], 0.7)
            XCTAssertEqual(frame.rms, mode == 0 ? 0.4 / sqrt(2) : 0.2, accuracy: 0.015)
        }
    }

    func testInterleavedAndPlanarBufferListsMatchSyntheticPath() throws {
        let samples = (0..<4096).map { Float(0.2 * sin(2 * .pi * 1000 * Double($0) / 48_000)) }
        let expected = try RealtimeSpectrumProcessor(sampleRate: 48_000)
        samples.withUnsafeBufferPointer { expected.consume(left: $0) }
        for planar in [false, true] {
            let dsp = try RealtimeSpectrumProcessor(sampleRate: 48_000)
            let list = AudioBufferList.allocate(maximumBuffers: planar ? 2 : 1)
            defer { list.unsafeMutablePointer.deallocate() }
            let interleaved = samples.flatMap { [$0, $0] }
            samples.withUnsafeBufferPointer { mono in
                interleaved.withUnsafeBufferPointer { stereo in
                    if planar {
                        for i in 0..<2 { list[i] = AudioBuffer(mNumberChannels: 1,
                            mDataByteSize: UInt32(mono.count * 4), mData: UnsafeMutableRawPointer(mutating: mono.baseAddress!)) }
                    } else {
                        list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(stereo.count * 4),
                            mData: UnsafeMutableRawPointer(mutating: stereo.baseAddress!))
                    }
                    dsp.consume(UnsafePointer(list.unsafeMutablePointer), hostTime: 42)
                }
            }
            XCTAssertEqual(dsp.mailbox.snapshot().frame?.bands, expected.mailbox.snapshot().frame?.bands)
            XCTAssertEqual(dsp.mailbox.snapshot().frame?.hostTime, 42)
        }
    }

    func testNyquistAndUnsupportedSampleRateAndInvalidation() throws {
        XCTAssertThrowsError(try RealtimeSpectrumProcessor(sampleRate: .nan))
        XCTAssertThrowsError(try RealtimeSpectrumProcessor(sampleRate: 0))
        let dsp = try RealtimeSpectrumProcessor(sampleRate: 8000)
        XCTAssertLessThan(try XCTUnwrap(dsp.bandEdges.last), 4000)
        dsp.mailbox.invalidate()
        feed(dsp, hz: 1000, amplitude: 0.4, frames: 4096)
        XCTAssertNil(dsp.mailbox.snapshot().frame)
        XCTAssertTrue(dsp.mailbox.snapshot().invalidated)
    }

    func testMeasureBoundedSyntheticProcessing() throws {
        let dsp = try RealtimeSpectrumProcessor(sampleRate: 48_000)
        let chunk = (0..<512).map { Float(0.25 * sin(2 * .pi * 1000 * Double($0) / 48_000)) }
        var nanos: [UInt64] = []
        chunk.withUnsafeBufferPointer { buffer in
            for _ in 0..<1000 {
                let start = DispatchTime.now().uptimeNanoseconds
                dsp.consume(left: buffer)
                nanos.append(DispatchTime.now().uptimeNanoseconds - start)
            }
        }
        nanos.sort()
        let mean = Double(nanos.reduce(0, +)) / Double(nanos.count) / 1000
        let p95 = Double(nanos[950]) / 1000
        print("[AudioDSP] synthetic512Frames mean_us=\(mean) p95_us=\(p95) budget_us=10666")
        XCTAssertLessThan(p95, 10_666, "must fit a 512-frame/48kHz block on this host; not live HAL acceptance")
    }

    private func feed(_ dsp: RealtimeSpectrumProcessor, hz: Double, amplitude: Double, frames: Int) {
        let samples = (0..<frames).map { Float(amplitude * sin(2 * .pi * hz * Double($0) / dsp.sampleRate)) }
        samples.withUnsafeBufferPointer { dsp.consume(left: $0) }
    }
}

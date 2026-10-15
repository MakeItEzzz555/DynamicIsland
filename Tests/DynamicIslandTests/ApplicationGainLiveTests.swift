import AVFoundation
import CoreAudio
import XCTest
import os
@testable import DynamicIsland

/// Real-hardware acceptance, skipped unless explicitly authorized with
/// `DYNAMIC_ISLAND_LIVE_APP_VOLUME=1`. It plays quiet tones with `afplay` (each
/// process stands in for one helper process of an app), routes them through the
/// real engine on the current output and measures twice: inside the engine's
/// real IOProc (tap input vs output peak) and, when the output is a loopback
/// device, at the device boundary (the tone energy that actually reaches it).
/// macOS may ask the test runner for System Audio Recording. Ears stay in the
/// manual checklist.
@MainActor
final class ApplicationGainLiveTests: XCTestCase {
    func testGroupedHelpersAreAttenuatedTogetherIndependentlyAndReleasedCleanly() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_APP_VOLUME"] == "1",
                          "Live per-app volume needs explicit authorization")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("app-volume-live-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hardware = MeasuringGainHardware()
        let route = try hardware.defaultOutputRoute()
        try XCTSkipIf(route.capturesMicrophone, "The current output also has a microphone; v1 declines it by design")
        let objectsBefore = Self.audioObjectCounts()

        let frequencies: [Double] = [1_234, 2_345, 3_456, 4_567] // helper 1, helper 2, other app, late helper
        var players: [Process] = []
        defer { players.forEach { if $0.isRunning { $0.terminate() } } }
        func play(_ frequency: Double) throws -> Process {
            let file = directory.appendingPathComponent("tone\(Int(frequency)).caf")
            try Self.writeTone(to: file, frequency: frequency, seconds: 30)
            let player = Process()
            player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            player.arguments = ["-v", "0.5", file.path]
            try player.run()
            players.append(player)
            return player
        }
        func objectID(of player: Process) async throws -> AudioObjectID {
            for _ in 0..<80 {
                if let found = try ApplicationAudioDiscovery.readHALProcesses().first(where: { $0.pid == player.processIdentifier && $0.outputIORunning }) {
                    return found.objectID
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw XCTSkip("afplay never reported running output")
        }
        let helperOne = try play(frequencies[0]), helperTwo = try play(frequencies[1]), other = try play(frequencies[2])
        let app = [try await objectID(of: helperOne), try await objectID(of: helperTwo)]
        let otherObject = try await objectID(of: other)

        let observer = route.hasInputStreams ? try? LoopbackObserver(routeUID: route.uid, frequencies: frequencies) : nil
        defer { observer?.stop() }
        func measure(_ seconds: Double = 1.6) async throws -> [Double] {
            try await Task.sleep(for: .milliseconds(300)) // let the last gain ramp and any rebuild settle
            observer?.reset(); hardware.resetPeaks()
            try await Task.sleep(for: .seconds(seconds))
            return observer?.magnitudes() ?? []
        }
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        let baseline = try await measure()
        func report(_ phase: String, _ values: [Double], against reference: [Double]) {
            let ratios = zip(values, reference).map { String(format: "%.3f", $0 / max($1, 1e-9)) }
            let peaks = hardware.peaks()
            print("LIVE \(phase): device-boundary tone ratios vs direct \(ratios) route=\(route.uid) virtual=\(route.isVirtual) ioproc tap=\(peaks.tap) out=\(peaks.output)")
        }
        print("LIVE baseline tone amplitudes at the device \(baseline.map { String(format: "%.4f", $0) }) (generated 0.2 x afplay -v 0.5 = 0.1)")
        try XCTSkipIf(observer != nil && baseline.prefix(3).contains { $0 < 1e-4 }, "the loopback input did not carry the tones")

        // 1. Two helper processes of one app, 25% amplitude, the other app untouched.
        try await engine.setGain(0.25, application: "app.test", processes: app)
        var active = await engine.activeApplications
        XCTAssertEqual(active, ["app.test"])
        var mags = try await measure()
        var peaks = hardware.peaks()
        report("1 two helpers of one app at 25%", mags, against: baseline)
        XCTAssertGreaterThan(peaks.tap, 0.001)
        XCTAssertEqual(peaks.output / peaks.tap, 0.25, accuracy: 0.01, "the real IOProc applies the gain to the tapped helpers")
        if observer != nil {
            XCTAssertEqual(mags[0] / baseline[0], 0.25, accuracy: 0.1, "helper 1 reaches the device attenuated (and not also directly)")
            XCTAssertEqual(mags[1] / baseline[1], 0.25, accuracy: 0.1, "helper 2 reaches the device attenuated")
            XCTAssertEqual(mags[2] / baseline[2], 1, accuracy: 0.3, "the other app is unchanged")
        }

        // 2. A helper that starts later: audible at 100% until the group is re-tapped, then attenuated with no echo.
        let late = try play(frequencies[3])
        let lateObject = try await objectID(of: late)
        let lateBaseline = try await measure()
        let members = app + [lateObject]
        try await engine.setGain(0.25, application: "app.test", processes: members)
        let tapped = await engine.tappedProcesses(of: "app.test")
        XCTAssertEqual(tapped, Set(members), "the session follows the helper")
        mags = try await measure()
        report("2 late helper joined, group re-tapped", mags, against: [baseline[0], baseline[1], baseline[2], lateBaseline[3]])
        if observer != nil {
            XCTAssertEqual(mags[3] / lateBaseline[3], 0.25, accuracy: 0.1, "the late helper is attenuated after the tap update")
            XCTAssertEqual(mags[0] / baseline[0], 0.25, accuracy: 0.1, "no doubled playback after the swap")
            XCTAssertEqual(mags[2] / baseline[2], 1, accuracy: 0.3)
        }
        await engine.checkStalls()
        active = await engine.activeApplications
        XCTAssertEqual(active, ["app.test"], "the replacement renders, so the watchdog keeps it")

        // 3. Another app, independent gain at the same time.
        try await engine.setGain(0.5, application: "app.other", processes: [otherObject])
        mags = try await measure()
        report("3 other app at 50% while first app at 25%", mags, against: [baseline[0], baseline[1], baseline[2], lateBaseline[3]])
        if observer != nil {
            XCTAssertEqual(mags[2] / baseline[2], 0.5, accuracy: 0.15)
            XCTAssertEqual(mags[0] / baseline[0], 0.25, accuracy: 0.1, "the first app keeps its own level")
        }
        try await engine.release("app.other")

        // 4. 0% silences only the grouped app.
        try await engine.setGain(0, application: "app.test", processes: members)
        mags = try await measure()
        peaks = hardware.peaks()
        report("4 first app muted (0%)", mags, against: [baseline[0], baseline[1], baseline[2], lateBaseline[3]])
        XCTAssertEqual(peaks.output, 0, "muted output is exact silence")
        XCTAssertGreaterThan(peaks.tap, 0.001, "the tap still carries the (muted) apps")
        if observer != nil {
            let reference = [baseline[0], baseline[1], baseline[2], lateBaseline[3]]
            for index in [0, 1, 3] { XCTAssertLessThan(mags[index] / reference[index], 0.08) }
            XCTAssertEqual(mags[2] / baseline[2], 1, accuracy: 0.3)
        }

        // 5. 100% releases everything and leaves nothing behind.
        try await engine.setGain(1, application: "app.test", processes: members)
        active = await engine.activeApplications
        XCTAssertTrue(active.isEmpty)
        mags = try await measure()
        report("5 released (100%)", mags, against: [baseline[0], baseline[1], baseline[2], lateBaseline[3]])
        if observer != nil {
            for index in 0..<3 { XCTAssertEqual(mags[index] / baseline[index], 1, accuracy: 0.3, "released apps play directly again") }
        }
        try await engine.releaseAll()
        XCTAssertEqual(Self.audioObjectCounts(), objectsBefore, "no tap or aggregate device is left behind")
    }

    /// The prime real-world case: Chromium plays from a helper process, never from
    /// the browser's main process. A throwaway Brave instance (own profile) plays a
    /// tone; the "Brave Browser" row must exist, contain the helper that plays and
    /// move that tone through the row-level API.
    func testRealChromiumHelperIsAttenuatedThroughItsApplicationRow() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_APP_VOLUME"] == "1",
                          "Live per-app volume needs explicit authorization")
        let braveURL = URL(fileURLWithPath: "/Applications/Brave Browser.app")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: braveURL.path), "Brave Browser is not installed")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("app-volume-brave-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hardware = MeasuringGainHardware()
        let route = try hardware.defaultOutputRoute()
        try XCTSkipIf(route.capturesMicrophone, "The current output also has a microphone; v1 declines it by design")

        let frequency = 2_345.0
        let wav = directory.appendingPathComponent("tone.wav")
        let file = try AVAudioFile(forWriting: wav, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
        let frames = AVAudioFrameCount(48_000 * 20)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            let samples = try XCTUnwrap(buffer.floatChannelData)[channel]
            for index in 0..<Int(frames) { samples[index] = Float(sin(2 * .pi * frequency * Double(index) / 48_000) * 0.3) }
        }
        try file.write(from: buffer)
        try "<html><body><audio id=a src=\"tone.wav\" loop autoplay></audio><script>a.volume=0.3;a.play()</script></body></html>"
            .write(to: directory.appendingPathComponent("tone.html"), atomically: true, encoding: .utf8)

        let brave = Process()
        brave.executableURL = braveURL.appendingPathComponent("Contents/MacOS/Brave Browser")
        brave.arguments = ["--user-data-dir=\(directory.appendingPathComponent("profile").path)", "--no-first-run", "--no-default-browser-check",
                           "--autoplay-policy=no-user-gesture-required", "--window-size=300,200",
                           directory.appendingPathComponent("tone.html").absoluteString]
        brave.standardOutput = FileHandle.nullDevice; brave.standardError = FileHandle.nullDevice
        try brave.run()
        let engine = ApplicationGainEngine(hardware: hardware, watchdogInterval: .seconds(60))
        let defaults = UserDefaults(suiteName: "ApplicationGainLiveTests.\(UUID().uuidString)")!
        let discovery = ApplicationAudioDiscovery(engine: engine, defaults: defaults)
        defer {
            if brave.isRunning { brave.terminate() }
            Task { await discovery.disableRouting() }
        }

        var playing: ApplicationAudioProcess?
        for _ in 0..<160 where playing == nil {
            playing = try ApplicationAudioDiscovery.readHALProcesses()
                .first { $0.bundleIdentifier?.hasPrefix("com.brave.Browser") == true && $0.outputIORunning && $0.pid != brave.processIdentifier }
            if playing == nil { try await Task.sleep(for: .milliseconds(50)) }
        }
        let helper = try XCTUnwrap(playing, "Chromium never reported a playing process")
        XCTAssertNotEqual(helper.pid, brave.processIdentifier, "the sound comes from a helper, not the browser's main process")
        print("LIVE chromium: main pid \(brave.processIdentifier), playing helper pid \(helper.pid) bundle \(helper.bundleIdentifier ?? "-") path …\(helper.executablePath?.suffix(60) ?? "-")")

        let observer = route.hasInputStreams ? try? LoopbackObserver(routeUID: route.uid, frequencies: [frequency]) : nil
        defer { observer?.stop() }
        func measure() async throws -> Double? {
            try await Task.sleep(for: .milliseconds(300))
            observer?.reset(); hardware.resetPeaks()
            try await Task.sleep(for: .milliseconds(1_400))
            return observer?.magnitudes().first
        }
        let baseline = try await measure()

        await discovery.setGainEnabled(true)
        let rows = discovery.outputs.filter { $0.bundleIdentifier == "com.brave.Browser" }
        XCTAssertEqual(rows.count, 1, "all Chromium processes are one Brave Browser row")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.name, "Brave Browser")
        XCTAssertTrue(row.identity.processObjectIDs.contains(helper.objectID), "the row owns the helper that plays")

        let half = await discovery.requestGain(0.5, application: row.identity) // slider 50% -> amplitude 0.25
        XCTAssertEqual(half, .verified(volume: 0.5, muted: false))
        var peaks = hardware.peaks()
        let attenuated = try await measure()
        peaks = hardware.peaks()
        print("LIVE chromium 50%: device ratio \(String(describing: zip([attenuated], [baseline]).map { ($0 ?? 0) / max($1 ?? 1, 1e-9) })) ioproc tap=\(peaks.tap) out=\(peaks.output)")
        XCTAssertGreaterThan(peaks.tap, 0.001, "the helper's audio is what the tap carries")
        XCTAssertEqual(peaks.output / peaks.tap, 0.25, accuracy: 0.01)
        if let attenuated, let baseline { XCTAssertEqual(attenuated / baseline, 0.25, accuracy: 0.08, "Chromium's audible level follows the Brave row") }

        let current = try XCTUnwrap(discovery.outputs.first { $0.bundleIdentifier == "com.brave.Browser" })
        _ = await discovery.requestGain(0, application: current.identity)
        let muted = try await measure()
        if let muted, let baseline { XCTAssertLessThan(muted / baseline, 0.05, "0% silences Brave") }
        _ = await discovery.requestGain(1, application: try XCTUnwrap(discovery.outputs.first { $0.bundleIdentifier == "com.brave.Browser" }).identity)
        let restored = try await measure()
        if let restored, let baseline { XCTAssertEqual(restored / baseline, 1, accuracy: 0.2, "100% releases Brave") }
        let activeAfterRelease = await engine.activeApplications
        XCTAssertTrue(activeAfterRelease.isEmpty)
        await discovery.disableRouting()
    }

    /// Read-only: the real HAL process list grouped by the real resolver. Helper
    /// processes must land under the app whose bundle contains them.
    func testRealProcessListIsGroupedUnderOwningApplications() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LIVE_APP_VOLUME"] == "1",
                          "Live per-app volume needs explicit authorization")
        let processes = try ApplicationAudioDiscovery.readHALProcesses()
        let discovery = ApplicationAudioDiscovery(readProcesses: { processes })
        discovery.apply(processes, generation: 1)
        let owners = ApplicationAudioOwnership.liveOwners(for: processes)
        for process in processes {
            guard let path = process.executablePath, let appURL = ApplicationAudioOwnership.outerApplicationURL(executablePath: path),
                  let bundle = Bundle(url: appURL)?.bundleIdentifier, let owner = owners[process.objectID] else { continue }
            XCTAssertEqual(owner.bundleIdentifier, bundle, "\(process.bundleIdentifier ?? "?") (pid \(process.pid)) belongs to \(appURL.lastPathComponent)")
        }
        let rows = discovery.outputs.map { "\($0.name) [\($0.bundleIdentifier ?? "-")] processes=\($0.identity.processObjectIDs.count) playing=\($0.activity == .outputIOActive)" }
        print("LIVE rows (running output only): \(rows)")
        print("LIVE HAL processes: \(processes.count), applications after grouping: \(Set(owners.values.map(\.bundleIdentifier)).count + processes.filter { owners[$0.objectID] == nil }.count)")
    }

    // MARK: Helpers

    /// Byte sizes of the system-wide process-tap and device lists; equal sizes mean nothing was left behind.
    private static func audioObjectCounts() -> [Int] {
        [kAudioHardwarePropertyTapList, kAudioHardwarePropertyDevices].map { selector in
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes)
            return Int(bytes)
        }
    }

    private static func writeTone(to url: URL, frequency: Double, seconds: Double) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(48_000 * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            let samples = try XCTUnwrap(buffer.floatChannelData)[channel]
            for index in 0..<Int(frames) { samples[index] = Float(sin(2 * .pi * frequency * Double(index) / 48_000) * 0.2) }
        }
        try file.write(from: buffer)
    }
}

/// The real hardware with a measuring IOProc: it records the tap's input peak and
/// the output peak around the engine's own renderer.
private final class MeasuringGainHardware: ApplicationGainHardware, @unchecked Sendable {
    private let base = CoreAudioApplicationGainHardware()
    private let state = OSAllocatedUnfairLock(initialState: (tap: Float(0), output: Float(0)))

    func resetPeaks() { state.withLock { $0 = (0, 0) } }
    func peaks() -> (tap: Float, output: Float) { state.withLock { $0 } }

    func defaultOutputRoute() throws -> ApplicationGainRoute { try base.defaultOutputRoute() }
    func createTap(processes: [AudioObjectID], route: ApplicationGainRoute) throws -> AudioObjectID { try base.createTap(processes: processes, route: route) }
    func format(tap: AudioObjectID) throws -> AudioStreamBasicDescription { try base.format(tap: tap) }
    func createAggregate(tap: AudioObjectID, route: ApplicationGainRoute) throws -> AudioObjectID { try base.createAggregate(tap: tap, route: route) }
    func createIOProc(device: AudioObjectID, renderer: ApplicationGainRenderer) throws -> AudioDeviceIOProcID {
        var io: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&io, device, nil) { [state] _, input, _, output, _ in
            renderer.render(input: input, output: output)
            let tapPeak = Self.peak(of: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).last)
            let outputPeak = UnsafeMutableAudioBufferListPointer(output).reduce(Float(0)) { max($0, Self.peak(of: $1)) }
            state.withLock { $0 = (max($0.tap, tapPeak), max($0.output, outputPeak)) }
        }
        guard status == noErr, let io else { throw NativeAudioError.operationFailed(.createIOProc, status) }
        return io
    }
    private static func peak(of buffer: AudioBuffer?) -> Float {
        guard let buffer, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
        return (0..<Int(buffer.mDataByteSize) / 4).reduce(Float(0)) { max($0, abs(data[$1])) }
    }
    func start(device: AudioObjectID, io: AudioDeviceIOProcID) throws { try base.start(device: device, io: io) }
    func stop(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { base.stop(device: device, io: io) }
    func destroyIOProc(device: AudioObjectID, io: AudioDeviceIOProcID) -> OSStatus { base.destroyIOProc(device: device, io: io) }
    func destroyAggregate(_ id: AudioObjectID) -> OSStatus { base.destroyAggregate(id) }
    func destroyTap(_ id: AudioObjectID) -> OSStatus { base.destroyTap(id) }
}

/// Reads a loopback output device's own input (the mix that reached it) and
/// measures the amplitude of a few pure tones with a coherent sine/cosine sum.
private final class LoopbackObserver: @unchecked Sendable {
    private struct Sums { var cos: [Double]; var sin: [Double]; var frames = 0 }
    private let device: AudioObjectID
    private var io: AudioDeviceIOProcID?
    private let toneCount: Int
    private let state: OSAllocatedUnfairLock<Sums>

    init(routeUID: String, frequencies: [Double]) throws {
        var uid = routeUID as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
        }
        guard status == noErr, device != kAudioObjectUnknown else { throw NativeAudioError.perApplicationRoutingUnavailable }
        var rate = Float64(48_000)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(device, &rateAddress, 0, nil, &rateSize, &rate)
        self.device = device
        toneCount = frequencies.count
        let sums = OSAllocatedUnfairLock(initialState: Sums(cos: Array(repeating: 0, count: frequencies.count),
                                                            sin: Array(repeating: 0, count: frequencies.count)))
        state = sums
        let sampleRate = rate
        var created: AudioDeviceIOProcID?
        let create = AudioDeviceCreateIOProcIDWithBlock(&created, device, nil) { _, input, _, _, _ in
            guard let buffer = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).first,
                  let data = buffer.mData?.assumingMemoryBound(to: Float.self), buffer.mNumberChannels > 0 else { return }
            let channels = Int(buffer.mNumberChannels), frames = Int(buffer.mDataByteSize) / (4 * channels)
            sums.withLock { sums in
                for frame in 0..<frames {
                    let sample = Double(data[frame * channels])
                    for (index, frequency) in frequencies.enumerated() {
                        let phase = 2 * Double.pi * frequency * Double(sums.frames + frame) / sampleRate
                        sums.cos[index] += sample * Foundation.cos(phase); sums.sin[index] += sample * Foundation.sin(phase)
                    }
                }
                sums.frames += frames
            }
        }
        guard create == noErr, let created else { throw NativeAudioError.operationFailed(.createIOProc, create) }
        io = created
        let started = AudioDeviceStart(device, created)
        guard started == noErr else { throw NativeAudioError.operationFailed(.startDevice, started) }
    }

    func reset() { state.withLock { $0 = Sums(cos: Array(repeating: 0, count: toneCount), sin: Array(repeating: 0, count: toneCount)) } }
    func magnitudes() -> [Double] {
        state.withLock { sums -> [Double] in
            var result: [Double] = []
            for index in 0..<toneCount {
                let power: Double = sums.cos[index] * sums.cos[index] + sums.sin[index] * sums.sin[index]
                result.append(2 * power.squareRoot() / Double(max(1, sums.frames)))
            }
            return result
        }
    }
    func stop() {
        guard let io else { return }
        AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io); self.io = nil
    }
}

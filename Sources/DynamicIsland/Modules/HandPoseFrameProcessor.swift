@preconcurrency import AVFoundation
import Vision
import CoreVideo
import Foundation

struct HandInferenceCadence {
    private var deadline = -Double.infinity
    mutating func accepts(_ timestamp: TimeInterval) -> Bool {
        guard timestamp >= deadline else { return false }
        deadline = max(deadline + 1 / 20, timestamp)
        return true
    }
}

struct HandPoseFrameResult: Sendable {
    var observation: HandNavigationObservation?
    var generation: Int
    var latency: Double
    var failed = false
    var isSampleReceipt = false
}

/// All Vision state is confined to this serial output queue. Only numeric
/// observations cross to the UI; sample buffers leave scope after inference.
final class HandPoseFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "DynamicIsland.CameraNavigation.vision", qos: .userInitiated)
    private let request = VNDetectHumanHandPoseRequest()
    private let generation: Int
    private let deliver: @Sendable (HandPoseFrameResult) -> Void
    private var cadence = HandInferenceCadence()
    private var previousObservation: HandNavigationObservation?
    private let lock = NSLock()
    private var stopped = false
    private var reportedFirstSample = false

    init(generation: Int, deliver: @escaping @Sendable (HandPoseFrameResult) -> Void) {
        self.generation = generation; self.deliver = deliver
        request.maximumHandCount = 1
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        request.cancel()
    }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isStopped else { return }
        if !reportedFirstSample {
            reportedFirstSample = true
            deliver(.init(observation: nil, generation: generation, latency: 0, isSampleReceipt: true))
        }
        let time = ProcessInfo.processInfo.systemUptime
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer), cadence.accepts(time) else { return }
        autoreleasepool {
            var observation: HandNavigationObservation?
            var failed = false
            do {
                try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:]).perform([request])
                if let hand = request.results?.first {
                    observation = try Self.observation(hand, timestamp: time,
                        aspectRatio: Double(CVPixelBufferGetWidth(pixels)) / Double(max(1, CVPixelBufferGetHeight(pixels))))
                }
            } catch { observation = nil; failed = true }
            if var current = observation, let previous = previousObservation, current.timestamp > previous.timestamp,
               current.timestamp - previous.timestamp < 0.3, current.side == previous.side {
                let dt = current.timestamp - previous.timestamp
                current.palmVelocity = CGPoint(x: (current.palm.x - previous.palm.x) / dt, y: (current.palm.y - previous.palm.y) / dt)
                observation = current
            }
            previousObservation = observation
            guard !isStopped else { return }
            deliver(HandPoseFrameResult(observation: observation, generation: generation,
                                       latency: ProcessInfo.processInfo.systemUptime - time, failed: failed))
        }
    }

    static func observation(_ hand: VNHumanHandPoseObservation, timestamp: TimeInterval, aspectRatio: Double = 1) throws -> HandNavigationObservation? {
        let points = try hand.recognizedPoints(.all)
        let required: [VNHumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .indexMCP, .middleTip, .middleMCP, .littleMCP, .wrist]
        guard required.allSatisfy({ (points[$0]?.confidence ?? 0) >= 0.5 }) else { return nil }
        func point(_ joint: VNHumanHandPoseObservation.JointName) -> CGPoint {
            HandNavigationCoordinates.oriented(points[joint]!.location)
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { HandNavigationGeometry.distance(a, b, aspectRatio: aspectRatio) }
        let wrist = point(.wrist), indexMCP = point(.indexMCP), middleMCP = point(.middleMCP), pinkyMCP = point(.littleMCP)
        let measurement = HandNavigationGeometry.measure(thumb: point(.thumbTip), index: point(.indexTip), wrist: wrist,
            middleMCP: middleMCP, indexMCP: indexMCP, littleMCP: pinkyMCP, aspectRatio: aspectRatio)
        let scale = measurement.scale
        guard scale >= 0.025 else { return nil }
        let indexExtended = distance(point(.indexTip), wrist) > distance(indexMCP, wrist) + scale * 0.45
        let middleExtended = distance(point(.middleTip), wrist) > distance(middleMCP, wrist) + scale * 0.45
        let ringExtended: Bool? = points[.ringTip].flatMap { $0.confidence >= 0.5 ? distance(HandNavigationCoordinates.oriented($0.location), wrist) > distance(middleMCP, wrist) + scale * 0.4 : nil }
        let pinkyExtended: Bool? = points[.littleTip].flatMap { $0.confidence >= 0.5 ? distance(HandNavigationCoordinates.oriented($0.location), wrist) > distance(pinkyMCP, wrist) + scale * 0.4 : nil }
        let pose: HandNavigationPose = indexExtended && middleExtended && ringExtended == true && pinkyExtended == true ? .openPalm
            : indexExtended && middleExtended && ringExtended == false && pinkyExtended == false ? .twoFinger
            : indexExtended ? .pointer : .other
        return HandNavigationObservation(fingertip: point(.indexTip),
            palm: CGPoint(x: (wrist.x + middleMCP.x) / 2, y: (wrist.y + middleMCP.y) / 2),
            handScale: scale, pinchRatio: measurement.pinch,
            pose: pose, confidence: Double(required.map { points[$0]!.confidence }.min() ?? 0), timestamp: timestamp,
            fingers: .init(index: indexExtended, middle: middleExtended, ring: ringExtended, little: pinkyExtended),
            side: hand.chirality == .left ? .left : hand.chirality == .right ? .right : .unknown)
    }
}

/// A blocked UI retains at most one numeric result and one scheduled delivery.
final class HandPoseResultMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: HandPoseFrameResult?
    private var scheduled = false
    private let consume: @MainActor @Sendable (HandPoseFrameResult) -> Void

    init(consume: @escaping @MainActor @Sendable (HandPoseFrameResult) -> Void) { self.consume = consume }
    func submit(_ value: HandPoseFrameResult) {
        lock.lock(); latest = value
        let schedule = !scheduled; scheduled = true; lock.unlock()
        if schedule { Task { @MainActor [self] in if let value = take() { consume(value) } } }
    }
    private func take() -> HandPoseFrameResult? {
        lock.lock(); defer { lock.unlock() }; scheduled = false
        defer { latest = nil }; return latest
    }
}

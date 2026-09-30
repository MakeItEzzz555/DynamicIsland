import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import Vision

enum BackgroundRemovalError: LocalizedError, Equatable {
    case disabled
    case busy
    case unsupportedInput
    case decodeFailed
    case noForegroundFound
    case segmentationFailed(String)
    case cancelled
    case exportFailed(String)
    case noResult
    case unsupportedAction(IslandCapabilityAction)

    var errorDescription: String? {
        switch self {
        case .disabled:
            "Background Removal is disabled."
        case .busy:
            "An image is already being processed."
        case .unsupportedInput:
            "This file is not a supported image."
        case .decodeFailed:
            "The image could not be decoded."
        case .noForegroundFound:
            "No foreground subject was found in the image."
        case .segmentationFailed(let message):
            "Background removal failed: \(message)"
        case .cancelled:
            "Background removal was cancelled."
        case .exportFailed(let message):
            "Export failed: \(message)"
        case .noResult:
            "There is no processed image yet."
        case .unsupportedAction(let action):
            "Background Removal does not support \(action.rawValue)."
        }
    }
}

struct BackgroundRemovalResult: Equatable, Sendable {
    let sourceURL: URL
    /// Processed PNG in the controller's private working directory.
    let previewURL: URL
    let pixelWidth: Int
    let pixelHeight: Int
}

enum BackgroundRemovalPhase: Equatable, Sendable {
    case idle
    case processing(sourceURL: URL)
    case completed(BackgroundRemovalResult)
    case failed(String)
}

struct BackgroundRemovalOutput: Sendable {
    let pngData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Local image segmentation. Implementations must not use the network.
protocol BackgroundRemovalProcessing: Sendable {
    /// Throws `CancellationError` or `.cancelled` when the task is cancelled.
    func removeBackground(from imageURL: URL) async throws -> BackgroundRemovalOutput
}

/// Vision foreground-instance segmentation (on-device), composited with
/// Core Image and encoded as PNG with alpha.
struct VisionBackgroundRemovalProcessor: BackgroundRemovalProcessing {
    static let maximumFileBytes = 200 * 1024 * 1024

    func removeBackground(from imageURL: URL) async throws -> BackgroundRemovalOutput {
        let image = try Self.decode(imageURL)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let box = RequestBox(request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BackgroundRemovalOutput, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try Self.process(image: image, request: box.request)
                    })
                }
            }
        } onCancel: {
            box.request.cancel()
        }
    }

    static func decode(_ url: URL) throws -> CGImage {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true,
              let type = values?.contentType,
              type.conforms(to: .image) else {
            throw BackgroundRemovalError.unsupportedInput
        }
        if let size = values?.fileSize, size > maximumFileBytes {
            throw BackgroundRemovalError.unsupportedInput
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw BackgroundRemovalError.decodeFailed
        }
        return image
    }

    private static func process(
        image: CGImage,
        request: VNGenerateForegroundInstanceMaskRequest
    ) throws -> BackgroundRemovalOutput {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            if (error as NSError).code == VNErrorCode.requestCancelled.rawValue {
                throw BackgroundRemovalError.cancelled
            }
            throw BackgroundRemovalError.segmentationFailed(error.localizedDescription)
        }
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw BackgroundRemovalError.noForegroundFound
        }

        let masked: CVPixelBuffer
        do {
            masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
        } catch {
            throw BackgroundRemovalError.segmentationFailed(error.localizedDescription)
        }

        let ciImage = CIImage(cvPixelBuffer: masked)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.pngRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace) else {
            throw BackgroundRemovalError.segmentationFailed("The result could not be encoded.")
        }
        return BackgroundRemovalOutput(
            pngData: data,
            pixelWidth: Int(ciImage.extent.width),
            pixelHeight: Int(ciImage.extent.height)
        )
    }
}

private final class RequestBox: @unchecked Sendable {
    let request: VNGenerateForegroundInstanceMaskRequest
    init(_ request: VNGenerateForegroundInstanceMaskRequest) { self.request = request }
}

// MARK: - Controller

@MainActor
final class BackgroundRemovalController: ObservableObject, IslandCapabilityAdapter {
    static let activityID = "backgroundRemoval.processing"

    let capabilityID: IslandCapabilityID = .backgroundRemoval

    @Published private(set) var phase: BackgroundRemovalPhase = .idle
    @Published private(set) var isEnabled = true
    @Published private(set) var lastExportURL: URL?

    private let processor: BackgroundRemovalProcessing
    private let liveActivities: LiveActivityStore
    private let capabilities: IslandCapabilityRegistry
    private let shelfStorage: FileShelfTemporaryStorage
    private let addToShelf: ([URL]) -> Void
    private let workingDirectory: URL
    private let now: () -> Date
    private var task: Task<Void, Never>?
    private var generation = 0
    private var addToShelfWhenFinished = false

    init(
        liveActivities: LiveActivityStore,
        capabilities: IslandCapabilityRegistry,
        processor: BackgroundRemovalProcessing = VisionBackgroundRemovalProcessor(),
        shelfStorage: FileShelfTemporaryStorage = .shared,
        addToShelf: @escaping ([URL]) -> Void,
        workingDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("BackgroundRemoval", isDirectory: true),
        now: @escaping () -> Date = Date.init
    ) {
        self.liveActivities = liveActivities
        self.capabilities = capabilities
        self.processor = processor
        self.shelfStorage = shelfStorage
        self.addToShelf = addToShelf
        self.workingDirectory = workingDirectory
        self.now = now
        publishState()
    }

    var result: BackgroundRemovalResult? {
        if case .completed(let result) = phase { return result }
        return nil
    }

    var isProcessing: Bool {
        if case .processing = phase { return true }
        return false
    }

    var snapshot: IslandCapabilitySnapshot {
        let health: IslandCapabilityHealth
        if case .failed(let message) = phase {
            health = .failed(message: message)
        } else {
            health = .healthy
        }
        return IslandCapabilitySnapshot(
            id: .backgroundRemoval,
            isEnabled: isEnabled,
            permission: .notRequired,
            availability: .available,
            health: health,
            supportedActions: isProcessing ? [.stop] : [],
            isActive: isEnabled && isProcessing,
            progress: nil,
            statusText: statusText
        )
    }

    var statusText: String {
        guard isEnabled else { return "Disabled" }
        switch phase {
        case .idle: return "Ready · on-device"
        case .processing: return "Removing background"
        case .completed: return "Result ready"
        case .failed(let message): return message
        }
    }

    // MARK: Workflow

    /// Starts local processing. The source file is only read. When started
    /// from the File Tray, the result is added back to the Tray on success.
    func process(imageURL: URL, addResultToShelfWhenFinished: Bool = false) throws {
        guard isEnabled else { throw BackgroundRemovalError.disabled }
        guard !isProcessing else { throw BackgroundRemovalError.busy }

        discardPreview()
        generation += 1
        addToShelfWhenFinished = addResultToShelfWhenFinished
        let token = generation
        let source = imageURL.standardizedFileURL
        phase = .processing(sourceURL: source)
        publishActivity(source: source)
        publishState()

        let processor = processor
        task = Task { [weak self] in
            do {
                let output = try await processor.removeBackground(from: source)
                try Task.checkCancellation()
                self?.finish(token: token, source: source, output: output)
            } catch {
                self?.fail(token: token, error: error)
            }
        }
    }

    /// Waits for the current processing task, if any. Used by callers and tests.
    func waitForCompletion() async {
        await task?.value
    }

    /// Vision requests honour cancellation, so this stops the actual work.
    func cancel() {
        guard isProcessing else { return }
        generation += 1
        task?.cancel()
        task = nil
        liveActivities.remove(id: Self.activityID)
        phase = .idle
        publishState()
    }

    func reset() {
        cancel()
        discardPreview()
        phase = .idle
        publishState()
    }

    /// Writes the result next to `directory` (default: the source's folder)
    /// using a collision-safe name. Never overwrites existing files.
    @discardableResult
    func export(toDirectory directory: URL? = nil) throws -> URL {
        guard let result else { throw BackgroundRemovalError.noResult }
        let targetDirectory = directory ?? result.sourceURL.deletingLastPathComponent()
        let destination = Self.availableDestination(for: result.sourceURL, in: targetDirectory)
        do {
            let data = try Data(contentsOf: result.previewURL)
            try data.write(to: destination, options: .withoutOverwriting)
        } catch {
            throw BackgroundRemovalError.exportFailed(error.localizedDescription)
        }
        lastExportURL = destination
        return destination
    }

    @discardableResult
    func addResultToShelf() throws -> URL {
        guard let result else { throw BackgroundRemovalError.noResult }
        let shelfURL: URL
        do {
            shelfURL = try shelfStorage.copyIntoShelf(
                result.previewURL,
                suggestedName: Self.outputFilename(for: result.sourceURL, index: 1)
            )
        } catch {
            throw BackgroundRemovalError.exportFailed(error.localizedDescription)
        }
        addToShelf([shelfURL])
        return shelfURL
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            cancel()
            discardPreview()
            phase = .idle
        }
        isEnabled = enabled
        publishState()
    }

    func terminate() {
        cancel()
        discardPreview()
    }

    static func outputFilename(for source: URL, index: Int) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        let stem = base.isEmpty ? "Image" : base
        return index <= 1
            ? "\(stem) (background removed).png"
            : "\(stem) (background removed) \(index).png"
    }

    static func availableDestination(
        for source: URL,
        in directory: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        var index = 1
        while true {
            let candidate = directory.appendingPathComponent(outputFilename(for: source, index: index))
            if candidate.standardizedFileURL != source.standardizedFileURL, !fileExists(candidate) {
                return candidate
            }
            index += 1
        }
    }

    // MARK: IslandCapabilityAdapter

    func refresh() async {
        publishState()
    }

    func perform(_ action: IslandCapabilityAction) async throws {
        switch action {
        case .stop:
            cancel()
        case .test:
            await refresh()
        case .start, .openSettings, .configureShortcut:
            throw BackgroundRemovalError.unsupportedAction(action)
        }
    }

    // MARK: Private

    private func finish(token: Int, source: URL, output: BackgroundRemovalOutput) {
        guard token == generation else { return }
        task = nil
        do {
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let previewURL = workingDirectory.appendingPathComponent("result-\(UUID().uuidString).png")
            try output.pngData.write(to: previewURL, options: .atomic)
            guard CGImageSourceCreateWithURL(previewURL as CFURL, nil)
                .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) != nil else {
                try? FileManager.default.removeItem(at: previewURL)
                throw BackgroundRemovalError.segmentationFailed("The result image is invalid.")
            }
            liveActivities.remove(id: Self.activityID)
            phase = .completed(BackgroundRemovalResult(
                sourceURL: source,
                previewURL: previewURL,
                pixelWidth: output.pixelWidth,
                pixelHeight: output.pixelHeight
            ))
            publishState()
            if addToShelfWhenFinished {
                addToShelfWhenFinished = false
                _ = try? addResultToShelf()
            }
        } catch {
            fail(token: token, error: error)
        }
    }

    private func fail(token: Int, error: Error) {
        guard token == generation else { return }
        task = nil
        liveActivities.remove(id: Self.activityID)
        if error is CancellationError || (error as? BackgroundRemovalError) == .cancelled {
            phase = .idle
        } else if let error = error as? BackgroundRemovalError {
            phase = .failed(error.localizedDescription)
        } else {
            phase = .failed(BackgroundRemovalError.segmentationFailed(error.localizedDescription).localizedDescription)
        }
        publishState()
    }

    private func discardPreview() {
        if let result {
            try? FileManager.default.removeItem(at: result.previewURL)
        }
    }

    private func publishActivity(source: URL) {
        liveActivities.update(Self.makeActivity(filename: source.lastPathComponent, updatedAt: now()))
    }

    /// Production activity shape; also used by Settings previews.
    static func makeActivity(filename: String, updatedAt: Date) -> DynamicIslandLiveActivity {
        DynamicIslandLiveActivity(
            id: activityID,
            kind: .backgroundRemoval,
            title: "Removing background",
            subtitle: filename,
            symbolName: "person.crop.rectangle",
            priority: 84,
            isActive: true,
            progress: nil,
            updatedAt: updatedAt,
            lifecycle: LiveActivityLifecycleMetadata(
                authority: .vision,
                startEvidence: "Vision foreground segmentation request started",
                progressEvidence: nil,
                completionEvidence: "A decoded PNG result was written to local storage",
                dismissPolicy: .untilSourceEnds,
                supportsCancellation: true
            )
        )
    }

    private func publishState() {
        capabilities.update(snapshot)
    }
}

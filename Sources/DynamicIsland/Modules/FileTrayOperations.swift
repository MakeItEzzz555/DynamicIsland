import AppKit
import Foundation
import UniformTypeIdentifiers
import Vision

/// The visible outcome of one File Tray operation. `succeeded` is published
/// only after the output exists and was accepted by the Tray.
enum FileTrayOperationStatus: Equatable {
    case working(String)
    case succeeded(String)
    case failed(String)

    var message: String {
        switch self { case .working(let m), .succeeded(let m), .failed(let m): m }
    }
}

/// Shared File Tray operations used by the context menu and the drop zones.
/// Every operation leaves its sources untouched and writes new,
/// collision-safe outputs, which are added to the Tray and selected.
@MainActor
extension FileShelfStore {
    func performDropZone(_ zone: FileDropZone, accepted: [URL], attemptedCount: Int,
                         operations: BackgroundOperationController, executor: FileDragActionExecutor,
                         anchor: NSView?, layoutStore: IslandLayoutStore) {
        let files = accepted.filter { self.files.contains($0.standardizedFileURL) }
        guard !files.isEmpty else {
            setOperationStatus(.failed("No files were accepted by the Tray."), clearAfter: .seconds(4))
            return
        }
        select(only: files)
        let prefix = files.count < attemptedCount ? "Added \(files.count) of \(attemptedCount). " : ""
        switch zone {
        case .keep:
            setOperationStatus(files.count < attemptedCount
                ? .failed(prefix + "Remaining files were not accepted.")
                : .succeeded("Added \(files.count) item\(files.count == 1 ? "" : "s") to the Tray."), clearAfter: .seconds(4))
        case .messages, .share:
            let outcome = executor.perform(zone == .messages ? .messages : .share, urls: files, anchor: anchor, layoutStore: layoutStore)
            switch outcome {
            case .handedOff:
                setOperationStatus(.succeeded(prefix + (zone == .messages ? "Opened Messages composition; nothing has been sent." : "Opened sharing options.")), clearAfter: .seconds(4))
            case .unavailable(let reason), .failed(let reason):
                setOperationStatus(.failed(prefix + reason + " Accepted files remain in the Tray."), clearAfter: .seconds(5))
            }
        case .zip:
            createZIP(files, using: operations)
            if !prefix.isEmpty { setOperationStatus(.working(prefix + "Creating ZIP of accepted files…")) }
        }
    }

    // MARK: Convert

    func convertImages(_ urls: [URL], to format: FileConversionFormat, using operations: BackgroundOperationController? = nil) {
        let sources = urls.filter { FileConversionController.targetFormats(for: $0).contains(format) }
        guard !sources.isEmpty else {
            setOperationStatus(.failed("These files can’t be converted to \(format.displayName)."), clearAfter: .seconds(4))
            return
        }
        setOperationStatus(.working(sources.count == 1 ? "Converting to \(format.displayName)…" : "Converting \(sources.count) files…"))
        if let operations {
            var pending = sources.count
            var outputs: [URL] = []
            var failures = 0
            let settle: @MainActor () -> Void = { [weak self] in
                pending -= 1
                if pending == 0 { self?.finish(outputs: outputs, failures: failures, noun: "converted file") }
            }
            for source in sources {
                let started = operations.startImageConversion(source, to: format) { outputs.append($0); settle() } onFailed: { _ in failures += 1; settle() }
                if started == nil { failures += 1; settle() }
            }
            return
        }
        Task { @MainActor in
            var outputs: [URL] = []
            var failures = 0
            for source in sources {
                do { outputs.append(try await FileConversionController.convert(source, to: format)) }
                catch { failures += 1 }
            }
            finish(outputs: outputs, failures: failures, noun: "converted file")
        }
    }

    func convertAudio(_ url: URL, to format: FileAudioFormat, using operations: BackgroundOperationController? = nil) {
        setOperationStatus(.working("Converting to \(format.rawValue)…"))
        if let operations {
            let started = operations.startAudioConversion(url, to: format) { [weak self] in
                self?.finish(outputs: [$0], failures: 0, noun: "converted file")
            } onFailed: { [weak self] reason in
                self?.setOperationStatus(.failed("Conversion failed: \(reason). Original preserved."), clearAfter: .seconds(5))
            }
            if started == nil { setOperationStatus(.failed("The conversion could not be started."), clearAfter: .seconds(4)) }
            return
        }
        Task { @MainActor in
            do { finish(outputs: [try await FileAudioConversion.convert(url, to: format)], failures: 0, noun: "converted file") }
            catch { setOperationStatus(.failed("Conversion failed: \(error.localizedDescription) Original preserved."), clearAfter: .seconds(5)) }
        }
    }

    // MARK: Archive

    /// Starts a verified ZIP on the background-operation center; the archive
    /// joins the Tray only after the operation reports completion.
    func createZIP(_ urls: [URL], using operations: BackgroundOperationController) {
        guard !urls.isEmpty else { return }
        let started = operations.startCompression(sources: urls) { [weak self] archive in
            self?.finish(outputs: [archive], failures: 0, noun: "archive")
        } onFailed: { [weak self] reason in
            self?.setOperationStatus(.failed("ZIP not created: \(reason). Originals preserved."), clearAfter: .seconds(5))
        }
        if started == nil {
            setOperationStatus(.failed("The archive could not be started."), clearAfter: .seconds(4))
        } else {
            setOperationStatus(.working(urls.count == 1 ? "Creating ZIP…" : "Creating ZIP of \(urls.count) items…"))
        }
    }

    /// Extracts each ZIP into a new folder beside it; the folders join the Tray
    /// when their operations complete. Originals are never modified.
    func extractArchives(_ urls: [URL], using operations: BackgroundOperationController) {
        let archives = urls.filter { $0.pathExtension.lowercased() == "zip" }
        guard !archives.isEmpty else { return }
        setOperationStatus(.working(archives.count == 1 ? "Extracting archive…" : "Extracting \(archives.count) archives…"))
        for archive in archives {
            let started = operations.startExtraction(archive: archive) { [weak self] folder in
                self?.finish(outputs: [folder], failures: 0, noun: "folder")
            } onFailed: { [weak self] reason in
                self?.setOperationStatus(.failed("Not extracted: \(reason) Archive preserved."), clearAfter: .seconds(5))
            }
            if started == nil { setOperationStatus(.failed("The extraction could not be started."), clearAfter: .seconds(4)) }
        }
    }

    // MARK: Folder

    /// Creates "New Folder" beside the first item and **copies** the items
    /// into it. Originals stay where they are and stay in the Tray.
    func makeFolder(withCopiesOf urls: [URL]) {
        guard let parent = urls.first?.deletingLastPathComponent() else { return }
        setOperationStatus(.working("Creating folder…"))
        Task { @MainActor in
            do {
                let folder = try await Task.detached(priority: .userInitiated) {
                    try Self.createFolder(withCopiesOf: urls, in: parent)
                }.value
                finish(outputs: [folder], failures: 0, noun: "folder")
            } catch {
                setOperationStatus(.failed("Folder not created: \(error.localizedDescription)"), clearAfter: .seconds(5))
            }
        }
    }

    nonisolated static func createFolder(withCopiesOf urls: [URL], in parent: URL) throws -> URL {
        let folder = FileShelfDiskOperations.collisionSafeDestination(for: parent.appendingPathComponent("New Folder"), in: parent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            throw FileShelfDiskOperationError.operationFailed(error.localizedDescription)
        }
        do {
            _ = try FileShelfDiskOperations.copy(urls, to: folder)
        } catch {
            // Only the folder this call created (now empty after rollback) is removed.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    // MARK: Extract text

    /// On-device text recognition (Vision); the text goes to the clipboard.
    func extractText(from urls: [URL]) {
        let images = urls.filter(FileTrayActionTargets.isImage)
        guard !images.isEmpty else { return }
        setOperationStatus(.working("Reading text…"))
        Task { @MainActor in
            let text = await Task.detached(priority: .userInitiated) {
                images.compactMap { try? Self.recognizedText(in: $0) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            }.value
            guard !text.isEmpty else {
                setOperationStatus(.failed("No text found."), clearAfter: .seconds(4))
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            setOperationStatus(.succeeded("Text copied to the clipboard."), clearAfter: .seconds(3))
        }
    }

    nonisolated static func recognizedText(in url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(url: url).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: Outcome

    /// Adds outputs to the Tray, selects them and reports exactly what happened.
    private func finish(outputs: [URL], failures: Int, noun: String) {
        add(outputs)
        let accepted = outputs.map(\.standardizedFileURL).filter(files.contains)
        select(only: accepted)
        let notAdded = outputs.count - accepted.count
        switch (accepted.count, failures + notAdded) {
        case (0, _) where notAdded > 0:
            setOperationStatus(.failed("Created, but the Tray is full. Saved beside the original."), clearAfter: .seconds(5))
        case (0, _):
            setOperationStatus(.failed("Nothing was created. Originals preserved."), clearAfter: .seconds(5))
        case (let made, 0):
            setOperationStatus(.succeeded(made == 1 ? "Added \(noun) to the Tray." : "Added \(made) \(noun)s to the Tray."), clearAfter: .seconds(3))
        case (let made, let missed):
            setOperationStatus(.failed("Added \(made); \(missed) failed. Originals preserved."), clearAfter: .seconds(5))
        }
    }
}

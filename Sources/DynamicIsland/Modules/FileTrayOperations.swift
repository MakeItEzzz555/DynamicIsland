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
    // MARK: Convert

    func convertImages(_ urls: [URL], to format: FileConversionFormat) {
        let sources = urls.filter { FileConversionController.targetFormats(for: $0).contains(format) }
        guard !sources.isEmpty else {
            setOperationStatus(.failed("These files can’t be converted to \(format.displayName)."), clearAfter: .seconds(4))
            return
        }
        setOperationStatus(.working(sources.count == 1 ? "Converting to \(format.displayName)…" : "Converting \(sources.count) files…"))
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

    func convertAudio(_ url: URL, to format: FileAudioFormat) {
        setOperationStatus(.working("Converting to \(format.rawValue)…"))
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
        }
        if started == nil {
            setOperationStatus(.failed("The archive could not be started."), clearAfter: .seconds(4))
        } else {
            setOperationStatus(.working(urls.count == 1 ? "Creating ZIP…" : "Creating ZIP of \(urls.count) items…"))
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

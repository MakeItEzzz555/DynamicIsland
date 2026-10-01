import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Owned temporary area for files materialized from NSFilePromiseReceiver
/// (notably Photos.app). Direct Finder/Desktop URLs are never copied here.
struct FileDragPromiseStorage: Sendable {
    static let shared = FileDragPromiseStorage()

    let rootURL: URL

    init(
        rootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("DragPromises", isDirectory: true)
    ) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func makeDropDirectory() throws -> URL {
        let directory = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func isOwned(_ url: URL) -> Bool {
        let root = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(root)
    }

    func removeIfOwned(_ urls: [URL]) {
        let ownedDirectories = Set(urls.compactMap { url -> URL? in
            guard isOwned(url) else { return nil }
            return url.standardizedFileURL.deletingLastPathComponent()
        })
        for directory in ownedDirectories where isOwned(directory) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Native share/compose UIs can outlive our island. Keep materialized files
    /// available long enough for those UIs, then remove only our own temp data.
    func scheduleCleanup(_ urls: [URL], after seconds: TimeInterval = 3600) {
        let owned = urls.filter(isOwned)
        guard !owned.isEmpty else { return }
        Task.detached(priority: .utility) { [self] in
            let nanos = UInt64(max(seconds, 0) * 1_000_000_000)
            if nanos > 0 { try? await Task.sleep(nanoseconds: nanos) }
            removeIfOwned(owned)
        }
    }
}

/// AppKit-only bridge that recognizes both direct files and file promises but
/// deliberately never accepts a drop. It exists so a Photos/Finder drag can
/// cross the gaps between action circles without ending the session.
final class FileDragBridgeNSView: NSView {
    var onTargetingChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var types: [NSPasteboard.PasteboardType] = [.fileURL]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        registerForDraggedTypes(Array(Set(types)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender.draggingPasteboard) else { return [] }
        onTargetingChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onTargetingChanged?(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onTargetingChanged?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetingChanged?(false)
        return false
    }

    private func accepts(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ||
            pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
    }
}

struct FileDragBridgeView: NSViewRepresentable {
    @Binding var isTargeted: Bool

    func makeNSView(context: Context) -> FileDragBridgeNSView {
        let view = FileDragBridgeNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: FileDragBridgeNSView, context: Context) { configure(nsView) }

    private func configure(_ view: FileDragBridgeNSView) {
        view.onTargetingChanged = { targeted in
            DispatchQueue.main.async { isTargeted = targeted }
        }
    }
}

/// AppKit destination used instead of SwiftUI-only `onDrop` for action
/// circles. NSFilePromiseReceiver is required for reliable Photos.app drags.
final class FilePromiseDropNSView: NSView {
    var onTargetingChanged: ((Bool) -> Void)?
    var onDropStarted: (() -> Int?)?
    var onFilesReceived: ((Int, [URL]) -> Void)?
    var onMaterializationFailed: ((Int, String) -> Void)?

    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "DynamicIsland.FilePromiseDrop"
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let storage: FileDragPromiseStorage

    init(storage: FileDragPromiseStorage = .shared) {
        self.storage = storage
        super.init(frame: .zero)
        registerDragTypes()
    }

    required init?(coder: NSCoder) {
        storage = .shared
        super.init(coder: coder)
        registerDragTypes()
    }

    private func registerDragTypes() {
        var types: [NSPasteboard.PasteboardType] = [.fileURL]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        registerForDraggedTypes(Array(Set(types)))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender.draggingPasteboard) else { return [] }
        onTargetingChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepts(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetingChanged?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargetingChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let claim = onDropStarted?() else { return false }
        let pasteboard = sender.draggingPasteboard

        let directURLs = Self.directFileURLs(from: pasteboard)
        if !directURLs.isEmpty {
            onTargetingChanged?(false)
            guard directURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                onMaterializationFailed?(claim, "One or more dragged files are no longer available")
                return false
            }
            onFilesReceived?(claim, directURLs)
            return true
        }

        guard let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver], !receivers.isEmpty else {
            onTargetingChanged?(false)
            onMaterializationFailed?(claim, "The drag did not contain file URLs or materializable file promises")
            return false
        }

        do {
            let destination = try storage.makeDropDirectory()
            let group = DispatchGroup()
            let lock = NSLock()
            var ordered: [(receiver: Int, callback: Int, url: URL)] = []
            var errors: [String] = []

            for (index, receiver) in receivers.enumerated() {
                // AppKit invokes the reader once per promised filename, not
                // necessarily once per receiver. Balance DispatchGroup using
                // the receiver's advertised file count so multi-file promises
                // cannot over-leave the group.
                let expectedCallbacks = max(receiver.fileNames.count, 1)
                for _ in 0..<expectedCallbacks { group.enter() }
                var callbackIndex = 0
                receiver.receivePromisedFiles(
                    atDestination: destination,
                    options: [:],
                    operationQueue: promiseQueue
                ) { fileURL, error in
                    let currentCallback = lock.withLock { () -> Int in
                        defer { callbackIndex += 1 }
                        return callbackIndex
                    }
                    defer { group.leave() }
                    lock.withLock {
                        if let error {
                            errors.append(error.localizedDescription)
                        } else {
                            ordered.append((index, currentCallback, fileURL.standardizedFileURL))
                        }
                    }
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                self.onTargetingChanged?(false)
                let snapshot = lock.withLock { (ordered, errors) }
                let urls = snapshot.0
                    .sorted { lhs, rhs in
                        lhs.receiver == rhs.receiver ? lhs.callback < rhs.callback : lhs.receiver < rhs.receiver
                    }
                    .map(\.url)
                // Multi-file drags are fail-closed: silently sharing only a
                // successful subset would violate the user's exact payload.
                if !snapshot.1.isEmpty || urls.isEmpty {
                    self.storage.removeIfOwned(urls)
                    try? FileManager.default.removeItem(at: destination)
                    let detail = snapshot.1.first ?? "No promised files were produced"
                    self.onMaterializationFailed?(claim, detail)
                } else {
                    self.onFilesReceived?(claim, urls)
                }
            }
            return true
        } catch {
            onTargetingChanged?(false)
            onMaterializationFailed?(claim, error.localizedDescription)
            return false
        }
    }

    static func directFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []).compactMap { object -> URL? in
            if let url = object as? URL { return url.standardizedFileURL }
            if let url = object as? NSURL { return (url as URL).standardizedFileURL }
            return nil
        }
    }

    private func accepts(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return true
        }
        return pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
    }
}

struct FilePromiseDropTarget<Content: View>: NSViewRepresentable {
    let content: Content
    let onDropStarted: () -> Int?
    let onFilesReceived: (Int, [URL]) -> Void
    let onMaterializationFailed: (Int, String) -> Void
    @Binding var isTargeted: Bool

    init(
        isTargeted: Binding<Bool>,
        onDropStarted: @escaping () -> Int?,
        onFilesReceived: @escaping (Int, [URL]) -> Void,
        onMaterializationFailed: @escaping (Int, String) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        _isTargeted = isTargeted
        self.onDropStarted = onDropStarted
        self.onFilesReceived = onFilesReceived
        self.onMaterializationFailed = onMaterializationFailed
        self.content = content()
    }

    func makeNSView(context: Context) -> NSView {
        let dropView = FilePromiseDropNSView()
        configure(dropView)
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            host.topAnchor.constraint(equalTo: dropView.topAnchor),
            host.bottomAnchor.constraint(equalTo: dropView.bottomAnchor)
        ])
        return dropView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let dropView = nsView as? FilePromiseDropNSView else { return }
        configure(dropView)
        if let host = dropView.subviews.first as? NSHostingView<Content> {
            host.rootView = content
        }
    }

    private func configure(_ view: FilePromiseDropNSView) {
        view.onTargetingChanged = { targeted in
            DispatchQueue.main.async { isTargeted = targeted }
        }
        view.onDropStarted = onDropStarted
        view.onFilesReceived = onFilesReceived
        view.onMaterializationFailed = onMaterializationFailed
    }
}

import AppKit

/// Retains the native picker/service and only its own island hold until dismissal.
@MainActor
final class NativeFileSharingSession: NSObject, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private static var active: [UUID: NativeFileSharingSession] = [:]
    let id = UUID()
    private weak var layoutStore: IslandLayoutStore?
    private var anchor: NSView?
    private var picker: NSSharingServicePicker?
    private var service: NSSharingService?
    private(set) var finished = false

    init(layoutStore: IslandLayoutStore?, anchor: NSView?) {
        self.layoutStore = layoutStore
        self.anchor = anchor
        super.init()
        layoutStore?.setTransientInteraction(true, owner: .fileSharing(id))
        if let window = anchor?.window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowClosing), name: NSWindow.willCloseNotification, object: window)
        }
    }

    static func present(_ action: FileDragQuickAction, urls: [URL], anchor: NSView?, layoutStore: IslandLayoutStore?) -> FileDragActionOutcome {
        let files = urls.map(\.standardizedFileURL)
        guard files.allSatisfy({ $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }) else {
            return .failed("One or more dragged files are no longer available")
        }
        if action == .airDrop {
            return AirDropService.share(urls: files, fallbackRevealInFinder: false) ? .handedOff : .unavailable("AirDrop is unavailable")
        }
        if action == .share {
            guard let anchor, anchor.window != nil, !anchor.bounds.isEmpty else { return .failed("Share picker anchor is unavailable") }
            let session = NativeFileSharingSession(layoutStore: layoutStore, anchor: anchor)
            active[session.id] = session
            let picker = NSSharingServicePicker(items: files)
            session.picker = picker
            picker.delegate = session
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        } else {
            guard let service = NSSharingService(named: action == .messages ? .composeMessage : .composeEmail),
                  service.canPerform(withItems: files) else { return .unavailable("\(action.title) sharing is unavailable for these files") }
            let session = NativeFileSharingSession(layoutStore: layoutStore, anchor: anchor)
            active[session.id] = session
            session.service = service
            service.delegate = session
            service.perform(withItems: files)
        }
        return .handedOff
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        service = sharingService
        return self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if let service { self.service = service } else { finish() }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) { finish() }

    @objc private func windowClosing(_ notification: Notification) { cancel() }

    func cancel() { picker?.close(); finish() }

    func finish() {
        guard !finished else { return }
        finished = true
        NotificationCenter.default.removeObserver(self)
        layoutStore?.setTransientInteraction(false, owner: .fileSharing(id))
        picker?.delegate = nil; service?.delegate = nil
        picker = nil; service = nil; anchor = nil
        Self.active[id] = nil
    }

    static func cancelAll() { Array(active.values).forEach { $0.cancel() } }
}

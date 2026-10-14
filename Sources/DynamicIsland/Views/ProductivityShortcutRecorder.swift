import AppKit
import SwiftUI

struct ProductivityShortcutSettingsView: View {
    @ObservedObject var controller: ProductivityShortcutController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ProductivityShortcutAction.allCases) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    if controller.recordingAction == action {
                        ProductivityShortcutRecorder(record: controller.finishRecording, cancel: controller.cancelRecording)
                            .frame(width: 180, height: 26)
                        Button("Cancel") { controller.cancelRecording() }
                    } else {
                        Text(controller.bindings[action]?.title ?? "None").foregroundStyle(.secondary)
                        Button("Record…") { _ = controller.beginRecording(action) }
                            .disabled(controller.recordingAction != nil)
                        if controller.bindings[action] != nil {
                            Button("Clear") { _ = controller.assign(nil, to: action) }
                                .disabled(controller.recordingAction != nil)
                        }
                    }
                }
                if let failure = controller.failures[action] {
                    Text(failure).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Use at least two modifiers, including Command or Control. Press and release the combination; Escape or moving focus cancels. macOS reports some system conflicts, but shortcuts used inside other apps cannot all be detected.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Check Again") { controller.checkAgain() }.disabled(controller.recordingAction != nil)
        }
        .onDisappear { controller.cancelRecording() }
    }
}

struct ProductivityShortcutRecorder: NSViewRepresentable {
    let record: (ProductivityShortcutBinding) -> Bool
    let cancel: () -> Void
    func makeNSView(context: Context) -> ProductivityShortcutRecorderField {
        let field = ProductivityShortcutRecorderField(frame: .zero)
        field.record = record; field.cancel = cancel
        return field
    }
    func updateNSView(_ field: ProductivityShortcutRecorderField, context: Context) {
        field.record = record; field.cancel = cancel
    }
}

/// Captures one explicitly focused chord, never monitors global typing.
final class ProductivityShortcutRecorderField: NSTextField {
    var record: (ProductivityShortcutBinding) -> Bool = { _ in false }
    var cancel: () -> Void = {}
    private var pending: ProductivityShortcutBinding?
    private var ended = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        isEditable = false; isSelectable = false; alignment = .center
        stringValue = "Press shortcut…"; font = .systemFont(ofSize: NSFont.systemFontSize)
        focusRingType = .exterior
        setAccessibilityLabel("Record productivity shortcut")
        setAccessibilityHelp("Press at least two modifiers including Command or Control, then release the key. Escape cancels.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool {
        pending = nil
        if !ended { ended = true; cancel() }
        needsDisplay = true; return true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isKeyWindow == true else { return }
            self.window?.makeFirstResponder(self)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { pending = nil; ended = true; cancel(); return }
        if event.keyCode == 48 { pending = nil; ended = true; cancel(); window?.selectNextKeyView(self); return }
        guard !event.isARepeat, pending == nil else { return }
        let binding = ProductivityShortcutBinding(event: event)
        guard binding.isSupported else {
            stringValue = "Use two modifiers"; NSAccessibility.post(element: self, notification: .valueChanged); return
        }
        pending = binding
        ended = false
        stringValue = "Release " + binding.title
    }
    override func keyUp(with event: NSEvent) {
        guard let binding = pending, event.keyCode == binding.keyCode else { return }
        pending = nil
        if record(binding) {
            ended = true
            stringValue = binding.title
            window?.makeFirstResponder(nil)
        } else {
            stringValue = "Try another shortcut"
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
}

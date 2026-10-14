import AppKit
import Carbon

// Physical key positions; text entry is observed only while the native recorder is focused.
struct ProductivityShortcutBinding: Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: UInt32
    static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    static let supportedKeys: Set<UInt16> = Set(Array(0...50).filter { $0 != 36 && $0 != 48 } + [96,97,98,99,100,101,103,105,106,107,109,111,113,115,116,117,118,119,120,121,122,123,124,125,126])

    var isSupported: Bool {
        Self.supportedKeys.contains(keyCode) && modifiers & ~Self.allowedModifiers == 0 &&
        modifiers & UInt32(cmdKey | controlKey) != 0 && modifiers.nonzeroBitCount >= 2
    }
    init(keyCode: UInt16, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = event.keyCode
        modifiers = Self.carbonModifiers(event.modifierFlags)
    }
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.command, cmdKey), (.control, controlKey), (.option, optionKey), (.shift, shiftKey)] {
            if flags.contains(flag) { value |= UInt32(carbon) }
        }
        return value
    }
    @MainActor var title: String {
        let prefix = [(controlKey,"⌃"), (optionKey,"⌥"), (shiftKey,"⇧"), (cmdKey,"⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined()
        return prefix + keyLabel
    }
    @MainActor private var keyLabel: String {
        let special: [UInt16: String] = [49:"Space",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",115:"Home",116:"Page Up",117:"Forward Delete",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"]
        if let name = special[keyCode] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return "Key \(keyCode)" }
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "Key \(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return "Key \(keyCode)" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0, length = 0
        var text = [UniChar](repeating: 0, count: 4)
        let result = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask), &dead, text.count, &length, &text)
        return result == noErr && length > 0 ? String(utf16CodeUnits: text, count: length).uppercased() : "Key \(keyCode)"
    }
    @MainActor func conflicts(with menu: NSMenu) -> Bool {
        menu.items.contains { item in
            (!item.keyEquivalent.isEmpty && Self.carbonModifiers(item.keyEquivalentModifierMask) == modifiers &&
             item.keyEquivalent.uppercased() == keyLabel) || item.submenu.map { conflicts(with: $0) } == true
        }
    }
}

enum ProductivityShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case shelf, basket, clipboard
    var id: Self { self }
    var title: String { switch self { case .shelf: "Open Shelf"; case .basket: "Show Basket"; case .clipboard: "Open Clipboard" } }
}

@MainActor
protocol ProductivityShortcutRegistering: AnyObject, Sendable {
    var receive: ((UInt32, Bool) -> Void)? { get set }
    func register(_ binding: ProductivityShortcutBinding, id: UInt32) -> OSStatus
    func unregister(_ id: UInt32) -> OSStatus
    func stop() -> OSStatus
}

@MainActor
final class CarbonProductivityShortcuts: ProductivityShortcutRegistering {
    private static var nextSignature: OSType = 0x44495348
    private let context: Context
    var signature: OSType { context.signature }
    init() {
        context = Context(signature: Self.nextSignature)
        Self.nextSignature &+= 1
    }
    var receive: ((UInt32, Bool) -> Void)? {
        get { context.receive }
        set { context.receive = newValue }
    }
    func register(_ binding: ProductivityShortcutBinding, id: UInt32) -> OSStatus { context.register(binding, id: id) }
    func unregister(_ id: UInt32) -> OSStatus { context.unregister(id) }
    func stop() -> OSStatus { context.stop() }
    deinit {
        let context = context
        Task { @MainActor in _ = context.stop() }
    }

    @MainActor
    private final class Context {
        let signature: OSType
        init(signature: OSType) { self.signature = signature }
        var receive: ((UInt32, Bool) -> Void)?
        private var registrations: [UInt32: EventHotKeyRef] = [:]
        private var handler: EventHandlerRef?
        private var retainedContext: UnsafeMutableRawPointer?

        func register(_ binding: ProductivityShortcutBinding, id: UInt32) -> OSStatus {
            guard binding.isSupported, registrations[id] == nil else { return OSStatus(paramErr) }
            var reserved: Unmanaged<CFArray>?
            let checked = CopySymbolicHotKeys(&reserved)
            guard checked == noErr else { return checked }
            let values = reserved?.takeRetainedValue() as? [[String: Any]] ?? []
            if values.contains(where: {
                ($0[kHISymbolicHotKeyEnabled as String] as? Bool) == true &&
                ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint16Value == binding.keyCode &&
                ($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == binding.modifiers
            }) { return OSStatus(eventHotKeyExistsErr) }
            if handler == nil {
                var kinds = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                             EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
                let pointer = Unmanaged.passRetained(self).toOpaque()
                let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                    guard let event, let context else { return OSStatus(eventNotHandledErr) }
                    var key = EventHotKeyID()
                    guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                        MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr else { return OSStatus(eventNotHandledErr) }
                    let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                    return MainActor.assumeIsolated {
                        let owner = Unmanaged<Context>.fromOpaque(context).takeUnretainedValue()
                        guard key.signature == owner.signature, owner.registrations[key.id] != nil else { return OSStatus(eventNotHandledErr) }
                        owner.receive?(key.id, down)
                        return noErr
                    }
                }, kinds.count, &kinds, pointer, &handler)
                guard installed == noErr else { Unmanaged<Context>.fromOpaque(pointer).release(); return installed }
                retainedContext = pointer
            }
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(binding.keyCode), binding.modifiers,
                EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if result == noErr, let reference { registrations[id] = reference }
            return result
        }
        func unregister(_ id: UInt32) -> OSStatus {
            guard let reference = registrations[id] else { return noErr }
            let result = UnregisterEventHotKey(reference)
            if result == noErr { registrations[id] = nil }
            return result
        }
        func stop() -> OSStatus {
            var failure: OSStatus = noErr
            for id in Array(registrations.keys) {
                let result = unregister(id)
                if result != noErr { failure = result }
            }
            receive = nil
            if let handler {
                let removed = RemoveEventHandler(handler)
                guard removed == noErr else { return removed }
                self.handler = nil
            }
            if let pointer = retainedContext {
                retainedContext = nil
                Unmanaged<Context>.fromOpaque(pointer).release()
            }
            return failure
        }
    }
}

@MainActor
final class ProductivityShortcutController: ObservableObject {
    @Published private(set) var bindings: [ProductivityShortcutAction: ProductivityShortcutBinding] = [:]
    @Published private(set) var failures: [ProductivityShortcutAction: String] = [:]
    @Published private(set) var recordingAction: ProductivityShortcutAction?
    private let backend: any ProductivityShortcutRegistering
    private let perform: (ProductivityShortcutAction) -> String?
    private var active: [ProductivityShortcutAction: UInt32] = [:]
    private var pressed: Set<UInt32> = []
    private var nextID: UInt32 = 0

    init(backend: any ProductivityShortcutRegistering = CarbonProductivityShortcuts(), perform: @escaping (ProductivityShortcutAction) -> String?) {
        self.backend = backend; self.perform = perform
        backend.receive = { [weak self] id, down in self?.receive(id, down: down) }
    }
    @discardableResult
    func assign(_ binding: ProductivityShortcutBinding?, to action: ProductivityShortcutAction) -> Bool {
        guard binding == nil || binding?.isSupported == true else {
            failures[action] = "Use a supported key with at least two modifiers, including Command or Control."; return false
        }
        guard binding == nil || !bindings.contains(where: { $0.key != action && $0.value == binding }) else {
            failures[action] = "This shortcut is already assigned in DynamicIsland."; return false
        }
        if let binding, [EditMenuInstaller.makeEditMenu(), SettingsWindowController.makeWindowMenu(target: NSObject()), NSApplication.shared.mainMenu]
            .compactMap({ $0 }).contains(where: { binding.conflicts(with: $0) }) {
            failures[action] = "This shortcut is used by a DynamicIsland menu command."; return false
        }
        if bindings[action] == binding, active[action] != nil { return true }
        backend.receive = { [weak self] id, down in self?.receive(id, down: down) }
        if let binding {
            nextID &+= 1
            let candidate = nextID
            let result = backend.register(binding, id: candidate)
            guard result == noErr else { failures[action] = "macOS could not register this shortcut (\(result)). Existing binding is preserved."; return false }
            if let old = active[action], backend.unregister(old) != noErr {
                _ = backend.unregister(candidate)
                failures[action] = "The previous shortcut could not be released. Try again."; return false
            }
            if let old = active[action] { pressed.remove(old) }
            active[action] = candidate; bindings[action] = binding
        } else {
            if let old = active[action] {
                guard backend.unregister(old) == noErr else { failures[action] = "The shortcut could not be released. Try again."; return false }
                pressed.remove(old)
            }
            active[action] = nil; bindings[action] = nil
        }
        failures[action] = nil
        return true
    }
    @discardableResult
    func stop() -> Bool {
        let result = backend.stop()
        if result != noErr {
            for action in active.keys { failures[action] = "macOS could not release the shortcut (\(result))." }
        }
        active.removeAll(); pressed.removeAll()
        recordingAction = nil
        return result == noErr
    }
    func checkAgain() {
        guard recordingAction == nil, stop() else { return }
        resumeBindings()
    }
    @discardableResult
    func beginRecording(_ action: ProductivityShortcutAction) -> Bool {
        guard recordingAction == nil, stop() else { return false }
        recordingAction = action
        return true
    }
    @discardableResult
    func finishRecording(_ binding: ProductivityShortcutBinding) -> Bool {
        guard let action = recordingAction, assign(binding, to: action) else { return false }
        recordingAction = nil
        resumeBindings()
        return true
    }
    func cancelRecording() {
        guard recordingAction != nil else { return }
        recordingAction = nil
        resumeBindings()
    }
    private func resumeBindings() {
        for action in ProductivityShortcutAction.allCases {
            if let binding = bindings[action] { _ = assign(binding, to: action) }
        }
    }
    deinit {
        let backend = backend
        Task { @MainActor in _ = backend.stop() }
    }
    private func receive(_ id: UInt32, down: Bool) {
        guard recordingAction == nil else { return }
        guard let action = active.first(where: { $0.value == id })?.key else { return }
        if !down { pressed.remove(id); return }
        guard pressed.insert(id).inserted else { return }
        failures[action] = perform(action)
    }
}

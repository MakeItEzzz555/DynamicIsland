import AppKit
import Carbon
import XCTest
@testable import DynamicIsland

@MainActor
final class ProductivityGlobalShortcutTests: XCTestCase {
    @MainActor
    final class Backend: ProductivityShortcutRegistering {
        var receive: ((UInt32, Bool) -> Void)?
        var registered: [UInt32: ProductivityShortcutBinding] = [:]
        var registrations = 0, removals = 0
        var failRegistration = false
        var failRemoval: UInt32?
        func register(_ binding: ProductivityShortcutBinding, id: UInt32) -> OSStatus {
            registrations += 1
            if failRegistration { return OSStatus(eventHotKeyExistsErr) }
            registered[id] = binding; return noErr
        }
        func unregister(_ id: UInt32) -> OSStatus {
            removals += 1
            if failRemoval == id { return OSStatus(paramErr) }
            registered[id] = nil; return noErr
        }
        func stop() -> OSStatus { registered.removeAll(); receive = nil; return noErr }
    }
    let a = ProductivityShortcutBinding(keyCode: 0, modifiers: UInt32(cmdKey | optionKey))
    let b = ProductivityShortcutBinding(keyCode: 11, modifiers: UInt32(controlKey | optionKey))

    func testValidationAndInternalConflictCannotReplaceBinding() {
        let backend = Backend()
        let actual = ProductivityShortcutController(backend: backend) { _ in nil }
        XCTAssertFalse(actual.assign(.init(keyCode: 0, modifiers: UInt32(cmdKey)), to: .shelf))
        XCTAssertFalse(actual.assign(.init(keyCode: 53, modifiers: UInt32(cmdKey | optionKey)), to: .shelf))
        XCTAssertFalse(actual.assign(.init(keyCode: 0, modifiers: UInt32(cmdKey | optionKey) | (1 << 31)), to: .shelf))
        XCTAssertFalse(actual.assign(.init(keyCode: 3, modifiers: UInt32(cmdKey | controlKey)), to: .shelf), "Fullscreen is an existing native command")
        XCTAssertFalse(actual.assign(.init(keyCode: 6, modifiers: UInt32(cmdKey | shiftKey)), to: .shelf), "Redo must retain its native chord")
        XCTAssertTrue(actual.assign(a, to: .shelf))
        XCTAssertFalse(actual.assign(a, to: .clipboard))
        XCTAssertNil(actual.bindings[.clipboard])
        XCTAssertEqual(backend.registrations, 1)
        XCTAssertNotNil(actual.failures[.clipboard])
    }

    func testOnePressAndStaleGenerationsAfterReplacementStopAndResume() {
        let backend = Backend(); var actions: [ProductivityShortcutAction] = []
        let controller = ProductivityShortcutController(backend: backend) { actions.append($0); return nil }
        XCTAssertTrue(controller.assign(a, to: .shelf))
        let old = try! XCTUnwrap(backend.registered.keys.first)
        backend.receive?(old, true); backend.receive?(old, true)
        XCTAssertEqual(actions, [.shelf])
        backend.receive?(old, false); backend.receive?(old, true)
        XCTAssertEqual(actions, [.shelf, .shelf])
        XCTAssertTrue(controller.assign(b, to: .shelf))
        let current = try! XCTUnwrap(backend.registered.keys.first)
        XCTAssertNotEqual(current, old)
        backend.receive?(old, true); backend.receive?(current, true)
        XCTAssertEqual(actions.count, 3)
        let retiredReceiver = backend.receive
        XCTAssertTrue(controller.stop())
        retiredReceiver?(current, true)
        XCTAssertEqual(actions.count, 3)
        XCTAssertTrue(controller.assign(b, to: .shelf))
        backend.receive?(try! XCTUnwrap(backend.registered.keys.first), true)
        XCTAssertEqual(actions.count, 4)
    }

    func testFailedRegistrationPreservesWorkingBindingAndFailedRemovalRollsBackCandidate() {
        let backend = Backend()
        let actual = ProductivityShortcutController(backend: backend) { _ in "Protected interaction" }
        XCTAssertTrue(actual.assign(a, to: .shelf))
        let old = try! XCTUnwrap(backend.registered.keys.first)
        backend.failRegistration = true
        XCTAssertFalse(actual.assign(b, to: .shelf))
        XCTAssertEqual(actual.bindings[.shelf], a)
        XCTAssertEqual(backend.registered.count, 1)
        backend.failRegistration = false; backend.failRemoval = old
        XCTAssertFalse(actual.assign(b, to: .shelf))
        XCTAssertEqual(backend.registered, [old: a])
        backend.receive?(old, true)
        XCTAssertEqual(actual.failures[.shelf], "Protected interaction")
    }

    func testRecorderSuspendsExistingBindingsAndEscapeRestoresThem() {
        let backend = Backend(); var actions = 0
        let controller = ProductivityShortcutController(backend: backend) { _ in actions += 1; return nil }
        XCTAssertTrue(controller.assign(a, to: .shelf))
        let receiver = backend.receive, oldID = try! XCTUnwrap(backend.registered.keys.first)
        XCTAssertTrue(controller.beginRecording(.clipboard))
        XCTAssertTrue(backend.registered.isEmpty)
        receiver?(oldID, true); XCTAssertEqual(actions, 0)
        controller.cancelRecording()
        XCTAssertEqual(controller.bindings, [.shelf: a])
        XCTAssertEqual(backend.registered.count, 1)
        XCTAssertTrue(controller.beginRecording(.clipboard))
        XCTAssertFalse(controller.finishRecording(a))
        XCTAssertEqual(controller.recordingAction, .clipboard)
        XCTAssertTrue(controller.finishRecording(b))
        XCTAssertNil(controller.recordingAction)
        XCTAssertEqual(backend.registered.count, 2)
    }

    func testDeallocationUnregistersBindings() async {
        let backend = Backend()
        var controller: ProductivityShortcutController? = .init(backend: backend) { _ in nil }
        XCTAssertTrue(controller!.assign(a, to: .shelf))
        controller = nil
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(backend.registered.isEmpty)
    }

    func testPublicCarbonRegistrationRoutesOnlyExactInstanceAndUnregisters() throws {
        _ = NSApplication.shared
        let first = CarbonProductivityShortcuts(), second = CarbonProductivityShortcuts()
        defer { _ = first.stop(); _ = second.stop() }
        let rare = ProductivityShortcutBinding(keyCode: 105, modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        let other = ProductivityShortcutBinding(keyCode: 106, modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        XCTAssertEqual(first.register(rare, id: 90), noErr)
        XCTAssertEqual(second.register(other, id: 90), noErr)
        var firstEvents = 0, secondEvents: [Bool] = []
        first.receive = { _, _ in firstEvents += 1 }
        second.receive = { _, down in secondEvents.append(down) }
        func send(signature: OSType, kind: UInt32) throws {
            var event: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), kind, 0, EventAttributes(kEventAttributeNone), &event), noErr)
            let value = try XCTUnwrap(event); defer { ReleaseEvent(value) }
            var key = EventHotKeyID(signature: signature, id: 90)
            XCTAssertEqual(SetEventParameter(value, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &key), noErr)
            XCTAssertEqual(SendEventToEventTarget(value, GetApplicationEventTarget()), noErr)
        }
        try send(signature: second.signature, kind: UInt32(kEventHotKeyPressed))
        try send(signature: second.signature, kind: UInt32(kEventHotKeyReleased))
        XCTAssertEqual(firstEvents, 0)
        XCTAssertEqual(secondEvents, [true, false])
        XCTAssertEqual(second.unregister(90), noErr)
        XCTAssertEqual(first.stop(), noErr)
        XCTAssertEqual(second.register(rare, id: 91), noErr, "The first backend must release its actual native registration")
    }

    func testHostedNativeRecorderReceivesWindowEventsWithoutGlobalInput() async throws {
        _ = NSApplication.shared
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        let window = NSWindow(contentRect: .init(x: 100, y: 100, width: 300, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); NSApp.setActivationPolicy(policy) }
        let field = ProductivityShortcutRecorderField(frame: .init(x: 20, y: 30, width: 250, height: 26))
        let content = NSView(frame: .init(x: 0, y: 0, width: 300, height: 100)); content.addSubview(field)
        window.contentView = content; window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(field))
        var captured: [ProductivityShortcutBinding] = []
        field.record = { captured.append($0); return true }
        let pointerBefore = NSEvent.mouseLocation
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [.command, .option], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        }
        window.sendEvent(event(.keyDown))
        XCTAssertTrue(captured.isEmpty)
        window.sendEvent(event(.keyUp))
        XCTAssertEqual(captured, [a])
        XCTAssertEqual(NSEvent.mouseLocation, pointerBefore)
        XCTAssertEqual(field.accessibilityLabel(), "Record productivity shortcut")
    }

    func testProductivityPresentationRejectsEveryProtectedOwnerIncludingCamera() {
        let layout = IslandLayoutStore()
        func permitted() -> Bool {
            layout.productivityPresentationAllowed(exactApproval: false, interactiveHUD: false, nativeInteraction: false, fileDrag: false)
        }
        XCTAssertTrue(permitted())
        for owner in [TransientInteractionOwner.cameraNavigation(UUID()), .workspaceEditor, .fileActionPanel(UUID())] {
            layout.setTransientInteraction(true, owner: owner); XCTAssertFalse(permitted())
            layout.setTransientInteraction(false, owner: owner)
        }
        for protected in 0..<4 {
            XCTAssertFalse(layout.productivityPresentationAllowed(exactApproval: protected == 0,
                interactiveHUD: protected == 1, nativeInteraction: protected == 2, fileDrag: protected == 3))
        }
        layout.setTextInputFocused(true); XCTAssertFalse(permitted())
        layout.setTextInputFocused(false); layout.collapsedMessageInteractionProtected = true
        XCTAssertFalse(permitted())
    }

    func testNativeRecorderCommitsOnReleaseExactlyOnceAndEscapeNeverRecords() {
        var captured: [ProductivityShortcutBinding] = [], cancellations = 0
        let field = ProductivityShortcutRecorderField(frame: .init(x: 0, y: 0, width: 180, height: 26))
        field.record = { captured.append($0); return true }; field.cancel = { cancellations += 1 }
        func event(_ type: NSEvent.EventType, code: UInt16 = 0, repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
                windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: repeatKey, keyCode: code)!
        }
        field.keyDown(with: event(.keyDown)); field.keyDown(with: event(.keyDown, repeatKey: true))
        XCTAssertTrue(captured.isEmpty)
        field.keyUp(with: event(.keyUp)); field.keyUp(with: event(.keyUp))
        XCTAssertEqual(captured, [a])
        field.keyDown(with: event(.keyDown)); field.keyDown(with: event(.keyDown, code: 53))
        field.keyUp(with: event(.keyUp))
        XCTAssertEqual(captured, [a]); XCTAssertEqual(cancellations, 1)
    }
}

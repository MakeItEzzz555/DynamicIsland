// Native whole-app acceptance driver. Compile with xcrun swiftc; no app changes.
// Never grants permission, selects an approval, or changes system preferences.
import AppKit
import ApplicationServices
import Darwin
import Foundation

enum DriverError: Error { case invalidArguments, unavailableApp, inaccessible, missingControl(String), usage(Int32) }
do {
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, let pid = Int32(args[0]) else { throw DriverError.invalidArguments }
let output = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == "com.local.dynamicisland" else { throw DriverError.unavailableApp }
guard AXIsProcessTrusted() else { throw DriverError.inaccessible }
let root = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(root, 1)
let began = ProcessInfo.processInfo.systemUptime
var samples: [[String: Any]] = []
var cycles: [[String: Any]] = []

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, key as CFString, &value)
    return value
}
func find(_ label: String, in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    guard depth < 14 else { return nil }
    for key in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute] {
        if attribute(element, key) as? String == label { return element }
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let found = find(label, in: child, depth: depth + 1) { return found }
    }
    return nil
}
func persist() throws {
    let report: [String: Any] = ["pid": pid, "classification": "real packaged-app workload; inspect results before acceptance",
        "elapsedSeconds": ProcessInfo.processInfo.systemUptime - began, "samples": samples, "cycles": cycles]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.appendingPathComponent("memory.json"), options: .atomic)
}
func sample(_ label: String) throws {
    guard !app.isTerminated else { throw DriverError.unavailableApp }
    var usage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &usage) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard result == 0 else { throw DriverError.usage(errno) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", String(pid), "-o", "rss=,%cpu="]
    let pipe = Pipe(); process.standardOutput = pipe
    try process.run(); process.waitUntilExit()
    let ps = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard process.terminationStatus == 0, ps.count == 2, let rss = UInt64(ps[0]), let cpu = Double(ps[1]) else { throw DriverError.unavailableApp }
    let row: [String: Any] = ["label": label, "elapsedSeconds": ProcessInfo.processInfo.systemUptime - began,
        "rssKiB": rss, "cpuPercent": cpu, "residentBytes": usage.ri_resident_size,
        "physicalFootprintBytes": usage.ri_phys_footprint,
        "windows": (attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).count,
        "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
    samples.append(row); try persist()
    print("MEMORY \(row)"); fflush(stdout)
}
func move(_ point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func click(_ point: CGPoint) {
    move(point)
    for count in [1, 2] {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            event?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.03)
        }
    }
}
func escape() {
    for down in [true, false] {
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
    }
}
func expanded() throws {
    guard let screen = NSScreen.screens.first else { throw DriverError.unavailableApp }
    // An attention event can already have expanded the island while the mouse
    // is outside. Enter it before navigation so normal mouse-exit collapse
    // cannot race this driver's next action.
    if find("Show Tools page", in: root) != nil {
        move(CGPoint(x: screen.frame.midX, y: 100))
        Thread.sleep(forTimeInterval: 0.15)
        return
    }
    // Hardware-notch right wing, matching the controlled acceptance workload.
    // Run without simultaneous user pointer input; a missing endpoint aborts.
    let point = CGPoint(x: screen.frame.midX + 100, y: 22)
    move(point); Thread.sleep(forTimeInterval: 0.4); click(point)
    for _ in 0..<25 {
        if find("Show Tools page", in: root) != nil { move(CGPoint(x: screen.frame.midX, y: 100)); return }
        Thread.sleep(forTimeInterval: 0.08)
    }
    throw DriverError.missingControl("Show Tools page (expand)")
}
func collapse() throws {
    app.activate(); Thread.sleep(forTimeInterval: 0.15)
    // Never send Escape into another application or a system consent dialog.
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw DriverError.inaccessible }
    for window in attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        guard attribute(window, kAXModalAttribute) as? Bool != true else { throw DriverError.inaccessible }
    }
    escape(); move(CGPoint(x: 950, y: 500))
    Thread.sleep(forTimeInterval: 0.9)
}
try sample("initial")
try collapse(); Thread.sleep(forTimeInterval: 20); try sample("idleBaseline")
for batch in 1...3 {
    for cycle in 1...20 {
        let start = ProcessInfo.processInfo.systemUptime
        do {
            try expanded()
            for label in ["Show Agents page", "Show Island page", "Show Tools page"] {
                guard let control = find(label, in: root), AXUIElementPerformAction(control, kAXPressAction as CFString) == .success else {
                    throw DriverError.missingControl(label)
                }
                Thread.sleep(forTimeInterval: 0.65)
            }
            try collapse()
            cycles.append(["batch": batch, "cycle": cycle, "completed": true, "seconds": ProcessInfo.processInfo.systemUptime - start])
        } catch {
            cycles.append(["batch": batch, "cycle": cycle, "completed": false, "error": String(describing: error)])
            try persist()
            // Stop on interference/modal/missing controls; never count a fake cycle.
            throw error
        }
        if cycle.isMultiple(of: 10) { try sample("batch\(batch)-cycle\(cycle)") }
    }
    Thread.sleep(forTimeInterval: 20); try sample("batch\(batch)-idle")
}
try collapse(); try sample("postCleanup")
Thread.sleep(forTimeInterval: 60); try sample("finalIdle")
} catch {
    FileHandle.standardError.write(Data("Acceptance driver stopped: \(error)\n".utf8))
    exit(1)
}

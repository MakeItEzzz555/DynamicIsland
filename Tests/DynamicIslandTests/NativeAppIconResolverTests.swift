import AppKit
import XCTest
@testable import DynamicIsland

@MainActor
final class NativeAppIconResolverTests: XCTestCase {
    func testSemanticMappingsAreIndependentOfInstalledApplications() {
        XCTAssertEqual(NativeAppIdentity.widget(.timer), .clock)
        XCTAssertEqual(NativeAppIdentity.widget(.calendar), .calendar)
        XCTAssertEqual(NativeAppIdentity.widget(.codexUsage), .codex)
        XCTAssertEqual(NativeAppIdentity.widget(.claudeUsage), .claude)
        XCTAssertEqual(NativeAppIdentity.clock.bundleIdentifier, "com.apple.clock")
        XCTAssertEqual(NativeAppIdentity.calendar.bundleIdentifier, "com.apple.iCal")
        XCTAssertEqual(NativeAppIdentity.safari.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(NativeAppIdentity.finder.bundleIdentifier, "com.apple.finder")
        let excluded: [IslandWidget] = [.files, .clipboard, .shortcuts, .activities, .media]
        for widget in excluded {
            XCTAssertNil(NativeAppIdentity.widget(widget))
        }
    }

    func testUnavailableApplicationsAreCachedAndRetainSFFallback() {
        var lookups = 0
        let resolver = NativeAppIconResolver(applicationURL: { _ in lookups += 1; return nil },
                                             iconAtURL: { _ in XCTFail("Missing apps must not ask for an icon"); return NSImage() })
        XCTAssertNil(resolver.installedIcon(for: IslandWidget.timer))
        XCTAssertNil(resolver.installedIcon(for: NativeAppIdentity.clock))
        XCTAssertEqual(lookups, 1)
        XCTAssertEqual(IslandWidget.timer.symbol, "timer")
        XCTAssertNil(resolver.installedIcon(for: IslandWidget.files))
        XCTAssertEqual(lookups, 1)
    }

    func testInstalledIconsAreCachedAndUntinted() {
        var lookups = 0
        var reads = 0
        let source = NSImage(size: NSSize(width: 32, height: 32))
        source.isTemplate = true
        let resolver = NativeAppIconResolver(applicationURL: { bundle in
            lookups += 1
            XCTAssertEqual(bundle, "com.anthropic.claudefordesktop")
            return URL(fileURLWithPath: "/Applications/SampleClaude.app")
        }, iconAtURL: { _ in reads += 1; return source })
        let first = resolver.installedIcon(for: NativeAppIdentity.claude)
        let second = resolver.installedIcon(for: NativeAppIdentity.claude)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        XCTAssertFalse(first?.isTemplate ?? true)
        XCTAssertTrue(source.isTemplate, "Do not mutate NSWorkspace's original image")
        XCTAssertEqual(lookups, 1)
        XCTAssertEqual(reads, 1)
    }
}

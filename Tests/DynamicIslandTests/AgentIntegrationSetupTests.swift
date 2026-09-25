import Foundation
import XCTest
@testable import DynamicIsland

final class AgentIntegrationSetupTests: XCTestCase {
    func testCodexInstallPreservesUnrelatedConfigurationAndHooks() throws {
        let original: [String: Any] = [
            "description": "keep me",
            "custom": ["enabled": true],
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/usr/bin/true"]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: original)
        let helper = URL(fileURLWithPath: "/Applications/Dynamic Island.app/Contents/Helpers/DynamicIslandCodexHookRelay")
        let installed = try AgentHookConfigurationPlanner.install(
            existing: data,
            provider: .codex,
            helperURL: helper
        )
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: installed) as? [String: Any])
        XCTAssertEqual(root["description"] as? String, "keep me")
        XCTAssertNotNil(root["custom"])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let preTool = try XCTUnwrap(hooks["PreToolUse"] as? [Any])
        XCTAssertTrue(preTool.contains { raw in
            guard let group = raw as? [String: Any],
                  let handlers = group["hooks"] as? [Any] else { return false }
            return handlers.contains {
                (($0 as? [String: Any])?["command"] as? String) == "/usr/bin/true"
            }
        })
        XCTAssertEqual(
            try AgentHookConfigurationPlanner.configurationState(
                existing: installed,
                provider: .codex,
                helperURL: helper
            ),
            .configured
        )
    }

    func testInstallIsIdempotentAndRepairsOldHelperPath() throws {
        let old = URL(fileURLWithPath: "/Old/DynamicIsland.app/Contents/Helpers/DynamicIslandClaudeHookRelay")
        let current = URL(fileURLWithPath: "/Applications/DynamicIsland.app/Contents/Helpers/DynamicIslandClaudeHookRelay")
        let first = try AgentHookConfigurationPlanner.install(existing: nil, provider: .claude, helperURL: old)
        XCTAssertEqual(
            try AgentHookConfigurationPlanner.configurationState(existing: first, provider: .claude, helperURL: current),
            .repairRequired
        )
        let repaired = try AgentHookConfigurationPlanner.install(existing: first, provider: .claude, helperURL: current)
        let twice = try AgentHookConfigurationPlanner.install(existing: repaired, provider: .claude, helperURL: current)
        XCTAssertEqual(try canonicalJSONObject(repaired), try canonicalJSONObject(twice))
        XCTAssertEqual(
            try AgentHookConfigurationPlanner.configurationState(existing: twice, provider: .claude, helperURL: current),
            .configured
        )
    }

    func testRemoveDeletesOnlyDynamicIslandHandlers() throws {
        let helper = URL(fileURLWithPath: "/Apps/DynamicIsland.app/Contents/Helpers/DynamicIslandCodexHookRelay")
        let installed = try AgentHookConfigurationPlanner.install(existing: nil, provider: .codex, helperURL: helper)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: installed) as? [String: Any])
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        hooks["CustomEvent"] = [["hooks": [["type": "command", "command": "/usr/bin/true"]]]]
        root["hooks"] = hooks
        let mixed = try JSONSerialization.data(withJSONObject: root)
        let removed = try AgentHookConfigurationPlanner.remove(existing: mixed, provider: .codex)
        let result = try XCTUnwrap(try JSONSerialization.jsonObject(with: removed) as? [String: Any])
        let resultHooks = try XCTUnwrap(result["hooks"] as? [String: Any])
        XCTAssertNotNil(resultHooks["CustomEvent"])
        XCTAssertFalse(String(data: removed, encoding: .utf8)?.contains("DynamicIslandCodexHookRelay") ?? true)
    }

    func testMalformedOrInvalidHookShapeFailsClosed() throws {
        XCTAssertThrowsError(
            try AgentHookConfigurationPlanner.install(
                existing: Data("{bad".utf8),
                provider: .codex,
                helperURL: URL(fileURLWithPath: "/tmp/DynamicIslandCodexHookRelay")
            )
        )
        let wrongShape = try JSONSerialization.data(withJSONObject: ["hooks": "not-an-object"])
        XCTAssertThrowsError(
            try AgentHookConfigurationPlanner.install(
                existing: wrongShape,
                provider: .claude,
                helperURL: URL(fileURLWithPath: "/tmp/DynamicIslandClaudeHookRelay")
            )
        )
    }

    func testApplyCreatesBackupAndRollbackRestoresExactOriginalBytes() throws {
        let fixture = try Fixture()
        let target = fixture.paths.configURL(for: .claude)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("{\n  \"custom\" : true\n}\n".utf8)
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)

        let service = AgentIntegrationSetupService(paths: fixture.paths)
        let applied = try service.apply(.claude)
        XCTAssertEqual(applied.state, .configured)
        XCTAssertTrue(applied.backupAvailable)
        XCTAssertNotEqual(try Data(contentsOf: target), original)

        let rolledBack = try service.rollback(.claude)
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertFalse(rolledBack.backupAvailable)
        let permissions = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o640)
    }

    func testRollbackRefusesToClobberExternalEdit() throws {
        let fixture = try Fixture()
        let service = AgentIntegrationSetupService(paths: fixture.paths)
        _ = try service.apply(.codex)
        let target = fixture.paths.configURL(for: .codex)
        var changed = try Data(contentsOf: target)
        changed.append(contentsOf: [0x20, 0x0A])
        try changed.write(to: target, options: [.atomic])

        XCTAssertThrowsError(try service.rollback(.codex)) { error in
            XCTAssertEqual(error as? AgentIntegrationSetupError, .changedExternally)
        }
    }

    func testApplyToAbsentFileRollsBackByDeletingOwnedCreatedFile() throws {
        let fixture = try Fixture()
        let service = AgentIntegrationSetupService(paths: fixture.paths)
        let target = fixture.paths.configURL(for: .codex)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        _ = try service.apply(.codex)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        _ = try service.rollback(.codex)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testSymlinkConfigurationIsRejectedWithoutTouchingDestination() throws {
        let fixture = try Fixture()
        let target = fixture.paths.configURL(for: .claude)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let victim = fixture.root.appendingPathComponent("victim.json")
        let original = Data("{\"safe\":true}".utf8)
        try original.write(to: victim)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: victim)

        let service = AgentIntegrationSetupService(paths: fixture.paths)
        let snapshot = service.snapshot(for: .claude)
        if case .blocked = snapshot.state {
            // expected
        } else {
            XCTFail("Expected blocked symlink state, got \(snapshot.state)")
        }
        XCTAssertThrowsError(try service.apply(.claude))
        XCTAssertEqual(try Data(contentsOf: victim), original)
    }

    func testPreviewUsesQuotedAbsoluteHelperAndDoesNotExposeCredentials() throws {
        let fixture = try Fixture(bundleName: "Dynamic Island's Build.app")
        let service = AgentIntegrationSetupService(paths: fixture.paths)
        let preview = try service.preview(for: .codex)
        XCTAssertTrue(preview.text.contains("DynamicIslandCodexHookRelay"))
        XCTAssertTrue(preview.text.contains("'\\''"))
        XCTAssertFalse(preview.text.lowercased().contains("token"))
        XCTAssertFalse(preview.text.lowercased().contains("secret"))
    }

    private func canonicalJSONObject(_ data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: canonical, encoding: .utf8))
    }
}

private struct Fixture {
    let root: URL
    let paths: AgentIntegrationSetupPaths

    init(bundleName: String = "DynamicIsland.app") throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-setup-" + UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let bundle = root.appendingPathComponent(bundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        for helper in ["DynamicIslandCodexHookRelay", "DynamicIslandClaudeHookRelay"] {
            let url = bundle.appendingPathComponent("Contents/Helpers/" + helper)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }

        paths = AgentIntegrationSetupPaths(
            homeDirectory: home,
            applicationSupportDirectory: support,
            appBundleURL: bundle
        )
    }
}

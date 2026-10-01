import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class BackgroundOperationCenterSnapshotTests: XCTestCase {
    func testRenderBackgroundOperationCenterStates() throws {
        guard let raw = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_BACKGROUND_OPERATION_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_BACKGROUND_OPERATION_SNAPSHOT_DIR to render operation screenshots.")
        }
        let output = URL(fileURLWithPath: raw, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let scenarios: [(String, [BackgroundOperation], Bool)] = [
            ("01-idle", [], false),
            ("02-preparing", [operation(state: .preparing, progress: .indeterminate)], false),
            ("03-indeterminate", [operation(state: .running, progress: .indeterminate)], false),
            ("04-progress-25", [operation(state: .running, progress: .determinate(0.25))], false),
            ("05-progress-50", [operation(state: .running, progress: .determinate(0.50))], false),
            ("06-progress-90", [operation(state: .running, progress: .determinate(0.90))], false),
            ("07-completed", [operation(state: .completed, progress: .determinate(1))], false),
            ("08-failed", [operation(state: .failed, progress: .indeterminate)], false),
            ("09-cancelled", [operation(state: .cancelled, progress: .indeterminate)], false),
            (
                "10-two-simultaneous",
                [
                    operation(state: .running, progress: .indeterminate, title: "Compressing 3 items"),
                    operation(state: .preparing, progress: .indeterminate, title: "Compressing Photos")
                ],
                false
            ),
            ("11-reduce-motion", [operation(state: .running, progress: .determinate(0.50))], true)
        ]

        for (name, operations, reduceMotion) in scenarios {
            let controller = BackgroundOperationController(
                liveActivities: LiveActivityStore(),
                initialOperations: operations
            )
            let scene = ZStack {
                Color.black
                VStack(spacing: 8) {
                    if operations.isEmpty {
                        Text("No background operations")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.42))
                    } else {
                        BackgroundOperationCenterView(
                            controller: controller,
                            reduceMotion: reduceMotion
                        )
                    }
                }
                .padding(16)
            }
            .frame(width: 420, height: 84)
            .preferredColorScheme(.dark)

            try render(
                scene,
                size: CGSize(width: 420, height: 84),
                to: output.appendingPathComponent(name + ".png")
            )
        }
    }

    private func operation(
        state: BackgroundOperationState,
        progress: BackgroundOperationProgress,
        title: String = "Compressing Archive"
    ) -> BackgroundOperation {
        let now = Date()
        let output = URL(fileURLWithPath: "/tmp/Archive.zip")
        return BackgroundOperation(
            id: UUID(),
            generation: UUID(),
            kind: .compression,
            title: title,
            subtitle: state == .completed ? "Archive.zip" : nil,
            sources: [URL(fileURLWithPath: "/tmp/source")],
            destination: output,
            state: state,
            progress: progress,
            createdAt: now.addingTimeInterval(-2),
            startedAt: state == .queued ? nil : now.addingTimeInterval(-1),
            completedAt: state.isTerminal ? now : nil,
            failure: state == .failed
                ? BackgroundOperationFailure(code: .operationFailed, message: "Compression failed")
                : nil,
            result: state == .completed
                ? BackgroundOperationResult(outputURL: output)
                : nil,
            supportsCancellation: state.isActive
        )
    }

    private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not allocate render for \(url.lastPathComponent)")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Could not render \(url.lastPathComponent)")
            return
        }
        try png.write(to: url, options: .atomic)
    }
}


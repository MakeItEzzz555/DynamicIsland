import AppKit
import SwiftUI

struct BackgroundOperationCenterView: View {
    @ObservedObject var controller: BackgroundOperationController
    let reduceMotion: Bool

    var body: some View {
        if let operation = controller.primaryOperation {
            HStack(spacing: 10) {
                operationIcon(operation)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(operation.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .lineLimit(1)

                        if controller.activeCount > 1 {
                            Text("\(controller.activeCount) active")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.08), in: Capsule())
                        }
                    }

                    statusRow(operation)
                }

                Spacer(minLength: 4)

                trailingActions(operation)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: operation.state)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Background operation")
        }
    }

    @ViewBuilder
    private func operationIcon(_ operation: BackgroundOperation) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 30, height: 30)

            if operation.state.isActive {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: symbol(for: operation.state))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ operation: BackgroundOperation) -> some View {
        HStack(spacing: 6) {
            if case .determinate(let progress) = operation.progress,
               operation.state.isActive || operation.state == .completed {
                ProgressView(value: min(max(progress, 0), 1))
                    .frame(maxWidth: 88)
                    .accessibilityLabel("Operation progress")
                    .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
            }

            Text(operation.statusText)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(operation.state == .failed ? Color.orange : Color.white.opacity(0.56))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func trailingActions(_ operation: BackgroundOperation) -> some View {
        if operation.state.isActive && operation.supportsCancellation {
            Button("Cancel") {
                controller.cancel(operation.id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .accessibilityLabel("Cancel \(operation.title)")
        } else if let output = operation.result?.outputURL {
            HStack(spacing: 7) {
                Button {
                    NSWorkspace.shared.open(output)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open")
                .accessibilityLabel("Open \(output.lastPathComponent)")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                .accessibilityLabel("Show \(output.lastPathComponent) in Finder")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.76))
        } else if operation.state.isTerminal {
            Button {
                controller.clearFinished()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Clear finished operations")
            .accessibilityLabel("Clear finished operations")
            .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func symbol(for state: BackgroundOperationState) -> String {
        switch state {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        case .queued, .preparing, .running: "archivebox"
        }
    }
}

import SwiftUI

struct TerminalSessionView: View {
    @ObservedObject var controller: TerminalSessionController
    @State private var command = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Command", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(run)

                if controller.isRunning {
                    Button("Stop") {
                        controller.terminate()
                    }
                } else {
                    Button("Run", action: run)
                        .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            ScrollView {
                Text(controller.output.isEmpty ? "No output yet." : controller.output)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .frame(minHeight: 110, maxHeight: 180)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Label(controller.statusText, systemImage: controller.isRunning ? "terminal.fill" : "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(controller.workingDirectoryPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func run() {
        let value = command
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try controller.run(command: value)
            command = ""
        } catch {
            // The capability snapshot and status surface the concrete failure.
        }
    }
}

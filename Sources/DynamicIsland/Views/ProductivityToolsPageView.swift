import SwiftUI

enum ProductivityTool: String, CaseIterable, Identifiable {
    case keepAwake
    case windowSnap
    case voice
    case camera
    case backgroundRemoval
    case reminders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepAwake: "Keep Awake"
        case .windowSnap: "Snap"
        case .voice: "Voice"
        case .camera: "Camera"
        case .backgroundRemoval: "Remove BG"
        case .reminders: "Reminders"
        }
    }

    var symbolName: String {
        switch self {
        case .keepAwake: "cup.and.saucer.fill"
        case .windowSnap: "rectangle.split.2x1"
        case .voice: "mic.fill"
        case .camera: "camera.fill"
        case .backgroundRemoval: "person.crop.rectangle"
        case .reminders: "checklist"
        }
    }

    var capabilityID: IslandCapabilityID {
        switch self {
        case .keepAwake: .keepAwake
        case .windowSnap: .windowSnap
        case .voice: .voiceTranscribe
        case .camera: .camera
        case .backgroundRemoval: .backgroundRemoval
        case .reminders: .reminders
        }
    }
}

/// Expanded-island Tools page. Renders production controller state inside
/// the existing shell; it owns no feature state beyond the selected tool.
/// No scroll views, so expanded-island scroll gestures stay unambiguous.
struct ProductivityToolsPageView: View {
    let productivity: ProductivityModules
    let pageHeight: CGFloat
    @ObservedObject var capabilities: IslandCapabilityRegistry
    @State private var selectedTool: ProductivityTool = .keepAwake

    init(productivity: ProductivityModules, pageHeight: CGFloat) {
        self.productivity = productivity
        self.pageHeight = pageHeight
        self.capabilities = productivity.capabilities
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(ProductivityTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tool.symbolName)
                                .frame(width: 14)
                            Text(tool.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if capabilities.snapshot(for: tool.capabilityID)?.isActive == true {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(selectedTool == tool ? 0.95 : 0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            .white.opacity(selectedTool == tool ? 0.12 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(tool.title)")
                }
            }
            .frame(width: 118)

            VStack(alignment: .leading, spacing: 8) {
                CapabilityStatusLine(capabilities: capabilities, id: selectedTool.capabilityID)
                    .foregroundStyle(.white.opacity(0.8))
                toolContent
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: pageHeight, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var toolContent: some View {
        switch selectedTool {
        case .keepAwake:
            KeepAwakePanel(controller: productivity.keepAwake)
        case .windowSnap:
            WindowSnapPanel(controller: productivity.windowSnap)
        case .voice:
            VoiceTranscribePanel(controller: productivity.voice, compact: true)
        case .camera:
            CameraPanel(controller: productivity.camera, previewHeight: max(pageHeight - 70, 60))
        case .backgroundRemoval:
            BackgroundRemovalPanel(controller: productivity.backgroundRemoval, imageHeight: max(pageHeight - 110, 40))
        case .reminders:
            RemindersPanel(controller: productivity.reminders, maxUpcoming: 2)
                .task { await productivity.reminders.refresh() }
        }
    }
}

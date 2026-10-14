import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileActionPanel: View {
    let urls: [URL]
    let operations: BackgroundOperationController?
    var sample = false
    let addOutput: (URL) -> Void
    let dismiss: () -> Void
    @State private var audioAvailable = false
    @State private var checkingAudio = false
    @State private var job: Task<Void, Never>?
    @State private var busy = false
    @State private var status: String?
    @State private var compressionStarted = false
    @State private var selectedSample: FileAudioFormat?
    @State private var outputDirectory: URL?
    @State private var presentationGeneration = UUID()
    @State private var destinationPanel: NSOpenPanel?

    private var source: URL? { urls.count == 1 ? urls.first : nil }
    private var audioInput: Bool {
        if sample { return true }
        guard let source, let type = UTType(filenameExtension: source.pathExtension) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: audioInput ? "waveform" : "doc.fill").font(.system(size: 28))
                    .frame(width: 60, height: 60).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(sample ? "Preview recording.mov" : (source?.lastPathComponent ?? "\(urls.count) selected files"))
                        .font(.headline).lineLimit(1).truncationMode(.middle)
                        .help(source?.lastPathComponent ?? "Selected files")
                    Text(sample ? "Synthetic audio-bearing video" : fileSize).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(action: {
                    if sample { selectedSample = nil; status = nil } else { dismiss() }
                }) { Image(systemName: sample ? "arrow.counterclockwise.circle.fill" : "xmark.circle.fill").font(.title2) }
                    .buttonStyle(.plain).accessibilityLabel(sample ? "Reset file actions preview" : "Close file actions").disabled(busy)
            }
            if audioInput {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(FileAudioFormat.allCases) { format in
                            Button { sample ? selectSample(format) : convertAudio(format) } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: "waveform").font(.title2)
                                    Text(format.rawValue).font(.body.weight(.semibold))
                                }.frame(width: 76, height: 80)
                                    .background(selectedSample == format ? Color.accentColor.opacity(0.3) : .white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(!sample && (busy || !audioAvailable || !format.canEncode))
                            .help(sample ? "Select sample format; no conversion runs" : (format.canEncode ? "Convert the first audio track to \(format.rawValue)" : "Unavailable: this Mac has no \(format.rawValue) encoder"))
                            .accessibilityLabel("Convert to \(format.rawValue)")
                        }
                    }
                }
                if checkingAudio { ProgressView("Checking audio track…") }
                else if !sample && !audioAvailable { Text("No readable audio track was found.").font(.caption) }
                Text(sample ? "Interactive sample · No files are read or written" : "Mono/stereo first audio track. Original stays intact. Output metadata is not copied.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let source {
                HStack {
                    ForEach(FileConversionController.targetFormats(for: source)) { format in
                        Button("Convert to \(format.displayName)") { convertImage(source, format: format) }.disabled(busy)
                    }
                }
            }
            HStack {
                Button("Compress as ZIP") {
                    if sample { status = "Sample ZIP selected · No operation runs" }
                    else if operations?.startCompression(sources: urls) != nil { compressionStarted = true; status = "Compression started. Track or cancel it in Live Activities." }
                }.disabled(!sample && (urls.isEmpty || operations == nil || busy || compressionStarted))
                if busy {
                    ProgressView().controlSize(.small)
                    Button("Cancel conversion") { job?.cancel() }
                }
            }
            if source != nil || sample {
                HStack {
                    Text("Conversion destination").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(outputDirectory?.lastPathComponent ?? "Original folder").font(.caption).lineLimit(1)
                    Button("Choose…") { chooseDestination() }.disabled(busy)
                    if outputDirectory != nil { Button("Reset") { outputDirectory = nil }.disabled(busy) }
                }
            }
            if let status { Text(status).font(.caption).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(24).frame(minWidth: 360, idealWidth: 570, maxWidth: 620)
        .foregroundStyle(.white).background(Color.black)
        .task(id: urls) {
            audioAvailable = false
            guard !sample, audioInput, let source else { return }
            checkingAudio = true
            let hasAudio = await FileAudioConversion.hasAudio(source)
            guard !Task.isCancelled else { return }
            audioAvailable = hasAudio; checkingAudio = false
        }
        .onExitCommand { if busy { job?.cancel() } else { dismiss() } }
        .onDisappear {
            presentationGeneration = UUID(); job?.cancel()
            destinationPanel?.cancel(nil); destinationPanel = nil
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Contextual file actions")
    }
    private var fileSize: String {
        guard let source, let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "Local files · Originals preserved" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    private func selectSample(_ format: FileAudioFormat) { selectedSample = format; status = "Sample \(format.rawValue) selected · No conversion runs" }
    private func convertAudio(_ format: FileAudioFormat) {
        guard !busy, audioAvailable, format.canEncode, let source else { return }
        let folder = outputDirectory
        begin { try await FileAudioConversion.convert(source, to: format, outputDirectory: folder) }
    }
    private func convertImage(_ source: URL, format: FileConversionFormat) {
        guard !busy else { return }
        let folder = outputDirectory
        begin { try await FileConversionController.convert(source, to: format, outputDirectory: folder) }
    }
    private func begin(_ convert: @escaping @MainActor () async throws -> URL) {
        busy = true; status = "Converting…"
        let folder = outputDirectory
        job = Task { @MainActor in
            let access = folder?.startAccessingSecurityScopedResource() ?? false
            defer { if access { folder?.stopAccessingSecurityScopedResource() } }
            defer { busy = false; job = nil }
            do { let output = try await convert(); guard !Task.isCancelled else { try? FileManager.default.removeItem(at: output); throw CancellationError() }; addOutput(output); status = "Validated output added to File Tray." }
            catch is CancellationError { status = "Conversion cancelled. Original preserved." }
            catch { status = "Conversion failed. Original preserved; check file access and encoder support." }
        }
    }
    private func chooseDestination() {
        if sample { status = "Sample destination selected · No file picker opens"; return }
        guard destinationPanel == nil else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = outputDirectory ?? source?.deletingLastPathComponent()
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Choose"; panel.message = "Save converted files here. Originals are preserved; existing outputs are never overwritten."
        let generation = presentationGeneration
        destinationPanel = panel
        panel.begin { response in
            destinationPanel = nil
            guard presentationGeneration == generation, response == .OK, let url = panel.url else { return }
            outputDirectory = url
        }
    }
}

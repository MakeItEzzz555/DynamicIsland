import SwiftUI

struct AgentSessionLauncherView: View {
    let sessions: [AgentSession]
    @ObservedObject var managedControl: AgentManagedSessionController
    let onSelectSession: (AgentSessionInstanceID) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedRepositoryPath: String?
    @State private var repositoryPathDraft = ""
    @State private var showsRepositoryPathEntry = false
    @State private var repositoryPathError: String?
    @State private var starting = false

    private var liveSessions: [AgentSession] {
        AgentSessionLauncherProjection.liveSessions(
            sessions,
            query: query,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs
        )
    }

    private var currentSessionIDs: Set<AgentSessionInstanceID> {
        AgentSessionLauncherProjection.currentSessionIDs(
            sessions,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs
        )
    }

    private var repositories: [AgentLocalRepositoryChoice] {
        AgentSessionLauncherProjection.repositories(sessions, query: query)
    }

    private var selectedProvider: AgentProvider {
        managedControl.managedProvider ?? managedControl.managedProviders.first ?? .codex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.38))
                TextField("Search sessions or local repositories", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.38))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    launcherSectionTitle("LIVE SESSIONS")
                    if liveSessions.isEmpty {
                        launcherEmpty("No matching live or resumable sessions")
                    } else {
                        ForEach(liveSessions, id: \.id) { session in
                            liveSessionRow(session)
                        }
                    }

                    launcherSectionTitle("OPEN REPOSITORY")
                        .padding(.top, 6)

                    ForEach(repositories) { repo in
                        repositoryRow(repo)
                    }

                    Button {
                        showsRepositoryPathEntry.toggle()
                        repositoryPathError = nil
                    } label: {
                        Label("Enter local repository path…", systemImage: "folder.badge.plus")
                            .font(.system(size: 9.5, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.64))

                    if showsRepositoryPathEntry {
                        repositoryPathEntry
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 205)

            if let path = selectedRepositoryPath {
                Divider().overlay(.white.opacity(0.055))
                newSessionControls(path: path)
            }
        }
        .padding(9)
        .background(Color.black.opacity(0.96), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 12, y: 5)
        .onExitCommand(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent session and repository launcher")
    }

    private func launcherSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.32))
            .tracking(0.7)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
    }

    private func launcherEmpty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.30))
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
    }

    private func liveSessionRow(_ session: AgentSession) -> some View {
        let project = AgentPrivacyProjection.displayProject(session.project)
        let source = project.sourceApplicationName ?? session.source.rawValue
        let model = project.model ?? "model unavailable"
        let branch = project.gitBranch
        return Button {
            onSelectSession(session.id)
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: AgentVisualStyle.providerSymbol(session.id.sessionID.provider))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AgentVisualStyle.providerAccent(session.id.sessionID.provider))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.displayName ?? AgentSessionPresentation.primaryTitle(for: session))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                    Text("\(source) · \(model) · \(AgentSessionPresentation.displayedStateLabel(for: session, at: Date()))")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.40))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let branch, !branch.isEmpty {
                            Label(branch, systemImage: "arrow.triangle.branch")
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("…\(session.id.sessionID.nativeID.suffix(4))")
                            .fontDesign(.monospaced)
                    }
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.30))
                }
                Spacer(minLength: 4)
                if currentSessionIDs.contains(session.id) {
                    Text("Current")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.cyan.opacity(0.88))
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(.cyan.opacity(0.10), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.cyan.opacity(0.18), lineWidth: 1)
                        }
                        .help("Most current thread for this project")
                }
                if managedControl.isManaged(session) {
                    Image(systemName: "link.circle.fill")
                        .foregroundStyle(.green.opacity(0.68))
                        .help("Managed by DynamicIsland")
                } else {
                    Image(systemName: "eye")
                        .foregroundStyle(.white.opacity(0.30))
                        .help("Observed externally")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func repositoryRow(_ repo: AgentLocalRepositoryChoice) -> some View {
        Button {
            selectedRepositoryPath = repo.path
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedRepositoryPath == repo.path ? "folder.fill" : "folder")
                    .foregroundStyle(selectedRepositoryPath == repo.path ? .cyan.opacity(0.8) : .white.opacity(0.42))
                VStack(alignment: .leading, spacing: 1) {
                    Text(repo.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    HStack(spacing: 5) {
                        if let branch = repo.branch {
                            Label(branch, systemImage: "arrow.triangle.branch")
                        }
                        Text(repo.path)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
                    .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selectedRepositoryPath == repo.path ? Color.white.opacity(0.065) : .clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private func newSessionControls(path: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "plus.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("New Agent Session")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.34))
            }

            HStack(spacing: 5) {
                ForEach(managedControl.managedProviders, id: \.self) { provider in
                    Button {
                        managedControl.selectProvider(provider)
                    } label: {
                        Label(provider.stableName.capitalized, systemImage: AgentVisualStyle.providerSymbol(provider))
                            .font(.system(size: 8.5, weight: .semibold))
                            .padding(.horizontal, 7)
                            .frame(height: 24)
                            .background(
                                provider == selectedProvider ? Color.white.opacity(0.11) : Color.white.opacity(0.035),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            let models = managedControl.availableModels(for: selectedProvider)
            if !models.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        modelChoice("Default", model: nil)
                        ForEach(models) { option in
                            modelChoice(option.displayName, model: option.model)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            Button {
                guard !starting else { return }
                starting = true
                Task { @MainActor in
                    let descriptor = await managedControl.startNewSession(cwd: path)
                    starting = false
                    if descriptor != nil { onDismiss() }
                }
            } label: {
                Label(starting ? "Starting…" : "Start in repository", systemImage: "terminal.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 29)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.88))
            .background(.white.opacity(starting ? 0.55 : 0.92), in: RoundedRectangle(cornerRadius: 7))
            .disabled(starting || !managedControl.interactiveCapabilities.contains(.startSession))
        }
    }

    private var repositoryPathEntry: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                TextField("/path/to/repository", text: $repositoryPathDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .onSubmit(useRepositoryPathDraft)
                Button("Use") {
                    useRepositoryPathDraft()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))

            if let repositoryPathError {
                Text(repositoryPathError)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.red.opacity(0.78))
                    .padding(.horizontal, 3)
            }
        }
        .padding(.horizontal, 4)
    }

    private func modelChoice(_ title: String, model: String?) -> some View {
        let selected = managedControl.newSessionModel(for: selectedProvider) == model
        return Button {
            _ = managedControl.selectNewSessionModel(model, for: selectedProvider)
        } label: {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(selected ? 0.86 : 0.46))
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(.white.opacity(selected ? 0.09 : 0.025), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func useRepositoryPathDraft() {
        guard let path = AgentSessionLauncherProjection.validRepositoryPath(repositoryPathDraft) else {
            repositoryPathError = "Enter an existing local folder"
            return
        }
        selectedRepositoryPath = path
        repositoryPathDraft = path
        repositoryPathError = nil
        showsRepositoryPathEntry = false
    }


}

struct AgentLocalRepositoryChoice: Identifiable, Equatable {
    let path: String
    let name: String
    let branch: String?

    var id: String { path }
}

enum AgentSessionLauncherProjection {
    static func currentSessionIDs(
        _ sessions: [AgentSession],
        now: Date = Date(),
        activeManagedSessionIDs: Set<AgentSessionID> = []
    ) -> Set<AgentSessionInstanceID> {
        var currentByProject: [String: AgentSession] = [:]
        for session in sessions {
            let key = projectIdentity(session)
            guard let existing = currentByProject[key] else {
                currentByProject[key] = session
                continue
            }
            if isPreferredCurrent(
                session,
                over: existing,
                now: now,
                activeManagedSessionIDs: activeManagedSessionIDs
            ) {
                currentByProject[key] = session
            }
        }
        return Set(currentByProject.values.map(\.id))
    }

    static func liveSessions(
        _ sessions: [AgentSession],
        query: String,
        now: Date = Date(),
        recentObservedWindow: TimeInterval = 300,
        activeManagedSessionIDs: Set<AgentSessionID> = []
    ) -> [AgentSession] {
        let candidates = sessions.filter { session in
            let recentOpenObservation =
                session.endedAt == nil &&
                now.timeIntervalSince(session.lastUpdatedAt) <= recentObservedWindow
            let relevant: Bool
            switch session.state {
            case .working, .runningTool, .runningCommand, .thinking, .planning,
                 .planReady, .waitingForApproval, .waitingForUser:
                relevant = true
            case .idle, .completed, .failed, .interrupted:
                // A completed turn does not close the Codex thread. Keep a
                // recently observed VS Code/CLI thread selectable just like
                // AgentNotch's five-minute rollout window.
                relevant = session.availability == .resumable || recentOpenObservation
            }
            return relevant || !query.isEmpty
        }

        let active = candidates.filter {
            AgentWorkspaceSelection.isActive(
                $0,
                activeManagedSessionIDs: activeManagedSessionIDs
            )
        }
        let activeProjects = Set(active.map(projectIdentity))
        var latestInactiveByProject: [String: AgentSession] = [:]
        for session in candidates where !AgentWorkspaceSelection.isActive(
            session,
            activeManagedSessionIDs: activeManagedSessionIDs
        ) {
            let project = projectIdentity(session)
            guard !activeProjects.contains(project) else { continue }
            if let current = latestInactiveByProject[project],
               isPreferredHistorical(current, over: session) {
                continue
            }
            latestInactiveByProject[project] = session
        }

        let currentIDs = currentSessionIDs(
            candidates,
            now: now,
            activeManagedSessionIDs: activeManagedSessionIDs
        )
        return (active + Array(latestInactiveByProject.values))
            .filter { query.isEmpty || matchesSearch($0, query: query) }
            .sorted {
                let lhsCurrent = currentIDs.contains($0.id)
                let rhsCurrent = currentIDs.contains($1.id)
                if lhsCurrent != rhsCurrent { return lhsCurrent }
                let lhsActive = AgentWorkspaceSelection.isActive(
                    $0,
                    activeManagedSessionIDs: activeManagedSessionIDs
                )
                let rhsActive = AgentWorkspaceSelection.isActive(
                    $1,
                    activeManagedSessionIDs: activeManagedSessionIDs
                )
                if lhsActive != rhsActive { return lhsActive }
                return isPreferredHistorical($0, over: $1)
            }
    }

    private static func projectIdentity(_ session: AgentSession) -> String {
        if let repository = session.project.repositoryIdentity?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !repository.isEmpty {
            return "repository:\(repository.lowercased())"
        }
        if let workingDirectory = session.project.workingDirectory,
           let path = canonicalRepositoryPath(workingDirectory) {
            let root = canonicalRepositoryRoot(path) ?? path
            return "path:\(root.lowercased())"
        }
        // Without a stable repository/path identity it is safer to keep the
        // historical session distinct than to merge unrelated projects that
        // merely share a display name.
        return "session:\(session.id.sessionID.provider.deterministicSortKey):\(session.id.sessionID.nativeID)"
    }

    private static func isPreferredCurrent(
        _ lhs: AgentSession,
        over rhs: AgentSession,
        now: Date,
        activeManagedSessionIDs: Set<AgentSessionID>
    ) -> Bool {
        let lhsRank = currentRank(lhs, now: now, activeManagedSessionIDs: activeManagedSessionIDs)
        let rhsRank = currentRank(rhs, now: now, activeManagedSessionIDs: activeManagedSessionIDs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return isPreferredHistorical(lhs, over: rhs)
    }

    private static func currentRank(
        _ session: AgentSession,
        now: Date,
        activeManagedSessionIDs: Set<AgentSessionID>
    ) -> Int {
        if activeManagedSessionIDs.contains(session.id.sessionID) { return 0 }
        if AgentWorkspaceSelection.isActive(
            session,
            activeManagedSessionIDs: activeManagedSessionIDs
        ), !AgentSessionPresentation.hasStaleActiveSignal(session, at: now) {
            return 1
        }
        if session.endedAt == nil, now.timeIntervalSince(session.lastUpdatedAt) <= 60 {
            return 2
        }
        if session.availability == .resumable { return 3 }
        return 4
    }

    private static func isPreferredHistorical(_ lhs: AgentSession, over rhs: AgentSession) -> Bool {
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt { return lhs.lastUpdatedAt > rhs.lastUpdatedAt }
        if lhs.id.generation != rhs.id.generation { return lhs.id.generation > rhs.id.generation }
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
        if lhs.sourceAuthority != rhs.sourceAuthority { return lhs.sourceAuthority > rhs.sourceAuthority }
        let lhsSource = sourceStrength(lhs.source)
        let rhsSource = sourceStrength(rhs.source)
        if lhsSource != rhsSource { return lhsSource > rhsSource }
        return lhs.id.sessionID.nativeID > rhs.id.sessionID.nativeID
    }

    private static func sourceStrength(_ source: AgentSource) -> Int {
        switch source {
        case .desktopApp: 6
        case .vscode: 5
        case .jetbrains: 4
        case .terminal: 3
        case .cloud: 2
        case .mcp: 1
        case .unknown: 0
        }
    }

    private static func matchesSearch(_ session: AgentSession, query: String) -> Bool {
        let project = AgentPrivacyProjection.displayProject(session.project)
        return [
            project.displayName,
            session.project.workingDirectory,
            session.project.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent },
            project.gitBranch,
            project.model,
            project.sourceApplicationName,
            session.id.sessionID.provider.stableName,
            session.id.sessionID.nativeID
        ].compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func repositories(
        _ sessions: [AgentSession],
        query: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        repositoryRoot: (String) -> String? = { canonicalRepositoryRoot($0) }
    ) -> [AgentLocalRepositoryChoice] {
        var seen = Set<String>()
        return sessions
            .sorted { (lhs: AgentSession, rhs: AgentSession) -> Bool in
                if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
                    return lhs.lastUpdatedAt > rhs.lastUpdatedAt
                }
                if lhs.id.sessionID.provider != rhs.id.sessionID.provider {
                    return lhs.id.sessionID.provider.stableName < rhs.id.sessionID.provider.stableName
                }
                if lhs.id.sessionID.nativeID != rhs.id.sessionID.nativeID {
                    return lhs.id.sessionID.nativeID < rhs.id.sessionID.nativeID
                }
                return lhs.id.generation < rhs.id.generation
            }
            .compactMap { session -> AgentLocalRepositoryChoice? in
                guard let rawPath = session.project.workingDirectory,
                      let path = canonicalRepositoryPath(rawPath),
                      fileExists(path) else { return nil }
                let root = repositoryRoot(path) ?? path
                guard seen.insert(root).inserted else { return nil }
                let display = session.project.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                return AgentLocalRepositoryChoice(
                    path: root,
                    name: (display?.isEmpty == false ? display! : URL(fileURLWithPath: root).lastPathComponent),
                    branch: session.project.gitBranch
                )
            }
            .filter { choice in
                query.isEmpty ||
                choice.name.localizedCaseInsensitiveContains(query) ||
                choice.path.localizedCaseInsensitiveContains(query) ||
                (choice.branch?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func validRepositoryPath(
        _ rawPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        guard let path = canonicalRepositoryPath(rawPath) else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return path
    }

    private static func canonicalRepositoryPath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private static func canonicalRepositoryRoot(_ path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var candidate = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        while true {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent(".git").path
            ) {
                return candidate.path
            }

            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }
}

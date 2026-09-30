import AppKit
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
    @State private var projectedRepositories: [AgentLocalRepositoryChoice] = []
    @State private var recentFolders: [String] = []
    private let recentProjects = AgentRecentProjects(defaults: .standard)
    @Environment(\.agentProjectLocations) private var projectLocations

    private var liveSessions: [AgentSession] {
        AgentSessionLauncherProjection.liveSessions(
            sessions,
            query: query,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs,
            locations: projectLocations
        )
    }

    private var currentSessionIDs: Set<AgentSessionInstanceID> {
        AgentSessionLauncherProjection.currentSessionIDs(
            sessions,
            activeManagedSessionIDs: managedControl.activeManagedSessionIDs,
            locations: projectLocations
        )
    }

    private var repositories: [AgentLocalRepositoryChoice] {
        AgentSessionLauncherProjection.filterRepositories(projectedRepositories, query: query)
    }

    private var repositoryProjectionKey: String {
        AgentSessionLauncherProjection.repositoryProjectionKey(sessions)
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

                    let recents = recentFolders.filter { path in
                        !repositories.contains { $0.path == path } &&
                            (query.isEmpty || path.localizedCaseInsensitiveContains(query))
                    }
                    if !recents.isEmpty {
                        launcherSectionTitle("RECENT FOLDERS")
                            .padding(.top, 4)
                        ForEach(recents, id: \.self) { path in
                            repositoryRow(AgentLocalRepositoryChoice(
                                path: path,
                                name: URL(fileURLWithPath: path).lastPathComponent,
                                branch: nil
                            ))
                        }
                    }

                    Button(action: chooseFolder) {
                        Label("Open Folder…", systemImage: "folder.badge.plus")
                            .font(.system(size: 9.5, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.78))

                    Button {
                        showsRepositoryPathEntry.toggle()
                        repositoryPathError = nil
                    } label: {
                        Label("Enter folder path…", systemImage: "character.cursor.ibeam")
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
        .task(id: repositoryProjectionKey) {
            let snapshot = sessions
            let projected = await Task.detached(priority: .utility) {
                AgentSessionLauncherProjection.repositories(snapshot, query: "")
            }.value
            guard !Task.isCancelled else { return }
            projectedRepositories = projected
        }
        .onExitCommand(perform: onDismiss)
        .onAppear {
            recentFolders = recentProjects.load()
        }
        .task(id: selectedProvider) {
            await managedControl.refreshAgents(for: selectedProvider)
        }
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

            let agents = managedControl.availableAgents(for: selectedProvider)
            if !agents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        agentChoice("Default agent", agent: nil)
                        ForEach(agents) { option in
                            agentChoice(option.name, agent: option.name)
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
                    if descriptor != nil {
                        recentProjects.record(path)
                        onDismiss()
                    }
                }
            } label: {
                Label(starting ? "Starting…" : "Start in folder", systemImage: "terminal.fill")
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

    private func agentChoice(_ title: String, agent: String?) -> some View {
        let selected = managedControl.newSessionAgent(for: selectedProvider) == agent
        return Button {
            _ = managedControl.selectNewSessionAgent(agent, for: selectedProvider)
        } label: {
            Label(title, systemImage: agent == nil ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 0.86 : 0.46))
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(.white.opacity(selected ? 0.09 : 0.025), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(agent == nil ? "Start without a named agent" : "Start with the \(title) agent")
    }

    /// Any accessible local folder; the chosen folder itself becomes the
    /// session working directory (never rewritten to a repository root).
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a project folder for the agent session"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK,
              let url = panel.url,
              let path = AgentSessionLauncherProjection.validRepositoryPath(url.path) else { return }
        selectedRepositoryPath = path
        repositoryPathError = nil
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

struct AgentLocalRepositoryChoice: Identifiable, Equatable, Sendable {
    let path: String
    let name: String
    let branch: String?

    var id: String { path }
}

struct AgentProjectSessionSummary: Equatable {
    let repositoryIdentity: String
    let current: AgentSession?
    let otherActive: [AgentSession]
    let latestResumable: AgentSession?
}

enum AgentSessionLauncherProjection {
    static func preferredSelection(
        current: AgentSessionInstanceID?,
        sessions: [AgentSession],
        now: Date = Date(),
        activeManagedSessionIDs: Set<AgentSessionID> = [],
        locations: AgentProjectLocationIndex = .empty
    ) -> AgentSessionInstanceID? {
        if let current, sessions.contains(where: { $0.id == current }) {
            return current
        }
        return projectSummaries(
            sessions,
            now: now,
            activeManagedSessionIDs: activeManagedSessionIDs,
            locations: locations
        ).compactMap { $0.current?.id }.first
    }

    static func currentSessionIDs(
        _ sessions: [AgentSession],
        now: Date = Date(),
        activeManagedSessionIDs: Set<AgentSessionID> = [],
        locations: AgentProjectLocationIndex = .empty
    ) -> Set<AgentSessionInstanceID> {
        Set(
            projectSummaries(
                sessions,
                now: now,
                activeManagedSessionIDs: activeManagedSessionIDs,
                locations: locations
            ).compactMap { $0.current?.id }
        )
    }

    static func projectSummaries(
        _ sessions: [AgentSession],
        now: Date = Date(),
        activeManagedSessionIDs: Set<AgentSessionID> = [],
        locations: AgentProjectLocationIndex = .empty
    ) -> [AgentProjectSessionSummary] {
        let groups = Dictionary(grouping: sessions) { projectIdentity($0, locations: locations) }
        return groups.map { key, projectSessions in
            let orderedCurrent = projectSessions.sorted {
                isPreferredCurrent(
                    $0,
                    over: $1,
                    now: now,
                    activeManagedSessionIDs: activeManagedSessionIDs
                )
            }
            let current = orderedCurrent.first
            let active = projectSessions.filter {
                AgentWorkspaceSelection.isActive(
                    $0,
                    activeManagedSessionIDs: activeManagedSessionIDs
                ) && !AgentSessionPresentation.hasStaleActiveSignal($0, at: now)
            }
            let otherActive = active
                .filter { $0.id != current?.id }
                .sorted { isPreferredHistorical($0, over: $1) }
            let latestResumable = projectSessions
                .filter {
                    guard $0.id != current?.id else { return false }
                    if $0.availability == .resumable { return true }
                    guard !AgentWorkspaceSelection.isActive(
                        $0,
                        activeManagedSessionIDs: activeManagedSessionIDs
                    ) else { return false }
                    return $0.endedAt == nil &&
                        now.timeIntervalSince($0.lastUpdatedAt) <= 300
                }
                .sorted { isPreferredHistorical($0, over: $1) }
                .first
            return AgentProjectSessionSummary(
                repositoryIdentity: key,
                current: current,
                otherActive: otherActive,
                latestResumable: latestResumable
            )
        }
        .sorted {
            guard let lhs = $0.current else { return false }
            guard let rhs = $1.current else { return true }
            return isPreferredCurrent(
                lhs,
                over: rhs,
                now: now,
                activeManagedSessionIDs: activeManagedSessionIDs
            )
        }
    }

    static func liveSessions(
        _ sessions: [AgentSession],
        query: String,
        now: Date = Date(),
        recentObservedWindow: TimeInterval = 300,
        activeManagedSessionIDs: Set<AgentSessionID> = [],
        locations: AgentProjectLocationIndex = .empty
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

        // Apply search before project collapsing. This keeps the default
        // launcher clean while allowing an exact/suffix thread-ID search to
        // recover an older exact session even when the same project has a
        // different active thread.
        let projectedCandidates = query.isEmpty
            ? candidates
            : candidates.filter { matchesSearch($0, query: query) }

        let active = projectedCandidates.filter {
            AgentWorkspaceSelection.isActive(
                $0,
                activeManagedSessionIDs: activeManagedSessionIDs
            )
        }
        let activeProjects = Set(active.map { projectIdentity($0, locations: locations) })
        var latestInactiveByProject: [String: AgentSession] = [:]
        for session in projectedCandidates where !AgentWorkspaceSelection.isActive(
            session,
            activeManagedSessionIDs: activeManagedSessionIDs
        ) {
            let project = projectIdentity(session, locations: locations)
            guard !activeProjects.contains(project) else { continue }
            if let current = latestInactiveByProject[project],
               isPreferredHistorical(current, over: session) {
                continue
            }
            latestInactiveByProject[project] = session
        }

        let currentIDs = currentSessionIDs(
            projectedCandidates,
            now: now,
            activeManagedSessionIDs: activeManagedSessionIDs,
            locations: locations
        )
        return (active + Array(latestInactiveByProject.values))
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

    /// Pure: reads only the cached location index, never the filesystem,
    /// because it runs from SwiftUI body recomputation.
    static func projectIdentity(
        _ session: AgentSession,
        locations: AgentProjectLocationIndex = .empty
    ) -> String {
        AgentProjectGrouping.key(for: session, locations: locations, fallback: .perSession).rawValue
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
        // Tier 1: exact DynamicIsland-managed active ownership.
        if activeManagedSessionIDs.contains(session.id.sessionID) { return 0 }

        let freshActive = AgentWorkspaceSelection.isActive(
            session,
            activeManagedSessionIDs: activeManagedSessionIDs
        ) && !AgentSessionPresentation.hasStaleActiveSignal(session, at: now)

        // Tier 2: fresh Codex structured-rollout activity. Rollout events stamp
        // lastUpdatedAt at append-observation time, so freshness is already
        // represented without exposing rollout file internals to SwiftUI.
        if session.id.sessionID.provider == .codex,
           session.sourceAuthority == .localStructuredRecord,
           freshActive {
            return 1
        }

        // Tier 3: provider-native/lifecycle evidence that the exact thread is loaded/active.
        if session.sourceAuthority >= .lifecycle, freshActive {
            return 2
        }

        // Other fresh observed active work is still stronger than idle history.
        if freshActive { return 3 }

        // Tier 4: recently observed open thread, including a rollout that is
        // quiet right now but was appended recently.
        let freshness = session.activityEvidenceAt ?? session.lastUpdatedAt
        if session.endedAt == nil,
           now.timeIntervalSince(freshness) <= 60 {
            return 4
        }

        // Tier 5: only fall back to resumable history when no live evidence wins.
        if session.availability == .resumable { return 5 }
        return 6
    }

    private static func isPreferredHistorical(_ lhs: AgentSession, over rhs: AgentSession) -> Bool {
        let lhsActivity = lhs.activityEvidenceAt ?? lhs.lastUpdatedAt
        let rhsActivity = rhs.activityEvidenceAt ?? rhs.lastUpdatedAt
        if lhsActivity != rhsActivity { return lhsActivity > rhsActivity }
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt { return lhs.lastUpdatedAt > rhs.lastUpdatedAt }
        if lhs.id.generation != rhs.id.generation { return lhs.id.generation > rhs.id.generation }
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

    static func repositoryProjectionKey(_ sessions: [AgentSession]) -> String {
        sessions
            .sorted { lhs, rhs in
                repositoryProjectionSessionKey(lhs) < repositoryProjectionSessionKey(rhs)
            }
            .map { session in
                let project = session.project
                return [
                    repositoryProjectionSessionKey(session),
                    project.workingDirectory ?? "",
                    project.displayName ?? "",
                    project.gitBranch ?? ""
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    private static func repositoryProjectionSessionKey(_ session: AgentSession) -> String {
        [
            session.id.sessionID.provider.deterministicSortKey,
            session.id.sessionID.nativeID,
            String(session.id.generation.rawValue)
        ].joined(separator: ":")
    }

    static func filterRepositories(
        _ repositories: [AgentLocalRepositoryChoice],
        query: String
    ) -> [AgentLocalRepositoryChoice] {
        guard !query.isEmpty else { return repositories }
        return repositories.filter { choice in
            choice.name.localizedCaseInsensitiveContains(query) ||
            choice.path.localizedCaseInsensitiveContains(query) ||
            (choice.branch?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    static func repositories(
        _ sessions: [AgentSession],
        query: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        repositoryRoot: (String) -> String? = { AgentProjectResolver.resolve($0)?.repositoryRoot }
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
                guard let path = AgentProjectResolver.normalize(session.project.workingDirectory),
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
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func validRepositoryPath(
        _ rawPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        guard let path = AgentProjectResolver.normalize(rawPath) else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return path
    }
}

import Foundation

/// What the selected session offers in the workspace. Every non-composer
/// case is shown with an explicit label and action, never as a console
/// that silently lacks an input field.
enum AgentSessionControlSurface: Equatable, Sendable {
    /// Managed and accepting input: transcript + composer + Send (+ Stop).
    case composer
    /// Persisted provider session that can be resumed into managed control.
    case resumable
    /// Observed session the provider can take over.
    case controllable
    /// Attachment or reconciliation is in progress.
    case attaching
    /// The provider supports control, but not for this session right now.
    case controlUnavailable(String)
    /// The provider offers no managed control for this session.
    case readOnly
}

enum AgentWorkspaceSurface: Equatable {
    case launcher
    case empty(AgentProvider?)
    case session(AgentSession, AgentSessionControlSurface)
}

/// Single decision path for the Agents workspace, shared by the view and
/// the workflow tests.
struct AgentWorkspaceProjection {
    let providerSessions: [AgentSession]
    let effectiveProjectKey: String?
    let controlSessions: [AgentSession]
    let selectedSession: AgentSession?
    let surface: AgentWorkspaceSurface

    @MainActor
    static func make(
        sessions: [AgentSession],
        controller: AgentManagedSessionController,
        projectKey: String?,
        locations: AgentProjectLocationIndex,
        launcherOpen: Bool
    ) -> AgentWorkspaceProjection {
        let provider = controller.selectedProvider ?? controller.managedProvider
        let providerSessions = provider.map { provider in
            sessions.filter { $0.id.sessionID.provider == provider }
        } ?? sessions
        let effectiveKey = AgentProjectFilter.isEffective(
            projectKey,
            in: providerSessions,
            locations: locations
        ) ? projectKey : nil
        let controlSessions = AgentProjectFilter.filter(
            providerSessions,
            projectKey: effectiveKey,
            locations: locations
        )
        let selected = AgentWorkspaceSelection.session(
            current: controller.selectedSessionID,
            sessions: controlSessions,
            activeManagedSessionIDs: controller.activeManagedSessionIDs
        )
        let surface: AgentWorkspaceSurface
        if launcherOpen {
            surface = .launcher
        } else if let selected {
            surface = .session(selected, controlSurface(for: selected, controller: controller))
        } else {
            surface = .empty(provider)
        }
        return AgentWorkspaceProjection(
            providerSessions: providerSessions,
            effectiveProjectKey: effectiveKey,
            controlSessions: controlSessions,
            selectedSession: selected,
            surface: surface
        )
    }

    @MainActor
    static func controlSurface(
        for session: AgentSession,
        controller: AgentManagedSessionController
    ) -> AgentSessionControlSurface {
        if controller.isManaged(session), controller.mode(for: session).showsComposer {
            return .composer
        }
        switch controller.interactionState(for: session) {
        case .connecting, .checkingAttachment:
            return .attaching
        default:
            break
        }
        guard controller.supportsManagedControl(for: session) else { return .readOnly }
        if controller.canConnect(session) {
            return session.availability == .resumable ? .resumable : .controllable
        }
        return .controlUnavailable(
            controller.statusMessage(for: session) ?? "Managed control is not available for this session"
        )
    }

    /// Project filter to use after a session starts: keep the current
    /// filter when the new session belongs to it, otherwise switch to the
    /// new session's project so it can never be filtered out.
    static func projectKey(
        afterStarting session: AgentSession,
        currentKey: String?,
        locations: AgentProjectLocationIndex
    ) -> String? {
        let key = AgentProjectGrouping.key(for: session, locations: locations).rawValue
        guard let currentKey else { return nil }
        return currentKey == key ? currentKey : key
    }
}

/// State of the Agents launcher: browsing sessions, or configuring a new
/// session (provider, folder, model, agent) that starts only on Start.
@MainActor
final class AgentNewSessionFlow: ObservableObject {
    enum Mode: Equatable {
        case sessions
        case newSession
    }

    @Published private(set) var isPresented = false
    @Published var mode: Mode = .sessions
    @Published var provider: AgentProvider?
    @Published private(set) var folderPath: String?
    @Published private(set) var isStarting = false
    @Published private(set) var errorMessage: String?

    func present(_ mode: Mode, provider: AgentProvider?, folder: String?) {
        self.mode = mode
        if let provider { self.provider = provider }
        if let folder, let valid = AgentManagedSessionController.validatedWorkingDirectory(folder) {
            folderPath = valid
        }
        errorMessage = nil
        isPresented = true
    }

    func toggle(provider: AgentProvider?) {
        if isPresented { dismiss() } else { present(.sessions, provider: provider, folder: nil) }
    }

    func dismiss() {
        guard !isStarting else { return }
        isPresented = false
        errorMessage = nil
    }

    /// Uses an existing folder exactly as chosen.
    @discardableResult
    func useFolder(_ path: String) -> Bool {
        guard let valid = AgentManagedSessionController.validatedWorkingDirectory(path) else {
            errorMessage = "Folder not found. Choose an existing folder"
            return false
        }
        folderPath = valid
        mode = .newSession
        errorMessage = nil
        return true
    }

    /// Creates a new empty folder (never overwrites anything) and uses it.
    /// No Git repository is initialized.
    @discardableResult
    func createFolder(at url: URL, fileManager: FileManager = .default) -> Bool {
        let path = url.path
        guard !fileManager.fileExists(atPath: path) else {
            errorMessage = "A file or folder with that name already exists"
            return false
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            errorMessage = "The folder could not be created"
            return false
        }
        return useFolder(path)
    }

    var canStart: Bool {
        provider != nil && folderPath != nil && !isStarting
    }

    /// Starts in the chosen folder. On success the launcher closes and the
    /// exact new session is already selected and composer-ready; on
    /// failure the launcher stays open with the reason.
    func start(using controller: AgentManagedSessionController) async -> AgentManagedStartedSession? {
        guard !isStarting else { return nil }
        guard let provider else {
            errorMessage = "Choose Claude or Codex"
            return nil
        }
        guard let folderPath else {
            errorMessage = "Choose a project folder first"
            return nil
        }
        isStarting = true
        errorMessage = nil
        let result = await controller.startManagedSession(provider: provider, cwd: folderPath)
        isStarting = false
        switch result {
        case .success(let started):
            isPresented = false
            mode = .sessions
            return started
        case .failure(let failure):
            errorMessage = failure.message
            return nil
        }
    }
}

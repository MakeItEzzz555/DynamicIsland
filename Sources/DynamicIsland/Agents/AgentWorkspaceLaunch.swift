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
        launcherOpen: Bool,
        approvalControl: AgentApprovalController? = nil
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
        let selected = preferredSession(
            current: controller.selectedSessionID, sessions: controlSessions, controller: controller,
            approvalControl: approvalControl
        )
        let surface: AgentWorkspaceSurface
        if launcherOpen {
            surface = .launcher
        } else if let selected, offersPrimaryChat(selected, controller: controller) {
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

    /// Observation remains available to the Feed, but never establishes chat
    /// ownership. Only an exact managed session or a provider-verified resume
    /// candidate may occupy the primary interaction surface.
    @MainActor
    static func offersPrimaryChat(_ session: AgentSession, controller: AgentManagedSessionController) -> Bool {
        switch controlSurface(for: session, controller: controller) {
        case .composer, .resumable, .controllable, .attaching: return true
        case .controlUnavailable, .readOnly: return false
        }
    }

    @MainActor
    static func preferredSession(
        current: AgentSessionInstanceID?, sessions: [AgentSession], controller: AgentManagedSessionController,
        approvalControl: AgentApprovalController? = nil
    ) -> AgentSession? {
        let interactive = sessions.filter { controller.isManaged($0) && controller.mode(for: $0).showsComposer }
        if let current, let exact = sessions.first(where: { $0.id == current }), let approvalControl {
            // Shared bridge requests can be actionable without managed Chat
            // attachment. Attention must keep the selected exact Feed owner,
            // while offersPrimaryChat independently refuses fabricated control.
            let hasPending = approvalControl.pendingRequests.values.contains {
                $0.key.session == current && $0.expiresAt > Date()
            }
            let hasUnconfirmed = approvalControl.deliveringRequests.values.contains { $0.key.session == current }
            if hasPending || hasUnconfirmed { return exact }
        }
        if let current, let exact = sessions.first(where: { $0.id == current }),
           offersPrimaryChat(exact, controller: controller) { return exact }
        // A discovered external session must never displace a managed chat.
        if !interactive.isEmpty {
            return AgentWorkspaceSelection.session(current: nil, sessions: interactive,
                activeManagedSessionIDs: controller.activeManagedSessionIDs)
        }
        let resumable = sessions.filter { offersPrimaryChat($0, controller: controller) }
        if !resumable.isEmpty {
            return AgentWorkspaceSelection.session(current: current, sessions: resumable,
                activeManagedSessionIDs: controller.activeManagedSessionIDs)
        }
        // Retain truthful exact observation identity for operational data only.
        return AgentWorkspaceSelection.session(current: current, sessions: sessions,
            activeManagedSessionIDs: controller.activeManagedSessionIDs)
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

    /// Configures the existing launcher as the primary New Chat fallback,
    /// without opening an overlay or creating a second launch flow.
    func prepareNewChat(provider: AgentProvider?, folder: String?) {
        guard !isStarting else { return }
        mode = .newSession
        if let provider { self.provider = provider }
        if let folder, let valid = AgentManagedSessionController.validatedWorkingDirectory(folder) {
            folderPath = valid
        }
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

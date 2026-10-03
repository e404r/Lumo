import Foundation
import SwiftUI
import Combine

// Integration pills — Antigravity HUD
extension AgentTask {
    /// Dedicated Antigravity HUD agent task.
    static let integrationAgents: [AgentTask] = [
        AgentTask(id: "integration_gemini", name: "Antigravity", color: "#4285F4", state: .idle, steps: [], source: .antigravity, isIntegration: true),
    ]

    /// No external toggleable integrations
    static let toggleableIntegrationIds: [String] = []
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // Island state
    @Published var mode: IslandMode = .hidden
    @Published var view: IslandView = .overview

    // Tasks
    @Published var tasks: [AgentTask] = []
    @Published var focusId: String? = nil

    // Bot state override
    @Published var stateOverride: BotState? = nil

    // Real notch dimensions (set by IslandWindowController on launch)
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    // Last app active before NotchBuddy (for window context capture)
    var lastExternalApp: NSRunningApplication? = nil

    // Bot drag-attach state (hides original bot while ghost follows cursor)
    @Published var isDraggingBot: Bool = false

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var lastMouseMove: Date = .now
    var lastActivity: Date = .now
    var isPresent: Bool = true

    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false

    // Long thinking sigh state
    @Published var isSighing: Bool = false

    // Star Peeking and Hand Wave interaction state
    @Published var isPeekingUp: Bool = false
    @Published var isStarWaving: Bool = false

    // Upload progress (0-1) — set to 1.0 only at completion; animation is time-based
    @Published var uploadProgress: Double = 0

    // Upload animation timing (non-published — TimelineViews read these directly)
    var uploadStartTime: Date?
    var uploadDuration: Double = 2.4

    // File drag-over state (mailbox morph glow + mouth spring)
    @Published var fileDragOver: Bool = false

    // Sound enabled — persisted
    @Published var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    // Sound volume (0–0.2) — persisted, synced to SoundEngine
    @Published var soundVolume: Double = 0.12 {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
            SoundEngine.shared.volume = Float(soundVolume)
        }
    }

    // Active Model & Reasoning for Antigravity CLI (`agy`)
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "lumo_selected_model") ?? "gemini-3.8-flash-high" {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "lumo_selected_model")
            if let idx = chatSessions.firstIndex(where: { $0.id == activeSessionId }) {
                chatSessions[idx].model = selectedModel
            }
        }
    }

    @Published var selectedEffort: String = {
        let v = UserDefaults.standard.string(forKey: "lumo_selected_effort") ?? "high"
        return v == "max" ? "high" : v
    }() {
        didSet {
            let sanitized = (selectedEffort == "max") ? "high" : selectedEffort
            if selectedEffort != sanitized {
                selectedEffort = sanitized
                return
            }
            UserDefaults.standard.set(selectedEffort, forKey: "lumo_selected_effort")
            if let idx = chatSessions.firstIndex(where: { $0.id == activeSessionId }) {
                chatSessions[idx].effort = selectedEffort
            }
        }
    }

    var currentModelOption: AIModelOption {
        AIModelOption.find(selectedModel)
    }

    // Context for prompt (window attach / file)
    @Published var promptContext: PromptContext? = nil {
        didSet {
            if let idx = chatSessions.firstIndex(where: { $0.id == activeSessionId }) {
                chatSessions[idx].promptContext = promptContext
            }
        }
    }

    // Dropped file (set during upload flow)
    @Published var droppedFile: DroppedFile? = nil

    // Short note message (shown in NoteView)
    @Published var noteMessage: String? = nil

    // Auto-close delay — persisted
    @Published var autoCloseInterval: TimeInterval = 15 {
        didSet { UserDefaults.standard.set(autoCloseInterval, forKey: "autoCloseInterval") }
    }

    // Absence interval — persisted
    var absenceInterval: TimeInterval = 3 * 60 {
        didSet { UserDefaults.standard.set(absenceInterval, forKey: "absenceInterval") }
    }

    // Greeting threshold — how long hidden before greeting on reappear (default 2 min)
    var greetThresholdSeconds: TimeInterval = 120 {
        didSet { UserDefaults.standard.set(greetThresholdSeconds, forKey: "greetThreshold") }
    }

    // Hotkey to show island (e.g. ⌘⇧N)
    @Published var hotkeyEnabled: Bool = false {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    var hotkeyFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue {
        didSet { UserDefaults.standard.set(Int(hotkeyFlags), forKey: "hotkeyFlags") }
    }
    var hotkeyCode: UInt16 = 45 {  // 'n'
        didSet { UserDefaults.standard.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }

    // Vercel project filter — empty = watch all projects
    @Published var vercelProjectFilter: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(vercelProjectFilter)) {
                UserDefaults.standard.set(data, forKey: "vercelProjectFilter")
            }
        }
    }

    // n8n workflow filter — empty = watch all workflows
    @Published var n8nWorkflowFilter: Set<String> = [] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(n8nWorkflowFilter)) {
                UserDefaults.standard.set(data, forKey: "n8nWorkflowFilter")
            }
        }
    }

    // Active integration pills. Antigravity HUD is the dedicated integration.
    @Published var activeIntegrations: Set<String> = ["integration_gemini"] {
        didSet {
            if let data = try? JSONEncoder().encode(Array(activeIntegrations)) {
                UserDefaults.standard.set(data, forKey: "activeIntegrations")
            }
        }
    }

    // Pending API result
    @Published var searchResult: SearchResult? = nil

    // Vercel deployments (populated by VercelPoller)
    @Published var vercelDeployments: [VercelDeployment] = []

    // Resend emails (populated by ResendPoller)
    @Published var resendEmails: [ResendEmail] = []
    @Published var resendTotal: Int? = nil

    // GitHub stats (populated by GithubPoller)
    @Published var githubStats: GitHubStats? = nil

    // Stripe (populated by StripePoller)
    @Published var stripePayments: [StripePayment] = []
    @Published var stripeBalance: Int = 0           // raw balance in cents
    @Published var stripeDisplayBalance: Int = 0    // animated balance target
    @Published var stripeCurrency: String = "eur"
    @Published var stripeLoaded: Bool = false       // true after first successful poll
    @Published var stripeError: String? = nil      // last API error (nil = ok)

    // Cal.com (populated by CalcomPoller)
    @Published var calcomBookings: [CalcomBooking] = []
    @Published var calcomLoaded: Bool = false
    @Published var calcomError: String? = nil

    // Notion (populated by NotionPoller)
    @Published var notionPages: [NotionPage] = []
    @Published var notionLoaded: Bool = false
    @Published var notionError: String? = nil

    // Chat conversation history
    @Published var chatHistory: [ChatMessage] = []

    // Multi-Agent Chat Sessions (Tabs)
    @Published var chatSessions: [ChatSession] = [
        ChatSession(
            id: UUID(),
            title: "Chat 1",
            model: UserDefaults.standard.string(forKey: "lumo_selected_model") ?? "gemini-3.8-flash-high",
            effort: UserDefaults.standard.string(forKey: "lumo_selected_effort") ?? "high",
            history: []
        )
    ]
    @Published var activeSessionId: UUID = UUID()

    var activeSession: ChatSession {
        get {
            chatSessions.first(where: { $0.id == activeSessionId }) ?? chatSessions[0]
        }
        set {
            if let idx = chatSessions.firstIndex(where: { $0.id == activeSessionId }) {
                chatSessions[idx] = newValue
                chatHistory = newValue.history
            }
        }
    }

    func switchSession(id: UUID) {
        if let currentIdx = chatSessions.firstIndex(where: { $0.id == activeSessionId }) {
            chatSessions[currentIdx].promptContext = promptContext
        }
        guard let session = chatSessions.first(where: { $0.id == id }) else { return }
        activeSessionId = id
        selectedModel = session.model
        selectedEffort = session.effort
        chatHistory = session.history
        promptContext = session.promptContext
        let anyThinking = chatSessions.contains { $0.isThinking }
        stateOverride = anyThinking ? .thinking : nil
        SoundEngine.shared.play("blip")
    }

    func newChatSession(model: String? = nil) {
        let chosenModel = model ?? selectedModel
        let chosenEffort = selectedEffort
        let option = AIModelOption.find(chosenModel)
        let count = chatSessions.count + 1
        let title = "\(option.name.components(separatedBy: " ").first ?? "Chat") \(count)"
        let newSession = ChatSession(
            id: UUID(),
            title: title,
            model: chosenModel,
            effort: chosenEffort,
            history: []
        )
        chatSessions.append(newSession)
        switchSession(id: newSession.id)
    }

    func closeChatSession(id: UUID) {
        guard chatSessions.count > 1 else {
            if let idx = chatSessions.firstIndex(where: { $0.id == id }) {
                chatSessions[idx].history.removeAll()
                chatHistory.removeAll()
            }
            return
        }
        if activeSessionId == id {
            if let idx = chatSessions.firstIndex(where: { $0.id == id }) {
                let nextIdx = idx > 0 ? idx - 1 : 1
                let nextSession = chatSessions[nextIdx]
                activeSessionId = nextSession.id
                selectedModel = nextSession.model
                selectedEffort = nextSession.effort
                chatHistory = nextSession.history
                promptContext = nextSession.promptContext
            }
        }
        chatSessions.removeAll(where: { $0.id == id })
        let anyThinking = chatSessions.contains { $0.isThinking }
        stateOverride = anyThinking ? .thinking : nil
        SoundEngine.shared.play("pop")
    }

    func appendMessage(to sessionId: UUID, message: ChatMessage) {
        if let idx = chatSessions.firstIndex(where: { $0.id == sessionId }) {
            chatSessions[idx].history.append(message)
            if activeSessionId == sessionId {
                chatHistory = chatSessions[idx].history
            }
        }
    }

    func setSessionThinking(sessionId: UUID, thinking: Bool) {
        if let idx = chatSessions.firstIndex(where: { $0.id == sessionId }) {
            chatSessions[idx].isThinking = thinking
        }
        let anyThinking = chatSessions.contains { $0.isThinking }
        stateOverride = anyThinking ? .thinking : nil
    }

    // Pending approval request from Agent hook
    @Published var pendingApproval: ApprovalInfo? = nil

    // MARK: - Init (loads persisted settings)

    private init() {
        let ud = UserDefaults.standard

        if let v = ud.object(forKey: "soundEnabled") as? Bool   { soundEnabled = v }
        if let v = ud.object(forKey: "soundVolume")  as? Double { soundVolume  = v }
        // Migrate old 60s default → 15s
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
            autoCloseInterval = (v == 60) ? 15 : v
        }
        if let v = ud.object(forKey: "absenceInterval")   as? Double { absenceInterval   = v }
        if let v = ud.object(forKey: "greetThreshold")    as? Double { greetThresholdSeconds = v }
        if let v = ud.object(forKey: "hotkeyEnabled") as? Bool  { hotkeyEnabled = v }
        if let v = ud.object(forKey: "hotkeyFlags")   as? Int   { hotkeyFlags = UInt(v) }
        if let v = ud.object(forKey: "hotkeyCode")    as? Int   { hotkeyCode = UInt16(v) }
        if let d = ud.data(forKey: "vercelProjectFilter"),
           let a = try? JSONDecoder().decode([String].self, from: d) { vercelProjectFilter = Set(a) }
        if let d = ud.data(forKey: "n8nWorkflowFilter"),
           let a = try? JSONDecoder().decode([String].self, from: d) { n8nWorkflowFilter = Set(a) }
        if let d = ud.data(forKey: "activeIntegrations"),
           let a = try? JSONDecoder().decode([String].self, from: d) {
            var set = Set(a)
            if set.contains("integration_claude") {
                set.remove("integration_claude")
                set.insert("integration_gemini")
            }
            activeIntegrations = set
        }

        // Sync SoundEngine volume on launch
        SoundEngine.shared.volume = Float(soundVolume)

        // Ensure active session ID is initialized
        if let first = chatSessions.first {
            activeSessionId = first.id
        }

        // Always load integration pills
        loadIntegrationTasks()
    }

    // MARK: - Computed

    var focusTask: AgentTask? {
        tasks.first { $0.id == focusId } ?? tasks.first
    }

    var effectiveState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

    // MARK: - Task management

    func addTask(_ task: AgentTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        if focusId == nil { focusId = task.id }
        syncMode()
        syncView()
    }

    func removeTask(id: String) {
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = tasks.first?.id }
        syncMode()
        syncView()
    }

    func updateTask(id: String, state: BotState) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].state = state
    }

    func setFocus(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        focusId = id
        tasks[idx].pillBadge = nil  // clear badge when user brings task to focus
    }

    func syncMode() {
        // If no tasks and not expanded/peek, go hidden
        if tasks.isEmpty && mode == .compact {
            mode = .hidden
        } else if !tasks.isEmpty && mode == .hidden && isPresent {
            mode = .compact
        }
    }

    func syncView() {
        guard mode == .expanded else { return }
        if view == .empty && !tasks.isEmpty { view = .overview }
        else if view == .overview && tasks.isEmpty { view = .empty }
    }

    /// Load integration pills respecting activeIntegrations. Antigravity HUD always loads. Safe to call multiple times.
    func loadIntegrationTasks() {
        for task in AgentTask.integrationAgents {
            let shouldLoad = task.id == "integration_gemini" || activeIntegrations.contains(task.id)
            let loaded = tasks.contains(where: { $0.id == task.id })
            if shouldLoad && !loaded { tasks.append(task) }
            if !shouldLoad && loaded { tasks.removeAll { $0.id == task.id } }
        }
        if focusId == nil { focusId = "integration_gemini" }
        syncMode()
    }

    /// Toggle an integration pill on/off. Antigravity HUD cannot be toggled. Max 4 active at once.
    func toggleIntegration(_ id: String) {
        guard id != "integration_gemini" else { return }
        if activeIntegrations.contains(id) {
            activeIntegrations.remove(id)
            tasks.removeAll { $0.id == id }
            if focusId == id { focusId = "integration_gemini" }
        } else {
            guard activeIntegrations.count < 4 else { return }
            activeIntegrations.insert(id)
            if let task = AgentTask.integrationAgents.first(where: { $0.id == id }),
               !tasks.contains(where: { $0.id == id }) {
                tasks.append(task)
            }
        }
        syncMode()
    }

}

// MARK: - Supporting types

enum PromptContext {
    case window(appName: String, title: String, url: String?)
    case file(name: String, fileURL: URL?)
}

struct DroppedFile {
    var url: URL
    var name: String
}

struct SearchResult {
    var title: String
    var items: [ResultItem]
    var note: String?
}

struct ResultItem {
    var label: String
    var detail: String
    var url: String?
}

// MARK: - Vercel

struct VercelDeployment: Identifiable {
    let id: String
    let projectName: String
    let url: String
    let state: String        // "READY", "ERROR", "CANCELED"
    let createdAt: Date
    let commitMessage: String?
    let branch: String?

    var isSuccess: Bool { state == "READY" }
    var statusLabel: String { isSuccess ? "Ready" : (state == "CANCELED" ? "Canceled" : "Error") }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Resend

struct ResendEmail: Identifiable {
    let id: String
    let to: [String]
    let subject: String
    let createdAt: Date
    let lastEvent: String   // "delivered", "bounced", "complained", "opened", etc.

    var recipientShort: String {
        guard let first = to.first else { return "?" }
        return first.components(separatedBy: "@").first ?? first
    }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
    var isDelivered: Bool { lastEvent == "delivered" }
}

// MARK: - GitHub

struct GitHubStats {
    let totalRepos: Int
    let totalStars: Int
}

// MARK: - Stripe

struct StripePayment: Identifiable, Equatable {
    let id: String
    let amount: Int         // in cents/smallest unit
    let currency: String
    let description: String?
    let createdAt: Date
    let status: String      // "succeeded", "pending", "failed"

    var amountFormatted: String { String(format: "%.2f", Double(amount) / 100.0) }
    var isSuccess: Bool { status == "succeeded" }
    var timeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Cal.com

struct CalcomBooking: Identifiable, Equatable {
    let id: Int
    let title: String
    let startTime: Date
    let endTime: Date
    let status: String
    let attendeeName: String?
    let attendeeEmail: String?
    let attendeeNotes: String?

    var isActive: Bool { status == "ACCEPTED" || status == "PENDING" }
    var timeLabel: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: startTime)
    }
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: startTime)
        return "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
    }
}

// MARK: - Notion

struct NotionPage: Identifiable {
    let id: String
    let title: String
    let emoji: String?
    let lastEditedAt: Date
    let url: String

    var timeAgo: String {
        let diff = Date().timeIntervalSince(lastEditedAt)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

// MARK: - Chat

enum ChatRole: Equatable { case user, assistant }

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String

    init(id: UUID = UUID(), role: ChatRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

// MARK: - Multi-Agent Chat Session (Tabs)

struct ChatSession: Identifiable, Equatable {
    let id: UUID
    var title: String
    var model: String
    var effort: String
    var history: [ChatMessage]
    var isThinking: Bool = false
    var promptContext: PromptContext?
    var createdAt: Date = Date()

    var modelOption: AIModelOption {
        AIModelOption.find(model)
    }

    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.model == rhs.model &&
        lhs.effort == rhs.effort &&
        lhs.history == rhs.history &&
        lhs.isThinking == rhs.isThinking
    }
}

// MARK: - AI Models Supported by Antigravity

struct AIModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let provider: String
    let icon: String
    let tagColor: String

    static let allModels: [AIModelOption] = [
        AIModelOption(
            id: "gemini-3.8-flash-high",
            name: "Gemini 3.8 Flash",
            subtitle: "Lightning fast · High reasoning",
            provider: "Google",
            icon: "sparkles",
            tagColor: "#38BDF8"
        ),
        AIModelOption(
            id: "gemini-3.1-pro-high",
            name: "Gemini 3.1 Pro",
            subtitle: "Deep code analysis & complex tasks",
            provider: "Google",
            icon: "brain.head.profile",
            tagColor: "#818CF8"
        ),
        AIModelOption(
            id: "claude-sonnet-4-6",
            name: "Claude Sonnet 4.6",
            subtitle: "Balanced thinking & creative coding",
            provider: "Anthropic",
            icon: "cpu",
            tagColor: "#F59E0B"
        ),
        AIModelOption(
            id: "claude-opus-4-6-thinking",
            name: "Claude Opus 4.6",
            subtitle: "Deepest architectural reasoning",
            provider: "Anthropic",
            icon: "crown.fill",
            tagColor: "#EC4899"
        ),
        AIModelOption(
            id: "gemini-3.7-flash-high",
            name: "Gemini 3.7 Flash",
            subtitle: "Ultra responsive companion",
            provider: "Google",
            icon: "bolt.fill",
            tagColor: "#10B981"
        ),
        AIModelOption(
            id: "gpt-oss-120b-medium",
            name: "GPT-OSS 120B",
            subtitle: "Open-weights powerhouse",
            provider: "OSS",
            icon: "cube.fill",
            tagColor: "#A855F7"
        )
    ]

    static func find(_ id: String) -> AIModelOption {
        allModels.first { $0.id == id } ?? allModels[0]
    }
}

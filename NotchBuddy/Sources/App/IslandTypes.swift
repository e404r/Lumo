import Foundation

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

enum IslandView: String, CaseIterable {
    case overview, empty, approval, question, error, finished
    case confused, upload, uploading, choose, mail, prompt
    case searching, result, note, settings, greeting
}

// MARK: - Bot State

enum BotState: String, CaseIterable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

// MARK: - Bot Emote

enum BotEmote: String, CaseIterable {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

// MARK: - Approval info (pending PermissionRequest from Antigravity / Agent)

struct ApprovalInfo: Sendable {
    var sessionId: String
    var tool: String
    var command: String
}

// MARK: - Pill badge (shown on pill edge when non-focused task has an alert)

enum PillBadge { case approval, finished, error }

// MARK: - Agent Task

struct AgentTask: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String          // hex
    var state: BotState
    var stepIndex: Int = 0
    var steps: [String]
    var source: AgentSource
    var isIntegration: Bool = false  // true for persistent integration pills
    var emote: BotEmote? = nil
    var miniEye: EyeShape? = nil
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Agent sessions)
}

enum AgentSource: Equatable {
    case antigravity
    case gemini
    case n8n
}

// MARK: - View dimensions (from VIEWS in prototype)

struct ViewLayout {
    let height: CGFloat
    let botX: CGFloat
    let botY: CGFloat?         // nil = auto-centered
    let botDiameter: CGFloat
    let agentMode: AgentLayoutMode
}

enum AgentLayoutMode {
    case none, grid, pills, column
}

// MARK: - Constants (from NW, NH, EW in prototype)

enum IslandConst {
    static let notchWidth: CGFloat  = 184
    static let notchHeight: CGFloat = 32
    static let expandedWidth: CGFloat = 640
    static let earRadius: CGFloat   = 14
    static let roundedCorner: CGFloat = 14    // hidden/peek/compact
    static let expandedCorner: CGFloat = 22

    static let viewLayouts: [IslandView: ViewLayout] = [
        .overview:  ViewLayout(height: 172, botX: 68,  botY: nil, botDiameter: 48, agentMode: .none),
        .empty:     ViewLayout(height: 172, botX: 68,  botY: nil, botDiameter: 52, agentMode: .none),
        .approval:  ViewLayout(height: 172, botX: 68,  botY: nil, botDiameter: 48, agentMode: .column),
        .question:  ViewLayout(height: 172, botX: 68,  botY: nil, botDiameter: 48, agentMode: .column),
        .error:     ViewLayout(height: 172, botX: 68,  botY: nil, botDiameter: 48, agentMode: .column),
        .finished:  ViewLayout(height: 172, botX: 68,  botY: nil, botDiameter: 48, agentMode: .column),
        .confused:  ViewLayout(height: 172, botX: 68,  botY: nil, botDiameter: 48, agentMode: .column),
        .upload:    ViewLayout(height: 196, botX: 140, botY: 110, botDiameter: 56, agentMode: .column),
        .uploading: ViewLayout(height: 196, botX: 46,  botY: 124, botDiameter: 20, agentMode: .none),
        .choose:    ViewLayout(height: 196, botX: 60,  botY: 110, botDiameter: 48, agentMode: .column),
        .mail:      ViewLayout(height: 250, botX: 56,  botY: nil, botDiameter: 44, agentMode: .column),
        .prompt:    ViewLayout(height: 186, botX: 52,  botY: nil, botDiameter: 42, agentMode: .column),
        .searching: ViewLayout(height: 172, botX: 52,  botY: nil, botDiameter: 42, agentMode: .column),
        .result:    ViewLayout(height: 172, botX: 52,  botY: nil, botDiameter: 42, agentMode: .column),
        .note:      ViewLayout(height: 172, botX: 60,  botY: nil, botDiameter: 46, agentMode: .column),
        .settings:  ViewLayout(height: 172, botX: 54,  botY: nil, botDiameter: 44, agentMode: .none),
        .greeting:  ViewLayout(height: 172, botX: 68,  botY: nil, botDiameter: 48, agentMode: .none),
    ]

    // Project colors — keyed by lowercase display name or slug
    static let projectColors: [String: String] = [
        "korus":             "#FF5A4E",
        "sbe hub":           "#2EC4A0",
        "morning ai brief":  "#F29B38",
        "publication ig":    "#7C5CFF",
        "ig post":           "#7C5CFF",
        "louisraille.fr":    "#38BDF8",
        "louisraille":       "#38BDF8",
        "notch buddy":       "#EC4899",
        "notch-buddy":       "#EC4899",
        "notchbuddy":        "#EC4899",
    ]

    static let fallbackColors = ["#22C55E", "#EAB308", "#60A5FA", "#E879F9"]

    // Available integration pills (matches AgentTask.integrationAgents)
    struct IntegrationMeta {
        let id: String
        let name: String
        let color: String
    }
    static let allIntegrations: [IntegrationMeta] = [
        .init(id: "integration_gemini", name: "Antigravity", color: "#4285F4"),
    ]

    /// Returns the fixed project color for a display name, or a stable fallback.
    static func colorForProject(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let c = projectColors[key] { return c }
        // partial match (e.g. "korus-api" → "korus")
        for (k, c) in projectColors where key.hasPrefix(k) || key.contains(k) { return c }
        return fallbackColors[abs(name.hashValue) % fallbackColors.count]
    }

    // State card wash colors (radial gradient from bottom)
    static let washColors: [IslandView: String] = [
        .approval:  "rgba(245,165,36,0.42)",
        .question:  "rgba(34,211,238,0.38)",
        .error:     "rgba(244,80,94,0.55)",
        .finished:  "rgba(52,211,153,0.5)",
        .confused:  "rgba(244,114,182,0.55)",
        .searching: "rgba(99,102,241,0.5)",
        .result:    "rgba(52,211,153,0.22)",
        .prompt:    "rgba(99,102,241,0.22)",
    ]
}

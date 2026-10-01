import Foundation
import Darwin
import AppKit

// MARK: - SocketServer (Lumo Unix Domain Socket Server for agy)
// Listens on ~/.lumo/lumo.sock for IPC from lumo_bridge.py.
// Thread-safe socket I/O on background threads; state updates dispatched to @MainActor.

typealias HookServer = SocketServer

final class SocketServer: @unchecked Sendable {
    static let shared = SocketServer()

    private var serverFD: Int32 = -1
    private var pendingApprovalFD: Int32 = -1
    private(set) var hasActiveSession: Bool = false
    private var lastEventTime: Date = .distantPast
    static var supportDir: URL {
        AntigravityHookInstaller.lumoDir
    }

    private init() {}

    // MARK: - Lifecycle

    func start() {
        // Ensure bridge and hooks are installed on startup
        AntigravityHookInstaller.shared.install()

        Thread.detachNewThread { [weak self] in
            self?.serverThread()
        }
    }

    // Convenience hook installer proxy
    var isHooksConfigured: Bool {
        AntigravityHookInstaller.shared.isInstalled
    }

    func installBridgeAndHooks() {
        AntigravityHookInstaller.shared.install()
    }

    func uninstallLumoHooks() {
        AntigravityHookInstaller.shared.uninstall()
    }

    // MARK: - Socket Server (Background Thread)

    private func serverThread() {
        let path = AntigravityHookInstaller.socketPath
        let maxSunPathBytes = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size - 1
        guard path.utf8.count <= maxSunPathBytes else { return }

        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cpath = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, c) in cpath.enumerated() where i < raw.count { raw[i] = UInt8(bitPattern: c) }
        }

        let bindRC = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindRC == 0 else { close(fd); return }
        guard Darwin.listen(fd, 10) == 0 else { close(fd); return }

        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { break }
            self.hasActiveSession = true
            self.lastEventTime = Date()
            Thread.detachNewThread { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    // MARK: - Client Handler

    private func handleClient(fd: Int32) {
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        outer: while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == UInt8(ascii: "\n") { break outer }
                raw.append(buf[i])
            }
        }

        guard !raw.isEmpty,
              let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            sendLine(fd: fd, text: #"{"decision":"allow"}"#)
            close(fd)
            return
        }

        let eventName = payload["hook_event_name"] as? String ?? ""

        if eventName == "PreToolUse" {
            Task { @MainActor in
                self.processPreToolUse(fd: fd, payload: payload)
            }
        } else {
            Task { @MainActor in
                self.processGenericEvent(name: eventName, payload: payload)
            }
            sendLine(fd: fd, text: "{}\n")
            close(fd)
        }
    }

    // MARK: - Event Handlers (@MainActor)

    @MainActor
    private func processGenericEvent(name: String, payload: [String: Any]) {
        let state = AppState.shared
        let workspacePaths = payload["workspacePaths"] as? [String] ?? []
        let cwd = payload["cwd"] as? String ?? workspacePaths.first ?? ""
        let rawName = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = rawName.isEmpty ? "Antigravity" : rawName
        upsertTask(projectName: projectName, cwd: cwd)

        let focused = state.focusId == "integration_claude"

        switch name {
        case "PreInvocation":
            state.updateTask(id: "integration_claude", state: .thinking)
            appendStep(id: "integration_claude", step: "Gemini is thinking…")
            if state.isPresent { expandIfNeeded(to: .overview) }

        case "PostInvocation":
            state.updateTask(id: "integration_claude", state: .working)

        case "PostToolUse":
            state.updateTask(id: "integration_claude", state: .working)
            if let err = payload["error"] as? String, !err.isEmpty {
                appendStep(id: "integration_claude", step: "⚠ \(err.prefix(40))")
            }

        case "Stop":
            state.updateTask(id: "integration_claude", state: .finished)
            appendStep(id: "integration_claude", step: "✓ Task completed")
            SoundEngine.shared.play("finish")
            if focused {
                expandIfNeeded(to: .finished)
            } else {
                setPillBadge(id: "integration_claude", badge: .finished)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
                state.updateTask(id: "integration_claude", state: .idle)
                self.clearPillBadge(id: "integration_claude")
            }

        default:
            break
        }
    }

    @MainActor
    private func processPreToolUse(fd: Int32, payload: [String: Any]) {
        let state = AppState.shared
        let conversationId = payload["conversationId"] as? String ?? "session"
        let workspacePaths = payload["workspacePaths"] as? [String] ?? []
        let cwd = payload["cwd"] as? String ?? workspacePaths.first ?? ""
        let rawName = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = rawName.isEmpty ? "Antigravity" : rawName
        upsertTask(projectName: projectName, cwd: cwd)

        let toolCall = payload["toolCall"] as? [String: Any] ?? [:]
        let toolName = toolCall["name"] as? String ?? "Tool"
        let args = toolCall["args"] as? [String: Any] ?? [:]

        let stepText = formatToolStep(tool: toolName, args: args)
        appendStep(id: "integration_claude", step: stepText)

        let requiresApproval = isActionSensitive(toolName: toolName, args: args)

        if requiresApproval {
            if pendingApprovalFD >= 0 {
                let old = pendingApprovalFD
                Task.detached { [weak self] in
                    self?.sendLine(fd: old, text: #"{"decision":"allow"}"#)
                    close(old)
                }
            }
            pendingApprovalFD = fd

            var displayCommand = toolName
            if let cmd = args["CommandLine"] as? String {
                displayCommand = cmd
            } else if let file = args["TargetFile"] as? String {
                displayCommand = "\(toolName) \(URL(fileURLWithPath: file).lastPathComponent)"
            }

            state.updateTask(id: "integration_claude", state: .approval)
            state.pendingApproval = ApprovalInfo(sessionId: conversationId, tool: toolName, command: displayCommand)
            state.isPinned = true
            SoundEngine.shared.play("approval")

            state.focusId = "integration_claude"
            expandIfNeeded(to: .approval)

            // Fallback timeout after 115s: allow terminal to resume
            let captured = fd
            DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in
                guard let self, self.pendingApprovalFD == captured else { return }
                self.sendApprovalDecision("allow")
            }
        } else {
            // Auto-approved step
            state.updateTask(id: "integration_claude", state: .working)
            if state.isPresent && state.mode == .hidden {
                expandIfNeeded(to: .overview)
            }
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"decision":"allow"}"#)
                close(fd)
            }
        }
    }

    private func isActionSensitive(toolName: String, args: [String: Any]) -> Bool {
        if toolName == "run_command" {
            return true
        }
        return false
    }

    // MARK: - Approval Decision Handling

    @MainActor
    func sendApprovalDecision(_ decision: String) {
        let fd = pendingApprovalFD
        pendingApprovalFD = -1

        let json: String
        switch decision {
        case "allow":
            json = #"{"decision":"allow","permissionOverrides":["*"]}"#
        case "always":
            json = #"{"decision":"allow","permissionOverrides":["*"]}"#
        default:
            json = #"{"decision":"deny","reason":"Declined by user in Lumo"}"#
        }

        if fd >= 0 {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: json)
                close(fd)
            }
        }

        let state = AppState.shared
        state.pendingApproval = nil
        state.isPinned = false
        state.updateTask(id: "integration_claude", state: .working)
        clearPillBadge(id: "integration_claude")
        state.view = state.tasks.isEmpty ? .empty : .overview
    }

    // MARK: - Helpers

    @MainActor
    private func expandIfNeeded(to view: IslandView) {
        let state = AppState.shared
        let isAlert: Bool
        switch view {
        case .approval, .finished, .error, .confused: isAlert = true
        default: isAlert = false
        }
        if state.mode == .expanded {
            if isAlert { state.view = view }
        } else if isAlert {
            NotificationCenter.default.post(name: .hookExpand, object: view)
        } else if state.mode == .hidden {
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
    }

    @MainActor
    private func upsertTask(projectName: String, cwd: String = "") {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) else { return }
        state.tasks[idx].name = projectName
        if !cwd.isEmpty { state.tasks[idx].sessionCwd = cwd }
    }

    @MainActor
    private func setPillBadge(id: String, badge: PillBadge) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = badge
    }

    @MainActor
    private func clearPillBadge(id: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = nil
    }

    @MainActor
    private func appendStep(id: String, step: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].steps.append(step)
        if state.tasks[idx].steps.count > 25 { state.tasks[idx].steps.removeFirst() }
        state.tasks[idx].stepIndex = state.tasks[idx].steps.count - 1
    }

    private func formatToolStep(tool: String, args: [String: Any]) -> String {
        switch tool {
        case "run_command":
            if let cmd = args["CommandLine"] as? String {
                return "Run · \(cmd.prefix(35))"
            }
            return "Run command"
        case "replace_file_content", "multi_replace_file_content":
            if let file = args["TargetFile"] as? String {
                return "Edit · \(URL(fileURLWithPath: file).lastPathComponent)"
            }
            return "Edit file"
        case "write_to_file":
            if let file = args["TargetFile"] as? String {
                return "Write · \(URL(fileURLWithPath: file).lastPathComponent)"
            }
            return "Write file"
        case "view_file":
            if let file = args["AbsolutePath"] as? String {
                return "View · \(URL(fileURLWithPath: file).lastPathComponent)"
            }
            return "View file"
        case "grep_search":
            if let q = args["Query"] as? String {
                return "Search · \(q.prefix(30))"
            }
            return "Search codebase"
        case "list_dir":
            if let d = args["DirectoryPath"] as? String {
                return "List · \(URL(fileURLWithPath: d).lastPathComponent)"
            }
            return "List directory"
        case "browser_subagent", "read_browser_page":
            if let s = args["TaskSummary"] as? String ?? args["TaskName"] as? String {
                return "Web · \(s.prefix(30))"
            }
            return "Browser action"
        case "read_url_content":
            if let u = args["Url"] as? String {
                let hostOrPrefix = URL(string: u)?.host ?? String(u.prefix(30))
                return "Fetch · \(hostOrPrefix)"
            }
            return "Fetch URL"
        case "ask_question":
            return "Asking question…"
        case "generate_image":
            if let p = args["Prompt"] as? String {
                return "Imagen · \(p.prefix(30))"
            }
            return "Generate image"
        default:
            return tool
        }
    }

    private func sendLine(fd: Int32, text: String) {
        let full = text.hasSuffix("\n") ? text : text + "\n"
        let bytes = Array(full.utf8)
        bytes.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let n = Darwin.send(fd, buffer.baseAddress! + sent, buffer.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}

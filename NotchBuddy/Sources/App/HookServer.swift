import Foundation
import Darwin
import AppKit

// MARK: - HookServer (Lumo Edition for Google Antigravity CLI)
// Listens on a Unix domain socket (~/.lumo/lumo.sock) for lifecycle events from lumo_bridge.py.
// Thread-safe: socket I/O on background threads, state updates dispatched to main actor.

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()

    // Support directory: ~/.lumo
    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lumo")
    }

    // Unix domain socket: ~/.lumo/lumo.sock
    static var socketPath: String {
        supportDir.appendingPathComponent("lumo.sock").path
    }

    // Python bridge hook script: ~/.lumo/lumo_bridge.py
    static var bridgeScriptPath: String {
        supportDir.appendingPathComponent("lumo_bridge.py").path
    }

    // Antigravity global hooks configuration: ~/.gemini/config/hooks.json
    static var geminiHooksConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/config/hooks.json")
    }

    private var serverFD: Int32 = -1
    private var pendingApprovalFD: Int32 = -1
    private var activeConversationId: String? = nil

    private init() {}

    // MARK: - Lifecycle

    func start() {
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        installBridgeAndHooks()
        Thread.detachNewThread { self.serverThread() }
    }

    // MARK: - Auto-Configuration for Antigravity

    var isHooksConfigured: Bool {
        guard let data = try? Data(contentsOf: Self.geminiHooksConfigURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["lumo"] != nil else {
            return false
        }
        return true
    }

    func installBridgeAndHooks() {
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. Write the Python bridge script
        let bridgeURL = URL(fileURLWithPath: Self.bridgeScriptPath)
        try? lumoBridgePythonScript.write(to: bridgeURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: bridgeURL.path)

        // 2. Patch ~/.gemini/config/hooks.json
        patchGeminiHooksConfig()
    }

    func patchGeminiHooksConfig() {
        let configURL = Self.geminiHooksConfigURL
        let configDir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        let pythonCommand = "/usr/bin/python3 \"\(Self.bridgeScriptPath)\""

        let lumoHookGroup: [String: Any] = [
            "enabled": true,
            "PreToolUse": [
                [
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(pythonCommand) PreToolUse",
                            "timeout": 120
                        ]
                    ]
                ]
            ],
            "PostToolUse": [
                [
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(pythonCommand) PostToolUse",
                            "timeout": 15
                        ]
                    ]
                ]
            ],
            "PreInvocation": [
                [
                    "type": "command",
                    "command": "\(pythonCommand) PreInvocation",
                    "timeout": 15
                ]
            ],
            "PostInvocation": [
                [
                    "type": "command",
                    "command": "\(pythonCommand) PostInvocation",
                    "timeout": 15
                ]
            ],
            "Stop": [
                [
                    "type": "command",
                    "command": "\(pythonCommand) Stop",
                    "timeout": 15
                ]
            ]
        ]

        root["lumo"] = lumoHookGroup

        if let outData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? outData.write(to: configURL, options: .atomic)
            lumoLog("Successfully installed Antigravity hooks in \(configURL.path)")
        }
    }

    func uninstallLumoHooks() {
        let configURL = Self.geminiHooksConfigURL
        guard let data = try? Data(contentsOf: configURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        root.removeValue(forKey: "lumo")
        if let outData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? outData.write(to: configURL, options: .atomic)
            lumoLog("Uninstalled Lumo hooks from \(configURL.path)")
        }
    }

    // MARK: - Socket Server (Background Thread)

    private func serverThread() {
        let path = Self.socketPath
        let maxSunPathBytes = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size - 1
        guard path.utf8.count <= maxSunPathBytes else {
            lumoLog("Socket path too long: \(path)")
            return
        }

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

        lumoLog("Lumo socket listening at \(path)")

        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { break }
            Thread.detachNewThread { self.handleClient(fd: clientFD) }
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
            // Check if tool execution needs interactive user permission
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

    // MARK: - Event Processing (Main Actor)

    @MainActor
    private func processGenericEvent(name: String, payload: [String: Any]) {
        let state = AppState.shared
        let conversationId = payload["conversationId"] as? String ?? "session"
        activeConversationId = conversationId

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
        activeConversationId = conversationId

        let workspacePaths = payload["workspacePaths"] as? [String] ?? []
        let cwd = payload["cwd"] as? String ?? workspacePaths.first ?? ""
        let rawName = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = rawName.isEmpty ? "Antigravity" : rawName
        upsertTask(projectName: projectName, cwd: cwd)

        let toolCall = payload["toolCall"] as? [String: Any] ?? [:]
        let toolName = toolCall["name"] as? String ?? "Tool"
        let args = toolCall["args"] as? [String: Any] ?? [:]

        let stepText = formatAntigravityStep(tool: toolName, args: args)
        appendStep(id: "integration_claude", step: stepText)
        lumoLog("PreToolUse: \(toolName) -> \(stepText)")

        // Identify tools requiring user approval
        let requiresApproval = isToolSensitive(toolName: toolName, args: args)

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

            // Auto-fallback timeout after 115s (allows Antigravity default flow)
            let captured = fd
            DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in
                guard let self, self.pendingApprovalFD == captured else { return }
                self.sendApprovalDecision("allow")
            }
        } else {
            // Auto-approved safe read/inspection tool
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

    /// Evaluates if an Antigravity tool should prompt for user confirmation in Notch
    private func isToolSensitive(toolName: String, args: [String: Any]) -> Bool {
        if toolName == "run_command" {
            // Check for high-impact commands
            if let cmd = (args["CommandLine"] as? String)?.lowercased() {
                let destructive = ["rm -rf", "git push", "git reset", "drop table", "sudo", "chmod", "kill", "pkill"]
                for pattern in destructive {
                    if cmd.contains(pattern) { return true }
                }
            }
            // By default, command executions can prompt for approval if configured
            return true
        }
        return false
    }

    // MARK: - Approval Decision

    @MainActor
    func sendApprovalDecision(_ decision: String) {
        let fd = pendingApprovalFD
        pendingApprovalFD = -1

        let json: String
        switch decision {
        case "allow":
            json = #"{"decision":"allow","permissionDecision":"allow"}"#
        case "always":
            json = #"{"decision":"allow","permissionDecision":"always"}"#
        default:
            json = #"{"decision":"deny","reason":"Declined by user in Lumo","permissionDecision":"deny"}"#
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

    // MARK: - UI & Task Helpers

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

    private func formatAntigravityStep(tool: String, args: [String: Any]) -> String {
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

    // MARK: - Networking / Sockets IO

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

    private func lumoLog(_ message: String) {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Lumo")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFile = logsDir.appendingPathComponent("lumo.log")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let hookExpand = Notification.Name("lumo.hookExpand")
}

// MARK: - Embedded Python Bridge Script (lumo_bridge.py)
// Executed by Antigravity CLI lifecycle hooks.
// Connects to ~/.lumo/lumo.sock.
// Instant fail-safe: if Lumo is not running, exits in <5ms with default allow without blocking.

private let lumoBridgePythonScript = """
#!/usr/bin/env python3
import sys, json, os, socket

def main():
    event_name = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        raw = sys.stdin.buffer.read()
        payload = json.loads(raw) if raw else {}
    except Exception:
        payload = {}

    payload["hook_event_name"] = event_name

    # Add environment metadata
    env = os.environ
    payload.setdefault("term_program", env.get("TERM_PROGRAM", ""))
    payload.setdefault("cwd", os.getcwd())

    socket_path = os.path.expanduser("~/.lumo/lumo.sock")

    # Fast fail-safe: check socket existence
    if not os.path.exists(socket_path):
        fallback(event_name)
        return

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.2)
        s.connect(socket_path)
    except Exception:
        fallback(event_name)
        return

    try:
        s.sendall((json.dumps(payload) + "\\n").encode("utf-8"))

        if event_name == "PreToolUse":
            # Wait for user decision from Lumo (up to 118s)
            s.settimeout(118)
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b"\\n" in chunk:
                    break
            s.close()
            raw_resp = b"".join(chunks).decode("utf-8").strip()
            if raw_resp:
                sys.stdout.write(raw_resp + "\\n")
                sys.stdout.flush()
                return
            fallback(event_name)
        else:
            s.settimeout(1.0)
            try:
                s.recv(1024)
            except Exception:
                pass
            s.close()
            fallback(event_name)
    except Exception:
        fallback(event_name)

def fallback(event_name):
    if event_name == "PreToolUse":
        sys.stdout.write(json.dumps({"decision": "allow"}) + "\\n")
    else:
        sys.stdout.write("{}\\n")
    sys.stdout.flush()

if __name__ == "__main__":
    main()
    sys.exit(0)
"""

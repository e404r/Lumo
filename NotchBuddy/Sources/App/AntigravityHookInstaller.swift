import Foundation

// MARK: - AntigravityHookInstaller
// Manages zero-config installation of Lumo bridge and Antigravity lifecycle hooks.

final class AntigravityHookInstaller: Sendable {
    static let shared = AntigravityHookInstaller()

    static var lumoDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lumo")
    }

    static var socketPath: String {
        lumoDir.appendingPathComponent("lumo.sock").path
    }

    static var bridgeScriptPath: String {
        lumoDir.appendingPathComponent("lumo_bridge.py").path
    }

    static var geminiHooksConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/config/hooks.json")
    }

    var isInstalled: Bool {
        guard let data = try? Data(contentsOf: Self.geminiHooksConfigURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["lumo"] != nil else {
            return false
        }
        return true
    }

    @discardableResult
    func install() -> Bool {
        let dir = Self.lumoDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. Write the Python bridge script
        let bridgeURL = URL(fileURLWithPath: Self.bridgeScriptPath)
        do {
            try lumoBridgeScriptSource.write(to: bridgeURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: bridgeURL.path)
        } catch {
            return false
        }

        // 2. Patch ~/.gemini/config/hooks.json
        return patchHooksConfig()
    }

    func uninstall() {
        let configURL = Self.geminiHooksConfigURL
        guard let data = try? Data(contentsOf: configURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        root.removeValue(forKey: "lumo")
        if let outData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? outData.write(to: configURL, options: .atomic)
        }
    }

    private func patchHooksConfig() -> Bool {
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

        guard let outData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }

        do {
            try outData.write(to: configURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Python Bridge Relay Source (lumo_bridge.py)
// Intercepts agy lifecycle events and sends them over ~/.lumo/lumo.sock.
// Instant fail-safe: if Lumo.app is not running, exits immediately with {"decision": "allow"}

private let lumoBridgeScriptSource = """
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

    env = os.environ
    payload.setdefault("term_program", env.get("TERM_PROGRAM", ""))
    payload.setdefault("cwd", os.getcwd())

    socket_path = os.path.expanduser("~/.lumo/lumo.sock")

    # Fast exit if Lumo is not running
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
            # Wait for user Allow/Deny response from Lumo Notch (up to 118s)
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

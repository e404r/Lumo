import Foundation
import Security
import SwiftUI

// MARK: - Keychain helpers

enum Keychain {
    static let service = "com.lumo.Lumo"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let lookup: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(lookup as CFDictionary)
        let item: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Keychain cache

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    private static let allKeys = [
        "resend-api-key", "resend-from",
        "n8n-url", "n8n-api-key",
        "vercel-token",
        "github-token",
        "stripe-api-key",
        "calcom-api-key",
        "notion-api-key",
    ]

    private init() {
        for key in Self.allKeys {
            if let v = Keychain.load(key: key) { cache[key] = v }
        }
    }

    func get(_ key: String) -> String? {
        lock.withLock { cache[key] }
    }

    func set(_ key: String, value: String) {
        lock.withLock { cache[key] = value }
        Keychain.save(key: key, value: value)
    }

    func remove(_ key: String) {
        let had = lock.withLock { () -> Bool in
            let exists = cache[key] != nil
            cache[key] = nil
            return exists
        }
        if had { Keychain.delete(key: key) }
    }
}

// MARK: - Gemini / Antigravity Companion Service
// Lumo operates as a companion for the Antigravity CLI (`agy`).
// Model inference is executed natively via Google Gemini models (Gemini 3.8 Flash, Pro, Ultra).

@MainActor
final class GeminiService {
    static let shared = GeminiService()

    var apiKey: String? { nil }

    func clearConversation() {
        AppState.shared.chatHistory.removeAll()
    }

    private func resolveAgyPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/agy",
            "/usr/local/bin/agy",
            "/opt/homebrew/bin/agy",
            "\(home)/bin/agy"
        ]
        for p in candidates {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        // Fallback to which agy
        let whichProc = Process()
        whichProc.launchPath = "/usr/bin/which"
        whichProc.arguments = ["agy"]
        let pipe = Pipe()
        whichProc.standardOutput = pipe
        try? whichProc.run()
        whichProc.waitUntilExit()
        if whichProc.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !str.isEmpty, FileManager.default.isExecutableFile(atPath: str) {
                return str
            }
        }
        return nil
    }

    func chat(query: String, context: PromptContext?, state: AppState, sessionId: UUID? = nil) async {
        let targetId = sessionId ?? state.activeSessionId
        guard let agyPath = resolveAgyPath() else {
            state.setSessionThinking(sessionId: targetId, thinking: false)
            state.appendMessage(to: targetId, message: ChatMessage(role: .assistant, content: "Could not locate `agy` executable. Please verify that Antigravity CLI is installed at ~/.local/bin/agy."))
            return
        }

        var fullPrompt = query
        if let ctx = context {
            switch ctx {
            case .window(let appName, let title, let url):
                let urlStr = url.map { " (\($0))" } ?? ""
                fullPrompt = "[Context: App: \(appName), Window: \(title)\(urlStr)]\n\n" + query
            case .file(let name, let fileURL):
                if let url = fileURL, let fileData = try? String(contentsOf: url, encoding: .utf8) {
                    fullPrompt = "[Attached file \(name):\n\(fileData.prefix(500))]\n\n" + query
                } else {
                    fullPrompt = "[Attached file: \(name)]\n\n" + query
                }
            }
        }

        state.setSessionThinking(sessionId: targetId, thinking: true)

        let targetModel = state.chatSessions.first(where: { $0.id == targetId })?.model ?? state.selectedModel
        let targetEffort = state.chatSessions.first(where: { $0.id == targetId })?.effort ?? state.selectedEffort

        let result: String = await Task.detached(priority: .userInitiated) { [targetModel, targetEffort] () -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: agyPath)
            
            var args = ["-c"]
            if !targetModel.isEmpty {
                args.append(contentsOf: ["--model", targetModel])
            }
            if !targetEffort.isEmpty {
                args.append(contentsOf: ["--effort", targetEffort])
            }
            args.append(contentsOf: ["-p", fullPrompt])
            process.arguments = args

            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let currentPath = env["PATH"] ?? ""
            env["PATH"] = "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\(currentPath)"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let outString = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errString = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !outString.isEmpty {
                    return outString
                } else if !errString.isEmpty {
                    return errString
                } else {
                    return "No response from Antigravity."
                }
            } catch {
                return "Failed to run agy: \(error.localizedDescription)"
            }
        }.value

        state.setSessionThinking(sessionId: targetId, thinking: false)
        state.appendMessage(to: targetId, message: ChatMessage(role: .assistant, content: result))
        SoundEngine.shared.play("finish")
        VoiceManager.shared.speak(result)

        if state.view != .prompt {
            state.updateTask(id: "integration_gemini", state: .finished)
            if let taskIdx = state.tasks.firstIndex(where: { $0.id == "integration_gemini" }) {
                state.tasks[taskIdx].steps.append("\(targetModel) response ready")
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if state.mode == .expanded {
                    state.view = .finished
                } else {
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.finished)
                }
            }
        }
    }
}



import Foundation
import Security
import AppKit

// MARK: - GeminiService (Native Google Gemini Engine for Lumo)
// Supports Gemini 2.5 Flash and Pro via Google AI Studio API.

@MainActor
final class GeminiService {
    static let shared = GeminiService()

    private let apiBase = "https://generativelanguage.googleapis.com/v1beta/models"

    var apiKey: String? {
        KeychainStore.shared.get("gemini-api-key") ?? KeychainStore.shared.get("anthropic-api-key")
    }

    var selectedModel: String {
        KeychainStore.shared.get("gemini-model") ?? "gemini-2.5-flash"
    }

    // Multi-turn conversation messages
    private var conversationHistory: [[String: Any]] = []

    func clearConversation() {
        conversationHistory = []
    }

    private let systemInstruction = """
    You are Lumo, an intelligent, friendly native macOS desktop companion living in the MacBook notch. \
    You assist developers with coding, terminal tasks, questions, and workspace context. \
    Respond concisely and directly. \
    Format response as clean readable text. If appropriate, return a JSON object with:
    {"title": "Brief title", "items": [{"label": "Action or fact", "detail": "Description"}], "note": "Optional footnote"}
    """

    // MARK: - Chat Execution

    func chat(query: String, context: PromptContext?, state: AppState) async {
        guard let key = apiKey, !key.isEmpty else {
            await showError("Gemini API key missing. Open settings.", state: state)
            return
        }

        state.view = .searching
        state.stateOverride = .thinking

        // Build parts for current turn
        var parts: [[String: Any]] = []

        // Context (window title / attached file)
        if conversationHistory.isEmpty, let context = context {
            switch context {
            case .window(let app, let title, let url):
                var ctx = "Context: Active App '\(app)', Window '\(title)'"
                if let url = url { ctx += ", URL: \(url)" }
                parts.append(["text": ctx])
            case .file(let name, let fileURL):
                if let fileURL = fileURL, let block = readFileAsPart(url: fileURL) {
                    parts.append(block)
                }
                parts.append(["text": "Attached file: \(name)"])
            }
        }

        parts.append(["text": query])

        // Add to history
        conversationHistory.append(["role": "user", "parts": parts])

        let model = selectedModel
        guard let url = URL(string: "\(apiBase)/\(model):generateContent?key=\(key)") else {
            await showError("Invalid API endpoint URL.", state: state)
            return
        }

        let requestBody: [String: Any] = [
            "contents": conversationHistory,
            "systemInstruction": [
                "parts": [["text": systemInstruction]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            await showError("Serialization error.", state: state)
            return
        }
        req.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0

            guard code == 200 else {
                let errText = String(data: data, encoding: .utf8) ?? "Unknown HTTP \(code)"
                await showError("Gemini error (\(code)): \(errText.prefix(60))", state: state)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let responseParts = content["parts"] as? [[String: Any]],
                  let firstPart = responseParts.first,
                  let text = firstPart["text"] as? String else {
                await showError("Unexpected Gemini response structure.", state: state)
                return
            }

            // Save assistant reply in conversation history
            conversationHistory.append(["role": "model", "parts": [["text": text]]])

            // Parse response into UI SearchResult
            parseAndDisplayResult(text: text, state: state)

        } catch {
            await showError("Network error: \(error.localizedDescription)", state: state)
        }
    }

    private func parseAndDisplayResult(text: String, state: AppState) {
        let cleanText: String
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            cleanText = String(text[start...end])
        } else {
            cleanText = text
        }

        if let resultData = cleanText.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
            let title = parsed["title"] as? String ?? "Gemini"
            let note  = parsed["note"] as? String
            var items: [ResultItem] = []
            if let rawItems = parsed["items"] as? [[String: Any]] {
                for item in rawItems.prefix(3) {
                    items.append(ResultItem(
                        label:  item["label"]  as? String ?? "",
                        detail: item["detail"] as? String ?? "",
                        url:    item["url"]    as? String
                    ))
                }
            }
            state.searchResult = SearchResult(title: title, items: items, note: note)
        } else {
            let lines = cleanText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(3)
            state.searchResult = SearchResult(
                title: "Gemini",
                items: lines.map { ResultItem(label: $0, detail: "", url: nil) },
                note: nil
            )
        }

        state.stateOverride = nil
        state.view = .result
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
    }

    private func showError(_ message: String, state: AppState) async {
        state.stateOverride = .error
        state.noteMessage = message
        state.view = .note
    }

    private func readFileAsPart(url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()

        if ["jpg", "jpeg", "png", "webp"].contains(ext) {
            let mime = ext == "png" ? "image/png" : (ext == "webp" ? "image/webp" : "image/jpeg")
            return [
                "inlineData": [
                    "mimeType": mime,
                    "data": data.base64EncodedString()
                ]
            ]
        } else if ext == "pdf" {
            return [
                "inlineData": [
                    "mimeType": "application/pdf",
                    "data": data.base64EncodedString()
                ]
            ]
        } else {
            guard data.count <= 250_000,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return ["text": "File contents (\(url.lastPathComponent)):\n\(text)"]
        }
    }
}

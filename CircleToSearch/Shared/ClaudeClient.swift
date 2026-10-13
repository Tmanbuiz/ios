import Foundation

struct Source: Identifiable, Hashable {
    let title: String
    let url: URL
    var id: URL { url }
}

enum ClaudeEvent {
    case text(String)
    case searching
    case source(Source)
    case refused
}

struct ClaudeError: LocalizedError {
    let errorDescription: String?
}

/// Streams an answer from the Claude Messages API so text appears word by word.
enum ClaudeClient {
    // Kept constant across follow-ups so the conversation history stays valid.
    static let systemPrompt = """
    You are a visual search assistant, like Google's Circle to Search. The user circled, highlighted or tapped \
    part of their iPhone screen. The first image is their selection; a second image, if present, is the whole \
    screen for context.
    In your first reply, start with one line formatted as "# " followed by a short name for what is selected \
    (a product, place, landmark, plant, word, error message, etc.). Then give a concise, useful overview in a few \
    short paragraphs or bullets: what it is, key facts, and anything actionable such as prices, where to get it, \
    meaning, or how to do it. Use web search when current or factual information would help.
    Don't identify real people from their faces.
    For follow-up questions, answer directly without the title line.
    """

    static func stream(messages: [[String: Any]]) -> AsyncThrowingStream<ClaudeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: Any] = [
                        "model": Config.model,
                        "max_tokens": 16000,
                        "stream": true,
                        "output_config": ["effort": "low"],   // fast answers; use "medium" for deeper ones
                        "fallbacks": "default",               // retries on another model if a request is declined
                        "system": systemPrompt,
                        "messages": messages,
                    ]
                    if Config.useWebSearch {
                        body["tools"] = [["type": "web_search_20260209", "name": "web_search", "max_uses": 3]]
                    }

                    var request = URLRequest(url: Config.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 180
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(Config.apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw ClaudeError(errorDescription: errorMessage(from: data) ?? "Request failed (\(status))")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }

                        switch event["type"] as? String {
                        case "content_block_start":
                            let block = event["content_block"] as? [String: Any] ?? [:]
                            switch block["type"] as? String {
                            case "server_tool_use":
                                continuation.yield(.searching)
                            case "web_search_tool_result":
                                // On success `content` is a list of results; on error it's a single object.
                                for result in block["content"] as? [[String: Any]] ?? [] {
                                    guard let link = result["url"] as? String, let url = URL(string: link) else { continue }
                                    let title = result["title"] as? String ?? url.host() ?? link
                                    continuation.yield(.source(Source(title: title, url: url)))
                                }
                            default:
                                break
                            }
                        case "content_block_delta":
                            let delta = event["delta"] as? [String: Any] ?? [:]
                            if delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                                continuation.yield(.text(text))
                            }
                        case "message_delta":
                            let delta = event["delta"] as? [String: Any] ?? [:]
                            if delta["stop_reason"] as? String == "refusal" {
                                continuation.yield(.refused)
                            }
                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String
                            throw ClaudeError(errorDescription: message ?? "The answer was interrupted.")
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (json?["error"] as? [String: Any])?["message"] as? String
    }
}

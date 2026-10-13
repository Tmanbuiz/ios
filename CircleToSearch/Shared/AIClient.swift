import Foundation

struct Source: Identifiable, Hashable {
    let title: String
    let url: URL
    var id: URL { url }
}

/// One turn of the conversation, independent of which AI answers it.
struct AIMessage {
    let isUser: Bool
    let text: String
    var images: [Data] = []   // JPEG
}

enum AIEvent {
    case text(String)
    case searching
    case source(Source)
    case refused
}

struct AIError: LocalizedError {
    let errorDescription: String?
}

/// Streams an answer from Claude, ChatGPT, Gemini or Grok so text appears word by word.
enum AIClient {
    // Kept constant across follow-ups so the conversation history stays valid.
    static let systemPrompt = """
    You are a visual search assistant, like Google's Circle to Search. The user circled, highlighted or tapped \
    part of their iPhone screen. The first image is their selection; a second image, if present, is the whole \
    screen for context.
    In your first reply, start with one line formatted as "# " followed by a short name for what is selected \
    (a product, place, landmark, plant, word, error message, etc.). Then give a concise, useful overview in a few \
    short paragraphs or bullets: what it is, key facts, and anything actionable such as prices, where to get it, \
    meaning, or how to do it. Search the web when you can and current or factual information would help.
    Don't identify real people from their faces.
    For follow-up questions, answer directly without the title line.
    """

    struct Options {
        let provider: AIProvider
        let key: String
        let model: String
        let webSearch: Bool
    }

    static func stream(_ messages: [AIMessage], options: Options) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(messages, options: options)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw AIError(errorDescription: errorMessage(from: data, provider: options.provider, status: status))
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
                        let events: [AIEvent]
                        switch options.provider {
                        case .claude: events = try parseClaude(event)
                        case .chatgpt, .grok: events = try parseOpenAIStyle(event)
                        case .gemini: events = try parseGemini(event)
                        }
                        events.forEach { continuation.yield($0) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Requests

    private static func makeRequest(_ messages: [AIMessage], options: Options) throws -> URLRequest {
        let url: URL
        var headers = ["content-type": "application/json"]
        let body: [String: Any]

        switch options.provider {
        case .claude:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers["x-api-key"] = options.key
            headers["anthropic-version"] = "2023-06-01"
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
            var b: [String: Any] = [
                "model": options.model,
                "max_tokens": 16000,
                "stream": true,
                "output_config": ["effort": "low"],   // fast answers; use "medium" for deeper ones
                "fallbacks": "default",               // retries on another model if a request is declined
                "system": systemPrompt,
                "messages": messages.map { m -> [String: Any] in
                    var content: [[String: Any]] = m.images.map {
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
                    }
                    content.append(["type": "text", "text": m.text])
                    return ["role": m.isUser ? "user" : "assistant", "content": content]
                },
            ]
            if options.webSearch {
                b["tools"] = [["type": "web_search_20260209", "name": "web_search", "max_uses": 3]]
            }
            body = b

        case .chatgpt, .grok:
            url = URL(string: options.provider == .grok
                      ? "https://api.x.ai/v1/chat/completions"
                      : "https://api.openai.com/v1/chat/completions")!
            headers["authorization"] = "Bearer \(options.key)"
            var chat: [[String: Any]] = [["role": "system", "content": systemPrompt]]
            for m in messages {
                if m.isUser {
                    var content: [[String: Any]] = m.images.map {
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\($0.base64EncodedString())"]]
                    }
                    content.append(["type": "text", "text": m.text])
                    chat.append(["role": "user", "content": content])
                } else {
                    chat.append(["role": "assistant", "content": m.text])
                }
            }
            body = ["model": options.model, "stream": true, "messages": chat]

        case .gemini:
            let model = options.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? options.model
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!
            headers["x-goog-api-key"] = options.key
            var b: [String: Any] = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": messages.map { m -> [String: Any] in
                    var parts: [[String: Any]] = m.images.map {
                        ["inline_data": ["mime_type": "image/jpeg", "data": $0.base64EncodedString()]]
                    }
                    parts.append(["text": m.text])
                    return ["role": m.isUser ? "user" : "model", "parts": parts]
                },
            ]
            if options.webSearch { b["tools"] = [["google_search": [String: Any]()]] }
            body = b
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Stream parsers

    private static func parseClaude(_ event: [String: Any]) throws -> [AIEvent] {
        switch event["type"] as? String {
        case "content_block_start":
            let block = event["content_block"] as? [String: Any] ?? [:]
            switch block["type"] as? String {
            case "server_tool_use":
                return [.searching]
            case "web_search_tool_result":
                // On success `content` is a list of results; on error it's a single object.
                return (block["content"] as? [[String: Any]] ?? []).compactMap { result in
                    guard let link = result["url"] as? String, let url = URL(string: link) else { return nil }
                    return .source(Source(title: result["title"] as? String ?? url.host() ?? link, url: url))
                }
            default:
                return []
            }
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any] ?? [:]
            if delta["type"] as? String == "text_delta", let text = delta["text"] as? String { return [.text(text)] }
            return []
        case "message_delta":
            let delta = event["delta"] as? [String: Any] ?? [:]
            return delta["stop_reason"] as? String == "refusal" ? [.refused] : []
        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String
            throw AIError(errorDescription: message ?? "The answer was interrupted.")
        default:
            return []
        }
    }

    private static func parseOpenAIStyle(_ event: [String: Any]) throws -> [AIEvent] {
        if let error = event["error"] as? [String: Any] {
            throw AIError(errorDescription: error["message"] as? String ?? "The answer was interrupted.")
        }
        guard let choice = (event["choices"] as? [[String: Any]])?.first else { return [] }
        var events: [AIEvent] = []
        if let text = (choice["delta"] as? [String: Any])?["content"] as? String, !text.isEmpty {
            events.append(.text(text))
        }
        if choice["finish_reason"] as? String == "content_filter" { events.append(.refused) }
        return events
    }

    private static func parseGemini(_ event: [String: Any]) throws -> [AIEvent] {
        if let error = event["error"] as? [String: Any] {
            throw AIError(errorDescription: error["message"] as? String ?? "The answer was interrupted.")
        }
        guard let candidate = (event["candidates"] as? [[String: Any]])?.first else {
            let blocked = (event["promptFeedback"] as? [String: Any])?["blockReason"] != nil
            return blocked ? [.refused] : []
        }
        var events: [AIEvent] = []
        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        for part in parts {
            if let text = part["text"] as? String, part["thought"] as? Bool != true { events.append(.text(text)) }
        }
        let chunks = (candidate["groundingMetadata"] as? [String: Any])?["groundingChunks"] as? [[String: Any]] ?? []
        for chunk in chunks {
            guard let web = chunk["web"] as? [String: Any],
                  let link = web["uri"] as? String, let url = URL(string: link) else { continue }
            events.append(.source(Source(title: web["title"] as? String ?? url.host() ?? link, url: url)))
        }
        if ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST"].contains(candidate["finishReason"] as? String ?? "") {
            events.append(.refused)
        }
        return events
    }

    private static func errorMessage(from data: Data, provider: AIProvider, status: Int) -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (json?["error"] as? [String: Any])?["message"] as? String ?? json?["error"] as? String
        let keyProblem = status == 401 || status == 403 || (message ?? "").localizedCaseInsensitiveContains("api key")
        if keyProblem {
            return "\(provider.name) didn't accept the API key. Open Settings and tap Test key." + (message.map { "\n\($0)" } ?? "")
        }
        return message ?? "\(provider.name) request failed (\(status))."
    }

    // MARK: Key check

    /// Makes a free request (listing models) to check that the provider accepts the key.
    static func testKey(provider: AIProvider, key: String) async -> (ok: Bool, message: String) {
        var request: URLRequest
        switch provider {
        case .claude:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .chatgpt:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        case .grok:
            request = URLRequest(url: URL(string: "https://api.x.ai/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return (true, "\(provider.name) accepted this key.") }
            return (false, errorMessage(from: data, provider: provider, status: status))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

import Foundation

// MARK: - Config

struct LLMConfig {
    let provider: LLMProvider
    let apiKey: String
    let model: String
    let baseURL: String  // used by Ollama / LM Studio
}

// MARK: - Service

actor LLMService {
    private let session: URLSession

    init(session: URLSession = NetworkSessionFactory.makeEphemeralSession()) {
        self.session = session
    }

    func complete(
        prompt: String,
        systemPrompt: String,
        config: LLMConfig
    ) async throws -> String {
        switch config.provider {
        case .claude:
            return try await claudeComplete(prompt: prompt, systemPrompt: systemPrompt, config: config)
        case .openAI, .openRouter, .ollama, .lmStudio:
            return try await openAIComplete(prompt: prompt, systemPrompt: systemPrompt, config: config)
        }
    }

    // MARK: - Anthropic

    private struct AnthropicRequest: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [AnthropicMessage]
        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }
    }
    private struct AnthropicMessage: Encodable {
        let role: String
        let content: String
    }
    private struct AnthropicResponse: Decodable {
        let content: [ContentBlock]
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        var text: String { content.compactMap(\.text).joined() }
    }

    private func claudeComplete(prompt: String, systemPrompt: String, config: LLMConfig) async throws -> String {
        guard !config.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LLMError.noApiKey
        }
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(AnthropicRequest(
            model: config.model,
            maxTokens: 2048,
            system: systemPrompt,
            messages: [AnthropicMessage(role: "user", content: prompt)]
        ))
        let (data, response) = try await session.data(for: req)
        try checkHTTP(response, data)
        return try JSONDecoder().decode(AnthropicResponse.self, from: data).text
    }

    // MARK: - OpenAI-compatible (OpenRouter / Ollama / LM Studio)

    private struct OAIRequest: Encodable {
        let model: String
        let messages: [OAIMessage]
    }
    private struct OAIMessage: Encodable {
        let role: String
        let content: String
    }
    private struct OAIResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: OAIMessage
        }
        struct OAIMessage: Decodable {
            let content: String
        }
        var text: String { choices.first?.message.content ?? "" }
    }

    private func openAIComplete(prompt: String, systemPrompt: String, config: LLMConfig) async throws -> String {
        if config.provider.requiresApiKey,
           config.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            throw LLMError.noApiKey
        }
        let url = try Self.resolveChatCompletionsURL(for: config)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(OAIRequest(
            model: config.model,
            messages: [
                OAIMessage(role: "system", content: systemPrompt),
                OAIMessage(role: "user", content: prompt)
            ]
        ))
        let (data, response) = try await session.data(for: req)
        try checkHTTP(response, data)
        return try JSONDecoder().decode(OAIResponse.self, from: data).text
    }

    // MARK: - Helpers

    private static func resolveChatCompletionsURL(for config: LLMConfig) throws -> URL {
        let rawBase = rawBaseURL(for: config.provider, configuredBaseURL: config.baseURL)
        guard var components = URLComponents(string: rawBase) else {
            throw LLMError.invalidResponse
        }

        let normalizedPath = normalizedChatCompletionsPath(
            provider: config.provider,
            existingPath: components.path
        )
        components.path = normalizedPath

        guard let url = components.url else {
            throw LLMError.invalidResponse
        }
        return url
    }

    private static func rawBaseURL(for provider: LLMProvider, configuredBaseURL: String) -> String {
        let raw = configuredBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .openAI:
            return raw.isEmpty ? "https://api.openai.com/v1" : raw
        case .openRouter:
            return raw.isEmpty ? "https://openrouter.ai/api/v1" : raw
        case .ollama, .lmStudio:
            return raw.isEmpty ? provider.defaultBaseURL : raw
        case .claude:
            return raw
        }
    }

    private static func normalizedChatCompletionsPath(provider: LLMProvider, existingPath: String) -> String {
        let trimmed = existingPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmed.hasSuffix("chat/completions") {
            return "/" + trimmed
        }

        switch provider {
        case .openAI, .openRouter:
            if trimmed.isEmpty {
                return "/v1/chat/completions"
            }
            if trimmed == "v1" {
                return "/v1/chat/completions"
            }
            return "/" + trimmed + "/chat/completions"
        case .ollama, .lmStudio:
            if trimmed.isEmpty {
                return "/v1/chat/completions"
            }
            if trimmed == "v1" {
                return "/v1/chat/completions"
            }
            return "/" + trimmed + "/v1/chat/completions"
        case .claude:
            return existingPath
        }
    }

    private func checkHTTP(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw LLMError.httpError(http.statusCode, body)
        }
    }
}

extension LLMService {
    static func debugResolvedChatCompletionsURL(for config: LLMConfig) throws -> URL {
        try resolveChatCompletionsURL(for: config)
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case noApiKey
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No API key configured. Open Settings (⌘,) to add your key."
        case .invalidResponse:
            return "Invalid response received from the API."
        case .httpError(let code, let body):
            return "API request failed (\(code)): \(body.prefix(300))"
        }
    }
}

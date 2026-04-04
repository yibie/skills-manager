import Foundation

actor LLMService {

    // MARK: - Encodable request

    private struct APIRequest: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [APIMessage]

        enum CodingKeys: String, CodingKey {
            case model, system, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct APIMessage: Encodable {
        let role: String
        let content: String
    }

    // MARK: - Decodable response

    private struct APIResponse: Decodable {
        let content: [ContentBlock]

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        var text: String {
            content.compactMap(\.text).joined()
        }
    }

    // MARK: - Public API

    /// Sends a prompt + optional skill system prompt to Claude Messages API.
    func complete(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String = AppSettings.defaultModel
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LLMError.noApiKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body = APIRequest(
            model: model,
            maxTokens: 2048,
            system: systemPrompt,
            messages: [APIMessage(role: "user", content: prompt)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw LLMError.httpError(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        return decoded.text
    }
}

enum LLMError: LocalizedError {
    case noApiKey
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No Claude API key configured. Open Settings (⌘,) to add your key."
        case .invalidResponse:
            return "Invalid response received from the API."
        case .httpError(let code, let body):
            return "API request failed (\(code)): \(body.prefix(300))"
        }
    }
}

import Foundation

enum LLMProvider: String, CaseIterable {
    case claude      = "claude"
    case openAI      = "openai"
    case openRouter  = "openrouter"
    case ollama      = "ollama"
    case lmStudio    = "lmstudio"

    var displayName: String {
        switch self {
        case .claude:     return "Claude API"
        case .openAI:     return "OpenAI API"
        case .openRouter: return "OpenRouter"
        case .ollama:     return "Ollama"
        case .lmStudio:   return "LM Studio"
        }
    }

    var requiresApiKey: Bool {
        switch self {
        case .claude, .openAI, .openRouter: return true
        case .ollama, .lmStudio:            return false
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama:   return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234"
        default:        return ""
        }
    }
}

enum AppSettings {
    // NOTE: Keys are stored in UserDefaults (@AppStorage) for developer tool simplicity.
    static let claudeApiKeyKey      = "claudeApiKey"
    static let sandboxModelKey      = "sandboxModel"
    static let defaultModel         = "claude-haiku-4-5"

    static let llmProviderKey       = "llmProvider"

    static let openAIApiKeyKey      = "openAIApiKey"
    static let openAIModelKey       = "openAIModel"
    static let openAIBaseURLKey     = "openAIBaseURL"
    static let defaultOpenAIModel   = "gpt-4o-mini"

    static let openRouterApiKeyKey  = "openRouterApiKey"
    static let openRouterModelKey   = "openRouterModel"
    static let defaultOpenRouterModel = "openai/gpt-4o-mini"

    static let ollamaBaseURLKey     = "ollamaBaseURL"
    static let ollamaModelKey       = "ollamaModel"
    static let defaultOllamaModel   = "llama3"

    static let lmStudioBaseURLKey   = "lmStudioBaseURL"
    static let lmStudioModelKey     = "lmStudioModel"
    static let defaultLMStudioModel = "local-model"
}

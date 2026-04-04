import Foundation

enum AppSettings {
    // NOTE: API key is stored in UserDefaults (@AppStorage) for developer tool simplicity.
    // For production use, consider migrating to Keychain (kSecClassGenericPassword).
    static let claudeApiKeyKey = "claudeApiKey"
    static let sandboxModelKey = "sandboxModel"
    static let defaultModel = "claude-haiku-4-5"
}

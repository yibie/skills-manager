import Foundation
import NaturalLanguage

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
        case .ollama:   return "http://127.0.0.1:11434"
        case .lmStudio: return "http://127.0.0.1:1234"
        default:        return ""
        }
    }
}

enum DescriptionLanguageMode: String, CaseIterable {
    case system
    case manual

    var displayName: String {
        switch self {
        case .system: return "Follow System"
        case .manual: return "Manual"
        }
    }
}

struct DescriptionLanguageOption: Identifiable, Hashable {
    let localeIdentifier: String
    let label: String

    var id: String { localeIdentifier }
}

enum DescriptionLocale {
    private static let explicitLocaleKeys = [
        "description_locale",
        "descriptionLocale",
        "description-language",
        "description_language",
        "locale",
        "language",
        "lang",
    ]

    private static let aliases: [String: String] = [
        "english": "en",
        "英文": "en",
        "英语": "en",
        "chinese": "zh-Hans",
        "中文": "zh-Hans",
        "简体": "zh-Hans",
        "简体中文": "zh-Hans",
        "simplified-chinese": "zh-Hans",
        "simplified chinese": "zh-Hans",
        "zh-cn": "zh-Hans",
        "zh-sg": "zh-Hans",
        "zh-my": "zh-Hans",
        "繁體": "zh-Hant",
        "繁体": "zh-Hant",
        "繁體中文": "zh-Hant",
        "繁体中文": "zh-Hant",
        "traditional-chinese": "zh-Hant",
        "traditional chinese": "zh-Hant",
        "zh-tw": "zh-Hant",
        "zh-hk": "zh-Hant",
        "zh-mo": "zh-Hant",
        "japanese": "ja",
        "日本語": "ja",
        "日语": "ja",
        "korean": "ko",
        "한국어": "ko",
        "韩语": "ko",
        "french": "fr",
        "français": "fr",
        "german": "de",
        "deutsch": "de",
        "spanish": "es",
        "español": "es",
    ]

    private static let simplifiedChineseScalars = Set("这为会来过对经个们现发后实还样进开关问题学国时说没给让从将门间与无见电车长马风东话处声点买卖体网线云台页机级尽变边于优简译广气书区师数应论认设请识读写")
        .flatMap(\.unicodeScalars)
    private static let traditionalChineseScalars = Set("這為會來過對經個們現發後實還樣進開關問題學國時說沒給讓從將門間與無見電車長馬風東話處聲點買賣體網線雲臺頁機級盡變邊於優簡譯廣氣書區師數應論認設請識讀寫")
        .flatMap(\.unicodeScalars)

    static func descriptionLocale(
        frontmatter: [String: String] = [:],
        description: String,
        defaultLocale: String = "en"
    ) -> String {
        for key in explicitLocaleKeys {
            guard let raw = frontmatter[key] else { continue }
            if let locale = normalizedExplicitLocale(raw) {
                return locale
            }
        }

        if let detected = detectedTextLocale(description) {
            return detected
        }

        return normalizedIdentifier(defaultLocale)
    }

    static func shouldTranslate(sourceLocale: String, targetLocale: String) -> Bool {
        !isSameDisplayLanguage(sourceLocale, targetLocale)
    }

    static func isSameDisplayLanguage(_ lhs: String, _ rhs: String) -> Bool {
        let lhsNormalized = normalizedIdentifier(lhs)
        let rhsNormalized = normalizedIdentifier(rhs)
        let lhsPrimary = primaryLanguageCode(for: lhsNormalized)
        let rhsPrimary = primaryLanguageCode(for: rhsNormalized)
        guard !lhsPrimary.isEmpty, lhsPrimary == rhsPrimary else { return false }

        if lhsPrimary == "zh" {
            let lhsScript = chineseScriptCode(for: lhsNormalized)
            let rhsScript = chineseScriptCode(for: rhsNormalized)
            if let lhsScript, let rhsScript, lhsScript != rhsScript {
                return false
            }
        }

        return true
    }

    static func normalizedIdentifier(_ identifier: String) -> String {
        let trimmed = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        guard !trimmed.isEmpty else { return trimmed }

        if let alias = aliases[trimmed.lowercased()] {
            return alias
        }

        let parts = trimmed.split(separator: "-").map(String.init)
        guard let first = parts.first else { return trimmed }

        var output = [first.lowercased()]
        for part in parts.dropFirst() {
            if part.count == 4 {
                output.append(part.prefix(1).uppercased() + part.dropFirst().lowercased())
            } else if part.count == 2 || part.count == 3 {
                output.append(part.uppercased())
            } else {
                output.append(part)
            }
        }
        return output.joined(separator: "-")
    }

    static func primaryLanguageCode(for locale: String) -> String {
        normalizedIdentifier(locale)
            .split(separator: "-")
            .first
            .map { String($0).lowercased() } ?? ""
    }

    private static func normalizedExplicitLocale(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let alias = aliases[trimmed.lowercased()] {
            return alias
        }

        let normalized = normalizedIdentifier(trimmed)
        let primary = primaryLanguageCode(for: normalized)
        guard primary.count == 2 || primary.count == 3 else { return nil }
        return normalized
    }

    private static func detectedTextLocale(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }

        if let cjkLocale = cjkLocale(for: trimmed) {
            return cjkLocale
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let best = hypotheses.max(by: { $0.value < $1.value }), best.value >= 0.45 else {
            return nil
        }

        let rawValue = best.key.rawValue
        guard rawValue != NLLanguage.undetermined.rawValue else { return nil }
        return normalizedIdentifier(rawValue)
    }

    private static func cjkLocale(for text: String) -> String? {
        var hanCount = 0
        var kanaCount = 0
        var hangulCount = 0
        var simplifiedCount = 0
        var traditionalCount = 0
        var letterCount = 0

        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                letterCount += 1
            }

            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF:
                kanaCount += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F:
                hangulCount += 1
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                hanCount += 1
                if simplifiedChineseScalars.contains(scalar) { simplifiedCount += 1 }
                if traditionalChineseScalars.contains(scalar) { traditionalCount += 1 }
            default:
                continue
            }
        }

        let cjkCount = hanCount + kanaCount + hangulCount
        guard cjkCount >= 2 else { return nil }
        let cjkRatio = Double(cjkCount) / Double(max(letterCount, 1))
        guard cjkRatio >= 0.2 else { return nil }

        if hangulCount > 0, hangulCount >= hanCount, hangulCount >= kanaCount {
            return "ko"
        }
        if kanaCount > 0 {
            return "ja"
        }
        if hanCount > 0 {
            return traditionalCount > simplifiedCount ? "zh-Hant" : "zh-Hans"
        }
        return nil
    }

    private static func chineseScriptCode(for locale: String) -> String? {
        let parts = normalizedIdentifier(locale).split(separator: "-").map { String($0) }
        guard parts.first == "zh" else { return nil }

        for part in parts.dropFirst() {
            switch part.lowercased() {
            case "hans": return "Hans"
            case "hant": return "Hant"
            case "cn", "sg", "my": return "Hans"
            case "tw", "hk", "mo": return "Hant"
            default: continue
            }
        }
        return nil
    }
}

enum AppSettings {
    // NOTE: API keys are stored in the Keychain (see KeychainService); these are only
    // the account names. Non-secret preferences stay in UserDefaults (@AppStorage).
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

    static let descriptionLanguageModeKey = "descriptionLanguageMode"
    static let manualDescriptionLocaleKey = "manualDescriptionLocale"

    static let importedAgentFoldersKey = "importedAgentFolders"

    /// One-time migration: move API keys previously stored in UserDefaults into the
    /// Keychain, then remove the plaintext copies. Safe to call on every launch.
    static func migrateApiKeysToKeychainIfNeeded(defaults: UserDefaults = .standard) {
        for key in [claudeApiKeyKey, openAIApiKeyKey, openRouterApiKeyKey] {
            guard let value = defaults.string(forKey: key), !value.isEmpty else { continue }
            if KeychainService.string(forKey: key) == nil {
                KeychainService.setString(value, forKey: key)
            }
            defaults.removeObject(forKey: key)
        }
    }

    static func currentDescriptionLocale(defaults: UserDefaults = .standard, locale: Locale = .autoupdatingCurrent) -> String {
        let mode = DescriptionLanguageMode(rawValue: defaults.string(forKey: descriptionLanguageModeKey) ?? "") ?? .system
        switch mode {
        case .manual:
            let manual = defaults.string(forKey: manualDescriptionLocaleKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let option = descriptionLanguageOptions.first(where: { normalizedLocaleIdentifier($0.localeIdentifier) == normalizedLocaleIdentifier(manual) }) {
                return normalizedLocaleIdentifier(option.localeIdentifier)
            }
            return normalizedSystemLocaleIdentifier(locale)
        case .system:
            return normalizedSystemLocaleIdentifier(locale)
        }
    }

    static let descriptionLanguageOptions: [DescriptionLanguageOption] = [
        DescriptionLanguageOption(localeIdentifier: "en", label: "English"),
        DescriptionLanguageOption(localeIdentifier: "zh-Hans", label: "简体中文"),
        DescriptionLanguageOption(localeIdentifier: "zh-Hant", label: "繁體中文"),
        DescriptionLanguageOption(localeIdentifier: "ja", label: "日本語"),
        DescriptionLanguageOption(localeIdentifier: "ko", label: "한국어"),
        DescriptionLanguageOption(localeIdentifier: "fr", label: "Français"),
        DescriptionLanguageOption(localeIdentifier: "de", label: "Deutsch"),
        DescriptionLanguageOption(localeIdentifier: "es", label: "Español"),
    ]

    static func currentLLMConfig(defaults: UserDefaults = .standard) -> LLMConfig {
        let provider = LLMProvider(rawValue: defaults.string(forKey: llmProviderKey) ?? "") ?? .claude
        switch provider {
        case .claude:
            return LLMConfig(
                provider: .claude,
                apiKey: KeychainService.string(forKey: claudeApiKeyKey) ?? "",
                model: defaults.string(forKey: sandboxModelKey) ?? defaultModel,
                baseURL: ""
            )
        case .openAI:
            return LLMConfig(
                provider: .openAI,
                apiKey: KeychainService.string(forKey: openAIApiKeyKey) ?? "",
                model: defaults.string(forKey: openAIModelKey) ?? defaultOpenAIModel,
                baseURL: defaults.string(forKey: openAIBaseURLKey) ?? ""
            )
        case .openRouter:
            return LLMConfig(
                provider: .openRouter,
                apiKey: KeychainService.string(forKey: openRouterApiKeyKey) ?? "",
                model: defaults.string(forKey: openRouterModelKey) ?? defaultOpenRouterModel,
                baseURL: ""
            )
        case .ollama:
            return LLMConfig(
                provider: .ollama,
                apiKey: "",
                model: defaults.string(forKey: ollamaModelKey) ?? defaultOllamaModel,
                baseURL: defaults.string(forKey: ollamaBaseURLKey) ?? LLMProvider.ollama.defaultBaseURL
            )
        case .lmStudio:
            return LLMConfig(
                provider: .lmStudio,
                apiKey: "",
                model: defaults.string(forKey: lmStudioModelKey) ?? defaultLMStudioModel,
                baseURL: defaults.string(forKey: lmStudioBaseURLKey) ?? LLMProvider.lmStudio.defaultBaseURL
            )
        }
    }

    private static func normalizedLocaleIdentifier(_ identifier: String) -> String {
        DescriptionLocale.normalizedIdentifier(identifier)
    }

    private static func normalizedSystemLocaleIdentifier(_ locale: Locale) -> String {
        guard let languageCode = locale.language.languageCode?.identifier else {
            return normalizedLocaleIdentifier(locale.identifier)
        }

        var segments = [languageCode]
        if let script = locale.language.script?.identifier, !script.isEmpty {
            segments.append(script)
        }
        if let region = locale.region?.identifier, !region.isEmpty {
            segments.append(region)
        }

        return DescriptionLocale.normalizedIdentifier(segments.joined(separator: "-"))
    }
}

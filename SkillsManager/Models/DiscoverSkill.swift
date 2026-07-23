import Foundation

/// Entry shown in Discover, sourced from https://skills.sh/.
struct DiscoverSkill: Identifiable, Sendable {
    let id: String              // "{source}:{skillId}"
    var source: String          // GitHub repo, e.g. vercel-labs/agent-skills
    var skillId: String
    var name: String
    var installs: Int
    var repoURL: URL
    var repositoryRef: String? = nil
    var installCommand: String
    var baseDescription: String?
    var baseDescriptionLocale: String = "en"
    var localizedDescription: String?
    var readmeExcerpt: String?

    var summary: String? {
        let value = localizedDescription ?? baseDescription
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    var isDescriptionTranslated: Bool {
        guard let localizedDescription, let baseDescription else { return false }
        return localizedDescription != baseDescription
    }

    var detailURL: URL {
        URL(string: "https://skills.sh/\(source)/\(skillId)")!
    }
}

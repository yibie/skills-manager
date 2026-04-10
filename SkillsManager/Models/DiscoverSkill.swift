import Foundation

/// Entry shown in Discover, sourced from https://skills.sh/.
struct DiscoverSkill: Identifiable, Sendable {
    let id: String              // "{source}:{skillId}"
    var source: String          // GitHub repo, e.g. vercel-labs/agent-skills
    var skillId: String
    var name: String
    var installs: Int
    var repoURL: URL
    var installCommand: String
    var summary: String?
    var readmeExcerpt: String?

    var detailURL: URL {
        URL(string: "https://skills.sh/\(source)/\(skillId)")!
    }
}

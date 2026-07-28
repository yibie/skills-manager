import Foundation

/// Discover 条目与库内技能的对应关系。
/// 同名不是充分证据:"Installed" 徽章与"从库中删除"都必须建立在 provenance 精确对应上,
/// 否则用户手写的同名技能会被误标、误删。
enum DiscoverLibraryMatch: Equatable, Sendable {
    case installed(Skill)   // provenance(skillID + 仓库来源)与该条目对应
    case sameNameOnly       // 仅名字相同:来源不同或来源未知,不得当作已安装
    case none
}

enum DiscoverLibraryMatcher {
    static func match(entry: DiscoverSkill, in skills: [Skill]) -> DiscoverLibraryMatch {
        if let exact = skills.first(where: { provenanceMatches($0, entry: entry) }) {
            return .installed(exact)
        }
        if skills.contains(where: { $0.name == entry.skillId || $0.name == entry.name }) {
            return .sameNameOnly
        }
        return .none
    }

    static func isInstalled(entry: DiscoverSkill, in skills: [Skill]) -> Bool {
        if case .installed = match(entry: entry, in: skills) { return true }
        return false
    }

    static func provenanceMatches(_ skill: Skill, entry: DiscoverSkill) -> Bool {
        guard let skillID = skill.provenance.skillID,
              let sourceURL = skill.provenance.sourceURL,
              skillID == entry.skillId,
              let installedRepo = canonicalGitHubRepoIdentity(sourceURL)
        else { return false }
        let entrySourceRepo = URL(string: "https://github.com/\(entry.source)")
            .flatMap(canonicalGitHubRepoIdentity)
        return installedRepo == canonicalGitHubRepoIdentity(entry.repoURL)
            || installedRepo == entrySourceRepo
    }

    /// 归一成 "owner/repo"(小写、去 .git,忽略 scheme/query/fragment);非 GitHub owner/repo 返回 nil。
    static func canonicalGitHubRepoIdentity(_ url: URL) -> String? {
        guard url.host?.lowercased() == "github.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let repo = parts[1].lowercased().hasSuffix(".git")
            ? String(parts[1].dropLast(4))
            : parts[1]
        return "\(parts[0])/\(repo)".lowercased()
    }
}

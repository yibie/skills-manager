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
              let installedRepo = repoSlug(sourceURL)
        else { return false }
        return installedRepo == entry.source.lowercased() || installedRepo == repoSlug(entry.repoURL)
    }

    /// 归一成 "owner/repo"(小写、去 .git);非 owner/repo 形态(本地路径等)返回 nil。
    static func repoSlug(_ url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        return "\(parts[0])/\(repo)".lowercased()
    }
}

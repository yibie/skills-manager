import Foundation

struct SkillSearchQuery: Equatable, Sendable {
    var text = ""
    var installState: InstallState?
    var source: String?
    var agent: String?
    var starredOnly = false

    var activeFilterCount: Int {
        [installState != nil, source != nil, agent != nil, starredOnly]
            .filter { $0 }
            .count
    }

    mutating func clearFilters() {
        installState = nil
        source = nil
        agent = nil
        starredOnly = false
    }
}

enum SkillSearch {
    static func results(in skills: [Skill], query: SkillSearchQuery) -> [Skill] {
        let terms = normalized(query.text)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)

        let matches = skills.filter { skill in
            guard query.installState == nil || skill.installState == query.installState else { return false }
            if let source = query.source, sourceName(for: skill) != source { return false }
            if let agent = query.agent, !skill.compatibleAgents.contains(agent) { return false }
            guard !query.starredOnly || skill.isStarred else { return false }
            guard !terms.isEmpty else { return true }

            let index = searchFields(for: skill).map(normalized).joined(separator: " ")
            return terms.allSatisfy(index.contains)
        }

        guard !terms.isEmpty else { return matches }
        let fullQuery = terms.joined(separator: " ")
        return matches.sorted { lhs, rhs in
            let lhsRank = nameRank(for: lhs, query: fullQuery)
            let rhsRank = nameRank(for: rhs, query: fullQuery)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func sourceName(for skill: Skill) -> String {
        switch skill.source {
        case .local:
            "Local"
        case .openClaw:
            "OpenClaw"
        case .symlinked:
            "Symlinked"
        case .plugin(let pluginSource, _):
            pluginSource
        case .projectLocal:
            "Project"
        }
    }

    private static func searchFields(for skill: Skill) -> [String] {
        var fields = [
            skill.id,
            skill.name,
            skill.displayName,
            skill.baseDescription,
            skill.localizedDescription ?? "",
            sourceName(for: skill),
            skill.version ?? ""
        ]
        fields.append(contentsOf: skill.tags)
        fields.append(contentsOf: skill.compatibleAgents)
        if case .plugin(let source, let name) = skill.source {
            fields.append(source)
            fields.append(name)
        }
        return fields
    }

    private static func nameRank(for skill: Skill, query: String) -> Int {
        let name = normalized(skill.name)
        let displayName = normalized(skill.displayName)
        if name == query || displayName == query { return 0 }
        if name.hasPrefix(query) || displayName.hasPrefix(query) { return 1 }
        if name.contains(query) || displayName.contains(query) { return 2 }
        return 3
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }
}

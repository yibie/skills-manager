import Foundation

/// 组成员 id 维护。新写入使用 Skill.persistenceID;读取兼容旧 skill.id。
/// 仅兼容早期 Universal path-keyed 迁移: `universal:/path/to/review`
/// 可重写到精确的 `universal:review`。其他旧 path/source id 保持缺失。
enum CollectionSupport {
    struct Resolution: Equatable {
        var members: [Skill]
        var missingIDs: [String]
        var reconciledIDs: [String]
    }

    static func resolveMemberIDs(_ ids: [String], skills: [Skill]) -> Resolution {
        var members: [Skill] = []
        var missingIDs: [String] = []
        var reconciledIDs: [String] = []

        for id in ids {
            guard let skill = resolveMemberID(id, skills: skills) else {
                missingIDs.append(id)
                reconciledIDs.append(id)
                continue
            }
            members.append(skill)
            reconciledIDs.append(skill.persistenceID)
        }

        return Resolution(members: members, missingIDs: missingIDs, reconciledIDs: reconciledIDs)
    }

    static func reconcileMemberIDs(_ ids: [String], skills: [Skill]) -> [String] {
        resolveMemberIDs(ids, skills: skills).reconciledIDs
    }

    static func memberID(_ id: String, matches skill: Skill, skills: [Skill]) -> Bool {
        guard let resolved = resolveMemberID(id, skills: skills) else { return false }
        return resolved.persistenceID == skill.persistenceID || resolved.id == skill.id
    }

    static func protectedMountedMemberIDs(
        excluding collection: CollectionRecord,
        agentID: String,
        collections: [CollectionRecord],
        skills: [Skill]
    ) -> Set<String> {
        // ponytail: O(n²) collection/member scan; add a per-agent index only if real collection scale makes this measurable.
        Set(collections
            .filter { $0.id != collection.id && $0.mountedAgentIDs.contains(agentID) }
            .flatMap { resolveMemberIDs($0.memberSkillIDs, skills: skills).members }
            .map(\.persistenceID))
    }

    private static func resolveMemberID(_ id: String, skills: [Skill]) -> Skill? {
        if let stable = skills.first(where: { $0.persistenceID == id }) {
            return stable
        }
        if let legacy = skills.first(where: { $0.id == id }) {
            return legacy
        }

        guard let migratedUniversalID = migratedUniversalID(from: id) else {
            return nil
        }
        return skills.first { $0.id == migratedUniversalID }
    }

    private static func migratedUniversalID(from id: String) -> String? {
        guard id.hasPrefix("universal:/") else { return nil }
        let path = String(id.dropFirst("universal:".count))
        guard path.contains("/") else { return nil }
        guard let name = path.split(separator: "/").last.map(String.init), !name.isEmpty else {
            return nil
        }
        return "universal:\(SymlinkInstaller.sanitize(name))"
    }
}

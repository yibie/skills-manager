import Foundation
import CryptoKit

/// One physical copy of a conflicting skill: a distinct directory on disk that
/// serves the same skill name with different content.
struct SkillConflictInstance: Identifiable, Hashable, Sendable {
    /// Resolved skill directory path.
    let path: String
    /// Agents that load the skill from this copy.
    let agents: [String]
    /// Short SHA-256 of the SKILL.md content, for telling copies apart at a glance.
    let contentHash: String

    var id: String { path }
}

/// A skill name deployed to multiple agents whose on-disk copies have diverged.
struct SkillConflict: Identifiable, Hashable, Sendable {
    let name: String
    let instances: [SkillConflictInstance]

    var id: String { name }
}

/// Detects same-name skills whose copies drifted apart across agent directories.
///
/// Only user-managed sources participate (local / symlinked / OpenClaw): plugin
/// cache copies are read-only third-party content, and project-local skills are
/// intentional project overrides (shadowing is the Inspector's job to show).
/// Copies that resolve to the same directory (e.g. symlinks into the canonical
/// root) are one instance by construction, and identical content is not a conflict.
enum SkillConflictDetection {
    static func detect(in scanned: [Skill]) -> [SkillConflict] {
        var namesByPath: [String: (name: String, agents: Set<String>, content: String)] = [:]
        for skill in scanned where isUserManaged(skill.source) {
            let path = skill.directoryPath.resolvingSymlinksInPath().standardizedFileURL.path
            var entry = namesByPath[path] ?? (skill.name, [], skill.markdownContent)
            entry.agents.formUnion(skill.compatibleAgents)
            namesByPath[path] = entry
        }

        var pathsByName: [String: [String]] = [:]
        for (path, entry) in namesByPath {
            pathsByName[entry.name, default: []].append(path)
        }

        var conflicts: [SkillConflict] = []
        for (name, paths) in pathsByName where paths.count > 1 {
            let hashes = Set(paths.map { hash(namesByPath[$0]!.content) })
            guard hashes.count > 1 else { continue }
            let instances = paths
                .sorted()
                .map { path in
                    SkillConflictInstance(
                        path: path,
                        agents: namesByPath[path]!.agents.sorted(),
                        contentHash: hash(namesByPath[path]!.content)
                    )
                }
            conflicts.append(SkillConflict(name: name, instances: instances))
        }
        return conflicts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func isUserManaged(_ source: SkillSource) -> Bool {
        switch source {
        case .local, .symlinked, .openClaw:
            return true
        case .plugin, .projectLocal:
            return false
        }
    }

    private static func hash(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

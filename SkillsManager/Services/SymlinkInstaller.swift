import Foundation

/// Writes a skill to the canonical ~/.config/agents/skills/<name>/ directory
/// and creates symlinks in each target agent's globalSkillsDir.
enum SymlinkInstaller {

    /// Install a skill (represented as SKILL.md content) to one or more agents.
    /// - Parameters:
    ///   - content: The SKILL.md content string to write.
    ///   - skillName: The directory name to use (kebab-case).
    ///   - agentIDs: IDs from AgentRegistry to install to. Pass [] to install only to canonical dir.
    static func install(content: String, skillName: String, agentIDs: [String]) throws {
        let fm = FileManager.default
        let safe = sanitize(skillName)
        let canonicalDir = AgentRegistry.canonicalGlobalSkillsDir.appendingPathComponent(safe)

        // Write to canonical location
        if !fm.fileExists(atPath: canonicalDir.path) {
            try fm.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        }
        let skillMDPath = canonicalDir.appendingPathComponent("SKILL.md")
        try content.write(to: skillMDPath, atomically: true, encoding: .utf8)

        // Create symlinks for each agent
        for agentID in agentIDs {
            guard let agentDef = AgentRegistry.agent(id: agentID) else { continue }
            try createSymlink(from: canonicalDir, to: agentDef.globalSkillsDir.appendingPathComponent(safe), fm: fm)
        }
    }

    /// Remove a skill: delete canonical dir (which also breaks all symlinks pointing to it).
    /// Then remove any dangling symlinks in agent dirs.
    static func uninstall(skillName: String) throws {
        let fm = FileManager.default
        let safe = sanitize(skillName)
        let canonicalDir = AgentRegistry.canonicalGlobalSkillsDir.appendingPathComponent(safe)

        // Remove canonical dir (all symlinks to it become dangling, then we clean them)
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }

        // Clean up dangling symlinks in every agent dir
        for agent in AgentRegistry.all {
            let agentSkillDir = agent.globalSkillsDir.appendingPathComponent(safe)
            if let attrs = try? fm.attributesOfItem(atPath: agentSkillDir.path),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                try? fm.removeItem(at: agentSkillDir)
            }
        }
    }

    // MARK: - Helpers

    private static func createSymlink(from target: URL, to linkPath: URL, fm: FileManager) throws {
        let linkDir = linkPath.deletingLastPathComponent()
        if !fm.fileExists(atPath: linkDir.path) {
            try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        }

        // Remove existing entry at linkPath (could be old copy or stale symlink)
        if fm.fileExists(atPath: linkPath.path) || (try? fm.attributesOfItem(atPath: linkPath.path)) != nil {
            try fm.removeItem(at: linkPath)
        }

        // Use absolute path for symlink target (simpler and more reliable)
        let realTarget = target.resolvingSymlinksInPath()
        try fm.createSymbolicLink(atPath: linkPath.path, withDestinationPath: realTarget.path)
    }

    /// Sanitize to kebab-case, matching vercel/skills sanitizeName logic.
    static func sanitize(_ name: String) -> String {
        let s = name.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9._]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"^[.\-]+|[.\-]+$"#, with: "", options: .regularExpression)
        return s.isEmpty ? "unnamed-skill" : String(s.prefix(255))
    }
}

import Foundation

enum SymlinkInstallerError: LocalizedError {
    case destinationConflict(URL)

    var errorDescription: String? {
        switch self {
        case .destinationConflict(let url):
            "A file or directory already exists at \(url.path)."
        }
    }
}

/// Writes a skill to the canonical ~/.config/agents/skills/<name>/ directory
/// and creates symlinks in each target agent's globalSkillsDir.
enum SymlinkInstaller {
    static let managedMarkerName = ".skills-manager-managed"

    /// Install a skill (represented as SKILL.md content) to one or more agents.
    /// - Parameters:
    ///   - content: The SKILL.md content string to write.
    ///   - skillName: The directory name to use (kebab-case).
    ///   - agentIDs: IDs from AgentRegistry to install to. Pass [] to install only to canonical dir.
    static func install(
        content: String,
        skillName: String,
        agentIDs: [String],
        canonicalSkillsDirectory: URL = AgentRegistry.canonicalGlobalSkillsDir,
        importedPaths: [String: String] = AgentRegistry.storedImportedAgentFolders()
    ) throws {
        let fm = FileManager.default
        let safe = sanitize(skillName)
        let canonicalDir = canonicalSkillsDirectory.appendingPathComponent(safe)
        let linkPaths = agentIDs.compactMap { agentID -> URL? in
            guard let agent = AgentRegistry.agent(id: agentID) else { return nil }
            return AgentRegistry.resolvedSkillsDir(for: agent, importedPaths: importedPaths)
                .appendingPathComponent(safe)
        }
        let canonicalExists = (try? fm.attributesOfItem(atPath: canonicalDir.path)) != nil
        let knownLinkPaths = AgentRegistry.all.map {
            AgentRegistry.resolvedSkillsDir(for: $0, importedPaths: importedPaths)
                .appendingPathComponent(safe)
        }
        if canonicalExists
            && !isManagedCanonicalDirectory(canonicalDir, fm: fm)
            && !canAdoptLegacyCanonicalDirectory(
                canonicalDir,
                content: content,
                linkPaths: knownLinkPaths,
                fm: fm
            ) {
            throw SymlinkInstallerError.destinationConflict(canonicalDir)
        }

        for linkPath in linkPaths {
            try validateLink(from: canonicalDir, to: linkPath, fm: fm)
        }

        // Write to canonical location
        if !canonicalExists {
            try fm.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        }
        do {
            try content.write(
                to: canonicalDir.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
            try "1\n".write(
                to: canonicalDir.appendingPathComponent(managedMarkerName),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            if !canonicalExists {
                try? fm.removeItem(at: canonicalDir)
            }
            throw error
        }

        // Create symlinks for each agent
        for linkPath in linkPaths {
            try createSymlink(from: canonicalDir, to: linkPath, fm: fm)
        }
    }

    /// Remove a skill: delete canonical dir (which also breaks all symlinks pointing to it).
    /// Then remove any dangling symlinks in agent dirs.
    static func uninstall(
        skillName: String,
        canonicalSkillsDirectory: URL = AgentRegistry.canonicalGlobalSkillsDir,
        importedPaths: [String: String] = AgentRegistry.storedImportedAgentFolders()
    ) throws {
        let fm = FileManager.default
        let safe = sanitize(skillName)
        let canonicalDir = canonicalSkillsDirectory.appendingPathComponent(safe)
        guard (try? fm.attributesOfItem(atPath: canonicalDir.path)) != nil else { return }
        guard isManagedCanonicalDirectory(canonicalDir, fm: fm) else {
            throw SymlinkInstallerError.destinationConflict(canonicalDir)
        }
        let links = Set(AgentRegistry.all.compactMap { agent -> URL? in
            let link = AgentRegistry.resolvedSkillsDir(for: agent, importedPaths: importedPaths)
                .appendingPathComponent(safe)
            guard !sameDirectPath(link, canonicalDir),
                  isLink(link, pointingTo: canonicalDir, fm: fm)
            else { return nil }
            return link
        })

        // Remove canonical dir (all symlinks to it become dangling, then we clean them)
        if fm.fileExists(atPath: canonicalDir.path) {
            try fm.removeItem(at: canonicalDir)
        }

        for link in links {
            try fm.removeItem(at: link)
        }
    }

    // MARK: - Helpers

    private static func createSymlink(from target: URL, to linkPath: URL, fm: FileManager) throws {
        try validateLink(from: target, to: linkPath, fm: fm)
        if sameDirectPath(linkPath, target)
            || (try? fm.attributesOfItem(atPath: linkPath.path)) != nil {
            return
        }

        let linkDir = linkPath.deletingLastPathComponent()
        if !fm.fileExists(atPath: linkDir.path) {
            try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        }

        // Use absolute path for symlink target (simpler and more reliable)
        let realTarget = target.resolvingSymlinksInPath()
        try fm.createSymbolicLink(atPath: linkPath.path, withDestinationPath: realTarget.path)
    }

    private static func validateLink(from target: URL, to linkPath: URL, fm: FileManager) throws {
        guard !sameDirectPath(linkPath, target) else { return }
        guard (try? fm.attributesOfItem(atPath: linkPath.path)) != nil else { return }
        guard isLink(linkPath, pointingTo: target, fm: fm) else {
            throw SymlinkInstallerError.destinationConflict(linkPath)
        }
    }

    private static func isLink(_ link: URL, pointingTo target: URL, fm: FileManager) -> Bool {
        guard let rawDestination = try? fm.destinationOfSymbolicLink(atPath: link.path) else { return false }

        let destination: URL
        if rawDestination.hasPrefix("/") {
            destination = URL(fileURLWithPath: rawDestination)
        } else {
            destination = link.deletingLastPathComponent().appendingPathComponent(rawDestination)
        }
        return sameResolvedPath(destination, target)
    }

    private static func sameDirectPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private static func sameResolvedPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL.path
            == rhs.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func isManagedCanonicalDirectory(_ directory: URL, fm: FileManager = .default) -> Bool {
        fm.fileExists(atPath: directory.appendingPathComponent(managedMarkerName).path)
    }

    private static func canAdoptLegacyCanonicalDirectory(
        _ directory: URL,
        content: String,
        linkPaths: [URL],
        fm: FileManager
    ) -> Bool {
        let skillFile = directory.appendingPathComponent("SKILL.md")
        guard let existingContent = try? String(contentsOf: skillFile, encoding: .utf8),
              existingContent == content
        else { return false }

        return linkPaths.contains { isLink($0, pointingTo: directory, fm: fm) }
    }

    /// Sanitize to kebab-case, matching vercel/skills sanitizeName logic.
    static func sanitize(_ name: String) -> String {
        let s = name.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9._]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"^[.\-]+|[.\-]+$"#, with: "", options: .regularExpression)
        return s.isEmpty ? "unnamed-skill" : String(s.prefix(255))
    }
}

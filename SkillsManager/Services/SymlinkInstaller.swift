import Foundation

enum SymlinkInstallerError: LocalizedError {
    case destinationConflict(URL)
    case unsafePackageLink(URL)

    var errorDescription: String? {
        switch self {
        case .destinationConflict(let url):
            "A file or directory already exists at \(url.path)."
        case .unsafePackageLink(let url):
            "The skill package contains a link outside its own directory: \(url.path)."
        }
    }
}

/// Writes a skill to the canonical ~/.config/agents/skills/<name>/ directory
/// and creates symlinks in each target agent's globalSkillsDir.
enum SymlinkInstaller {
    static let managedMarkerName = ".skills-manager-managed"
    static let managedManifestName = ".skills-manager.json"

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

    /// Installs a complete skill directory so bundled scripts and assets remain available.
    static func install(
        sourceDirectory: URL,
        skillName: String,
        agentIDs: [String],
        canonicalSkillsDirectory: URL = AgentRegistry.canonicalGlobalSkillsDir,
        importedPaths: [String: String] = AgentRegistry.storedImportedAgentFolders()
    ) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceDirectory.appendingPathComponent("SKILL.md").path) else {
            throw SkillLifecycleError.skillNotFound(skillName)
        }
        try validatePackageLinks(in: sourceDirectory, fm: fm)

        let safe = sanitize(skillName)
        let canonicalDir = canonicalSkillsDirectory.appendingPathComponent(safe)
        let linkPaths = agentIDs.compactMap { agentID -> URL? in
            guard let agent = AgentRegistry.agent(id: agentID) else { return nil }
            return AgentRegistry.resolvedSkillsDir(for: agent, importedPaths: importedPaths)
                .appendingPathComponent(safe)
        }
        let canonicalExists = (try? fm.attributesOfItem(atPath: canonicalDir.path)) != nil
        if canonicalExists && !isManagedCanonicalDirectory(canonicalDir, fm: fm) {
            throw SymlinkInstallerError.destinationConflict(canonicalDir)
        }
        for linkPath in linkPaths {
            try validateLink(from: canonicalDir, to: linkPath, fm: fm)
        }

        if !sameResolvedPath(sourceDirectory, canonicalDir) {
            try fm.createDirectory(
                at: canonicalSkillsDirectory,
                withIntermediateDirectories: true
            )
            let staging = canonicalSkillsDirectory
                .appendingPathComponent(".\(safe)-install-\(UUID().uuidString)")
            let backup = canonicalSkillsDirectory
                .appendingPathComponent(".\(safe)-backup-\(UUID().uuidString)")
            defer {
                try? fm.removeItem(at: staging)
            }

            try fm.copyItem(at: sourceDirectory, to: staging)
            try? fm.removeItem(at: staging.appendingPathComponent(managedManifestName))
            try "1\n".write(
                to: staging.appendingPathComponent(managedMarkerName),
                atomically: true,
                encoding: .utf8
            )
            if canonicalExists {
                try fm.moveItem(at: canonicalDir, to: backup)
            }
            do {
                try fm.moveItem(at: staging, to: canonicalDir)
                if canonicalExists {
                    preserveReplacedCopy(
                        backup,
                        skillName: safe,
                        canonicalSkillsDirectory: canonicalSkillsDirectory,
                        fm: fm
                    )
                }
            } catch {
                if canonicalExists {
                    try? fm.moveItem(at: backup, to: canonicalDir)
                }
                throw error
            }
        }

        for linkPath in linkPaths {
            try createSymlink(from: canonicalDir, to: linkPath, fm: fm)
        }
    }

    /// 被替换的 canonical 副本保留在这里(canonical 目录的隐藏兄弟目录),
    /// 更新/重装永远不静默销毁旧内容。
    static func historyDirectory(canonicalSkillsDirectory: URL) -> URL {
        canonicalSkillsDirectory.deletingLastPathComponent()
            .appendingPathComponent(".skills-manager-history")
    }

    private static func preserveReplacedCopy(
        _ backup: URL,
        skillName: String,
        canonicalSkillsDirectory: URL,
        fm: FileManager
    ) {
        let historyDir = historyDirectory(canonicalSkillsDirectory: canonicalSkillsDirectory)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dest = historyDir.appendingPathComponent("\(skillName)-\(stamp)-\(UUID().uuidString.prefix(8))")
        do {
            try fm.createDirectory(at: historyDir, withIntermediateDirectories: true)
            try fm.moveItem(at: backup, to: dest)
        } catch {
            // 移动失败时备份仍以隐藏名留在 canonical 目录,内容不丢失
        }
    }

    /// Delete a skill from the Library and remove only links managed by this app.
    /// Collection unmounting is a separate, non-destructive operation.
    static func removeFromLibrary(
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

    private static func validatePackageLinks(in root: URL, fm: FileManager) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else { return }

        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true,
                  let destination = try? fm.destinationOfSymbolicLink(atPath: item.path)
            else { continue }
            let target = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : item.deletingLastPathComponent().appendingPathComponent(destination)
            let targetPath = target.resolvingSymlinksInPath().standardizedFileURL.path
            guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
                throw SymlinkInstallerError.unsafePackageLink(item)
            }
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

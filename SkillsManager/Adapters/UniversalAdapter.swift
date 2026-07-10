import Foundation

struct UniversalAdapter: AgentAdapter {

    let agentName = "Universal"
    let agentIcon = "square.grid.2x2"
    private let canonicalSkillsDirectory: URL
    private let sharedSkillsDirectories: [URL]
    private let installedAgentsOverride: [AgentDefinition]?
    private let importedPathsOverride: [String: String]?

    init(
        canonicalSkillsDirectory: URL = AgentRegistry.canonicalGlobalSkillsDir,
        sharedSkillsDirectories: [URL]? = nil,
        installedAgents: [AgentDefinition]? = nil,
        importedPaths: [String: String]? = nil
    ) {
        self.canonicalSkillsDirectory = canonicalSkillsDirectory
        self.sharedSkillsDirectories = sharedSkillsDirectories ?? [
            canonicalSkillsDirectory,
            AgentRegistry.home.appendingPathComponent(".agents/skills"),
        ]
        installedAgentsOverride = installedAgents
        importedPathsOverride = importedPaths
    }

    var skillsDirectories: [URL] {
        sharedSkillsDirectories
    }

    func scanSkills() async throws -> [Skill] {
        return await Task.detached(priority: .userInitiated) {
            self.scanAllAgentSkills()
        }.value
    }

    func installSkill(_ skill: Skill) throws {
        // Installation is handled by SymlinkInstaller
    }

    func uninstallSkill(_ skill: Skill) throws {
        // Handled by SkillStore.uninstallSkill
    }

    // MARK: - Private

    private func scanAllAgentSkills() -> [Skill] {
        let fm = FileManager.default
        let installedAgents = installedAgentsOverride ?? AgentRegistry.installedAgents()
        let importedPaths = importedPathsOverride ?? AgentRegistry.storedImportedAgentFolders()

        var entriesByPath: [String: (URL, [String])] = [:]

        for directory in sharedSkillsDirectories {
            scanDir(directory, agentID: nil, entriesByPath: &entriesByPath, fm: fm)
        }

        // Scan each installed agent's dir
        for agent in installedAgents where agent.id != "openclaw" {
            scanDir(AgentRegistry.resolvedSkillsDir(for: agent, importedPaths: importedPaths), agentID: agent.id,
                    entriesByPath: &entriesByPath, fm: fm)
        }

        let skills = entriesByPath.values.compactMap { dirURL, agentIDs -> Skill? in
            let skillMD = dirURL.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMD.path),
                  let content = try? String(contentsOf: skillMD, encoding: .utf8)
            else { return nil }
            return buildSkill(dirURL: dirURL, content: content, agentIDs: agentIDs)
        }

        return skills.sorted { $0.displayName < $1.displayName }
    }

    private func scanDir(
        _ dir: URL,
        agentID: String?,
        entriesByPath: inout [String: (URL, [String])],
        fm: FileManager
    ) {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: entry.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let resolvedPath = entry.resolvingSymlinksInPath().standardizedFileURL.path
            if var existing = entriesByPath[resolvedPath] {
                if let agentID, !existing.1.contains(agentID) {
                    existing.1.append(agentID)
                }
                entriesByPath[resolvedPath] = existing
            } else {
                entriesByPath[resolvedPath] = (entry, agentID.map { [$0] } ?? [])
            }
        }
    }

    private func buildSkill(dirURL: URL, content: String, agentIDs: [String]) -> Skill {
        let parsed = SkillParser.parse(content: content)
        let fm = parsed.frontmatter
        let dirName = dirURL.lastPathComponent
        let displayName = fm["name"] ?? dirName
        let description = fm["description"] ?? ""
        let rawTags = fm["tags"] ?? fm["keywords"] ?? ""
        let tags = rawTags
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let agentDisplayNames = agentIDs.map { id in
            AgentRegistry.agent(id: id)?.displayName ?? id
        }
        let canonical = canonicalSkillsDirectory.appendingPathComponent(dirName)
        let resolvedDirectory = dirURL.resolvingSymlinksInPath().standardizedFileURL
        let canonicalPath = resolvedDirectory.path
            == canonical.resolvingSymlinksInPath().standardizedFileURL.path
            && SymlinkInstaller.isManagedCanonicalDirectory(canonical)
            ? canonical
            : nil
        let id = canonicalPath == nil ? "universal:\(resolvedDirectory.path)" : "universal:\(dirName)"

        return Skill(
            id: id,
            name: dirName,
            displayName: displayName,
            baseDescription: description,
            baseDescriptionLocale: DescriptionLocale.descriptionLocale(frontmatter: fm, description: description),
            localizedDescription: nil,
            source: .local,
            version: fm["version"],
            filePath: dirURL.appendingPathComponent("SKILL.md"),
            directoryPath: dirURL,
            canonicalPath: canonicalPath,
            compatibleAgents: agentDisplayNames.isEmpty ? ["Universal"] : agentDisplayNames,
            tags: tags,
            markdownContent: content,
            frontmatter: fm
        )
    }
}

import Foundation

struct UniversalAdapter: AgentAdapter {

    let agentName = "Universal"
    let agentIcon = "square.grid.2x2"

    var skillsDirectories: [URL] {
        [AgentRegistry.canonicalGlobalSkillsDir]
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
        let installedAgents = AgentRegistry.installedAgents()

        var inodeMap: [UInt64: (URL, [String])] = [:]
        var nameMap: [String: (URL, [String])] = [:]

        // Scan canonical dir first
        scanDir(AgentRegistry.canonicalGlobalSkillsDir, agentID: nil,
                inodeMap: &inodeMap, nameMap: &nameMap, fm: fm)

        // Scan each installed agent's dir
        for agent in installedAgents {
            scanDir(agent.globalSkillsDir, agentID: agent.id,
                    inodeMap: &inodeMap, nameMap: &nameMap, fm: fm)
        }

        var skills: [Skill] = []
        var seenNames = Set<String>()

        for (_, (dirURL, agentIDs)) in inodeMap {
            let skillMD = dirURL.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMD.path),
                  let content = try? String(contentsOf: skillMD, encoding: .utf8) else { continue }
            let skill = buildSkill(dirURL: dirURL, content: content, agentIDs: agentIDs)
            if !seenNames.contains(skill.name) {
                seenNames.insert(skill.name)
                skills.append(skill)
            }
        }

        for (name, (dirURL, agentIDs)) in nameMap {
            guard !seenNames.contains(name) else { continue }
            let skillMD = dirURL.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillMD.path),
                  let content = try? String(contentsOf: skillMD, encoding: .utf8) else { continue }
            let skill = buildSkill(dirURL: dirURL, content: content, agentIDs: agentIDs)
            seenNames.insert(skill.name)
            skills.append(skill)
        }

        return skills.sorted { $0.displayName < $1.displayName }
    }

    private func scanDir(
        _ dir: URL,
        agentID: String?,
        inodeMap: inout [UInt64: (URL, [String])],
        nameMap: inout [String: (URL, [String])],
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

            let name = entry.lastPathComponent
            let resolvedPath = entry.resolvingSymlinksInPath().path
            let attrs = try? fm.attributesOfItem(atPath: resolvedPath)
            let inode = (attrs?[.systemFileNumber] as? UInt64) ?? 0

            if inode > 0 {
                if var existing = inodeMap[inode] {
                    if let id = agentID, !existing.1.contains(id) {
                        existing.1.append(id)
                    }
                    inodeMap[inode] = existing
                } else {
                    inodeMap[inode] = (entry, agentID.map { [$0] } ?? [])
                }
            } else {
                if var existing = nameMap[name] {
                    if let id = agentID, !existing.1.contains(id) {
                        existing.1.append(id)
                    }
                    nameMap[name] = existing
                } else {
                    nameMap[name] = (entry, agentID.map { [$0] } ?? [])
                }
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

        return Skill(
            id: "universal:\(dirName)",
            name: dirName,
            displayName: displayName,
            description: description,
            source: .local,
            version: fm["version"],
            filePath: dirURL.appendingPathComponent("SKILL.md"),
            directoryPath: dirURL,
            canonicalPath: AgentRegistry.canonicalGlobalSkillsDir.appendingPathComponent(dirName),
            compatibleAgents: agentDisplayNames.isEmpty ? ["Universal"] : agentDisplayNames,
            tags: tags,
            markdownContent: content,
            frontmatter: fm
        )
    }
}

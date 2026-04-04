import Foundation

struct ClaudeCodeAdapter: AgentAdapter {

    // MARK: - AgentAdapter

    let agentName = "Claude Code"
    let agentIcon = "terminal"

    var skillsDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/skills"),
            home.appendingPathComponent(".claude/plugins/cache"),
        ]
    }

    func scanSkills() async throws -> [Skill] {
        var skills: [Skill] = []

        let home = FileManager.default.homeDirectoryForCurrentUser
        let localSkillsDir = home.appendingPathComponent(".claude/skills")
        let pluginCacheDir = home.appendingPathComponent(".claude/plugins/cache")

        // Scan local skills
        let localSkills = scanLocalSkills(in: localSkillsDir)
        skills.append(contentsOf: localSkills)

        // Scan plugin skills
        let pluginSkills = scanPluginSkills(in: pluginCacheDir)
        skills.append(contentsOf: pluginSkills)

        return skills
    }

    func installSkill(_ skill: Skill) throws {
        // Installation not implemented for ClaudeCodeAdapter
    }

    func uninstallSkill(_ skill: Skill) throws {
        // Uninstallation not implemented for ClaudeCodeAdapter
    }

    // MARK: - Private

    private func scanLocalSkills(in directory: URL) -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        var skills: [Skill] = []

        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for entry in entries {
            // Resolve symlink if needed
            let resolved = resolveSymlink(entry)

            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory)

            if isDirectory.boolValue {
                // Skill directory: look for SKILL.md inside
                let skillFile = resolved.appendingPathComponent("SKILL.md")
                if fm.fileExists(atPath: skillFile.path) {
                    if let skill = buildSkill(
                        skillFile: skillFile,
                        skillDir: resolved,
                        id: "local:\(entry.lastPathComponent)",
                        name: entry.lastPathComponent,
                        source: .local
                    ) {
                        skills.append(skill)
                    }
                }
            } else if entry.lastPathComponent == "SKILL.md" || entry.pathExtension == "md" {
                // Single SKILL.md file directly in skills dir
                let dirName = entry.deletingPathExtension().lastPathComponent
                if let skill = buildSkill(
                    skillFile: resolved,
                    skillDir: directory,
                    id: "local:\(dirName)",
                    name: dirName,
                    source: .local
                ) {
                    skills.append(skill)
                }
            }
        }

        return skills
    }

    private func scanPluginSkills(in cacheDir: URL) -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheDir.path) else { return [] }

        var skills: [Skill] = []

        // Structure: {marketplace}/{plugin}/{version}/skills/
        guard let marketplaces = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for marketplaceURL in marketplaces {
            guard isDirectory(marketplaceURL) else { continue }
            let marketplace = marketplaceURL.lastPathComponent

            guard let plugins = try? fm.contentsOfDirectory(
                at: marketplaceURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for pluginURL in plugins {
                guard isDirectory(pluginURL) else { continue }
                let pluginName = pluginURL.lastPathComponent

                // Use only the latest cached version to avoid duplicate skill IDs
                guard let versionURL = latestVersion(in: pluginURL) else { continue }

                let skillsDir = versionURL.appendingPathComponent("skills")
                guard fm.fileExists(atPath: skillsDir.path) else { continue }

                guard let skillEntries = try? fm.contentsOfDirectory(
                    at: skillsDir,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for entry in skillEntries {
                    let resolved = resolveSymlink(entry)

                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: resolved.path, isDirectory: &isDir)

                    let skillName = entry.lastPathComponent

                    if isDir.boolValue {
                        let skillFile = resolved.appendingPathComponent("SKILL.md")
                        guard fm.fileExists(atPath: skillFile.path) else { continue }

                        let id = "plugin:\(marketplace):\(pluginName):\(skillName)"
                        if let skill = buildSkill(
                            skillFile: skillFile,
                            skillDir: resolved,
                            id: id,
                            name: skillName,
                            source: .plugin(marketplace: marketplace, pluginName: pluginName)
                        ) {
                            skills.append(skill)
                        }
                    } else if entry.pathExtension == "md" {
                        let nameWithoutExt = entry.deletingPathExtension().lastPathComponent
                        let id = "plugin:\(marketplace):\(pluginName):\(nameWithoutExt)"
                        if let skill = buildSkill(
                            skillFile: resolved,
                            skillDir: skillsDir,
                            id: id,
                            name: nameWithoutExt,
                            source: .plugin(marketplace: marketplace, pluginName: pluginName)
                        ) {
                            skills.append(skill)
                        }
                    }
                }
            }
        }

        return skills
    }

    // MARK: - Helpers

    private func buildSkill(
        skillFile: URL,
        skillDir: URL,
        id: String,
        name: String,
        source: SkillSource
    ) -> Skill? {
        guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }

        let parsed = SkillParser.parse(content: content)
        let fm = parsed.frontmatter

        let displayName = fm["name"] ?? name
        let description = fm["description"] ?? ""

        // Tags: prefer "tags", fall back to "keywords"
        let rawTags = fm["tags"] ?? fm["keywords"] ?? ""
        let tags = rawTags
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return Skill(
            id: id,
            name: name,
            displayName: displayName,
            description: description,
            source: source,
            version: fm["version"],
            filePath: skillFile,
            directoryPath: skillDir,
            compatibleAgents: ["Claude Code"],
            tags: tags,
            markdownContent: content,
            frontmatter: fm
        )
    }

    private func resolveSymlink(_ url: URL) -> URL {
        let fm = FileManager.default
        if let destination = try? fm.destinationOfSymbolicLink(atPath: url.path) {
            // destination may be relative or absolute
            if destination.hasPrefix("/") {
                return URL(fileURLWithPath: destination)
            } else {
                return url.deletingLastPathComponent().appendingPathComponent(destination)
            }
        }
        return url
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    /// Returns the URL of the highest semantic version subdirectory inside a plugin directory.
    /// Uses numeric string comparison so "5.0.10" > "5.0.9".
    private func latestVersion(in pluginURL: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: pluginURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return entries
            .filter { isDirectory($0) }
            .max { a, b in
                a.lastPathComponent.compare(b.lastPathComponent, options: .numeric) == .orderedAscending
            }
    }
}

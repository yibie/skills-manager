import Foundation

struct ProjectScanner {

    /// Scans a project directory for skill files.
    /// Returns .mdc files from .cursor/rules/ and SKILL.md files up to 3 levels deep.
    func scan(projectURL: URL) -> [Skill] {
        var skills: [Skill] = []

        // .cursor/rules/*.mdc
        let cursorRules = projectURL.appendingPathComponent(".cursor/rules")
        let cursorSkills = CursorAdapter().scanMDC(
            in: cursorRules,
            source: .projectLocal(projectURL: projectURL)
        )
        skills.append(contentsOf: cursorSkills)

        // SKILL.md anywhere in the project (depth ≤ 3)
        let skillMDFiles = findSKILLMD(in: projectURL, depth: 0, maxDepth: 3)
        let claudeSkills = skillMDFiles.compactMap {
            buildClaudeSkill(skillFile: $0, projectURL: projectURL)
        }
        skills.append(contentsOf: claudeSkills)

        return skills
    }

    // MARK: - Private

    private func findSKILLMD(in directory: URL, depth: Int, maxDepth: Int) -> [URL] {
        guard depth <= maxDepth else { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for entry in entries {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: entry.path, isDirectory: &isDir)
            if isDir.boolValue {
                results.append(contentsOf: findSKILLMD(in: entry, depth: depth + 1, maxDepth: maxDepth))
            } else if entry.lastPathComponent == "SKILL.md" {
                results.append(entry)
            }
        }
        return results
    }

    private func buildClaudeSkill(skillFile: URL, projectURL: URL) -> Skill? {
        guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }
        let parsed = SkillParser.parse(content: content)
        let fm = parsed.frontmatter
        let dirName = skillFile.deletingLastPathComponent().lastPathComponent
        let displayName = fm["name"] ?? dirName
        let description = fm["description"] ?? ""
        let rawTags = fm["tags"] ?? fm["keywords"] ?? ""
        let tags = rawTags
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let agents = fm["compatible_agents"]
            .map { $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            ?? ["Claude Code"]

        return Skill(
            id: "project:\(projectURL.lastPathComponent):\(dirName)",
            name: dirName,
            displayName: displayName,
            description: description,
            source: .projectLocal(projectURL: projectURL),
            version: fm["version"],
            filePath: skillFile,
            directoryPath: skillFile.deletingLastPathComponent(),
            compatibleAgents: agents,
            tags: tags,
            markdownContent: content,
            frontmatter: fm
        )
    }
}

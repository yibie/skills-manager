import Foundation

struct CursorAdapter: AgentAdapter {

    let agentName = "Cursor"
    let agentIcon = "cursorarrow"

    var skillsDirectories: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cursor/rules")]
    }

    func scanSkills() async throws -> [Skill] {
        scanMDC(in: skillsDirectories[0], source: .local)
    }

    func installSkill(_ skill: Skill) throws {
        let rulesDir = skillsDirectories[0]
        let fm = FileManager.default
        if !fm.fileExists(atPath: rulesDir.path) {
            try fm.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        }
        let content = SkillFormatConverter.toMDC(skill: skill)
        let dest = rulesDir.appendingPathComponent("\(skill.name).mdc")
        try content.write(to: dest, atomically: true, encoding: .utf8)
    }

    func uninstallSkill(_ skill: Skill) throws {
        try FileManager.default.removeItem(at: skill.filePath)
    }

    // MARK: - Internal (also used by ProjectScanner)

    /// Scans a directory for *.mdc files, building Skill structs with the given source.
    func scanMDC(in directory: URL, source: SkillSource) -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { url -> Skill? in
            guard url.pathExtension == "mdc" else { return nil }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return buildSkill(fileURL: url, content: content, source: source)
        }
    }

    // MARK: - Private

    private func buildSkill(fileURL: URL, content: String, source: SkillSource) -> Skill? {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let parsed = SkillFormatConverter.parseMDC(content: content)
        let description = parsed.frontmatter["description"] ?? ""
        let rawGlobs = parsed.frontmatter["globs"] ?? "[]"
        let tags = SkillFormatConverter.parseGlobs(rawGlobs)

        let idPrefix: String
        if case .projectLocal(let projectURL) = source {
            idPrefix = "project:\(projectURL.lastPathComponent):\(filename)"
        } else {
            idPrefix = "cursor:\(filename)"
        }

        return Skill(
            id: idPrefix,
            name: filename,
            displayName: filename,
            description: description,
            source: source,
            version: nil,
            filePath: fileURL,
            directoryPath: fileURL.deletingLastPathComponent(),
            compatibleAgents: ["Cursor"],
            tags: tags,
            markdownContent: content,
            frontmatter: parsed.frontmatter
        )
    }
}

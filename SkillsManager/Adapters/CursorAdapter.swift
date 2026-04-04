import Foundation

struct CursorAdapter: AgentAdapter {

    let agentName = "Cursor"
    let agentIcon = "cursorarrow"
    private let rulesDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cursor/rules")

    var skillsDirectories: [URL] { [rulesDirectory] }

    func scanSkills() async throws -> [Skill] {
        // Keep source: .local — Cursor global rules are locally-installed files.
        // The "cursor:" id prefix distinguishes them from Claude Code local skills ("local:").
        scanMDC(in: rulesDirectory, source: .local)
    }

    func installSkill(_ skill: Skill) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: rulesDirectory.path) {
            try fm.createDirectory(at: rulesDirectory, withIntermediateDirectories: true)
        }
        let content = SkillFormatConverter.toMDC(skill: skill)
        let dest = rulesDirectory.appendingPathComponent("\(skill.name).mdc")
        try content.write(to: dest, atomically: true, encoding: .utf8)
    }

    func uninstallSkill(_ skill: Skill) throws {
        let resolvedPath = skill.filePath.standardized.path
        let rulesPath = rulesDirectory.standardized.path
        guard resolvedPath.hasPrefix(rulesPath + "/") else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: skill.filePath)
    }

    // MARK: - Shared API

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
            compatibleAgents: [agentName],
            tags: tags,
            markdownContent: content,
            frontmatter: parsed.frontmatter
        )
    }
}

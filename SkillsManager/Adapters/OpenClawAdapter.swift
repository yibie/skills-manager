import Foundation

struct OpenClawAdapter: AgentAdapter {

    struct Root: Sendable {
        let id: String
        let url: URL
    }

    let agentName = "OpenClaw"
    let agentIcon = "claw"
    private let roots: [Root]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        roots = [
            Root(id: "clawd", url: home.appendingPathComponent("clawd/skills")),
            Root(id: "npm-global", url: home.appendingPathComponent(".npm-global/lib/node_modules/openclaw/skills")),
            Root(id: "workspace-main", url: home.appendingPathComponent(".openclaw/workspace-main/skills")),
        ]
    }

    init(roots: [Root]) {
        self.roots = roots
    }

    var skillsDirectories: [URL] {
        roots.map(\.url)
    }

    func scanSkills() async throws -> [Skill] {
        await Task.detached(priority: .userInitiated) {
            var all: [Skill] = []
            for root in roots {
                all.append(contentsOf: scanSkills(in: root))
            }
            return dedupe(all)
        }.value
    }

    private func scanSkills(in root: Root) -> [Skill] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.url.path) else { return [] }

        var results: [Skill] = []
        if let enumerator = fm.enumerator(at: root.url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                guard url.lastPathComponent == "SKILL.md" else { continue }
                guard let skill = buildSkill(skillFile: url, root: root) else { continue }
                results.append(skill)
            }
        }
        return results
    }

    private func buildSkill(skillFile: URL, root: Root) -> Skill? {
        guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }

        let parsed = SkillParser.parse(content: content)
        let frontmatter = parsed.frontmatter
        let skillDir = skillFile.deletingLastPathComponent()
        let relative = relativePath(of: skillDir, under: root.url) ?? skillDir.lastPathComponent
        let skillName = sanitize(relative)
        let displayName = frontmatter["name"] ?? skillDir.lastPathComponent
        let description = frontmatter["description"] ?? ""
        let rawTags = frontmatter["tags"] ?? frontmatter["keywords"] ?? ""
        let tags = rawTags
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Skill(
            id: "openclaw:\(root.id):\(relative)",
            name: skillName,
            displayName: displayName,
            baseDescription: description,
            baseDescriptionLocale: DescriptionLocale.descriptionLocale(frontmatter: frontmatter, description: description),
            localizedDescription: nil,
            source: .openClaw(root: root.id),
            version: frontmatter["version"],
            filePath: skillFile,
            directoryPath: skillDir,
            compatibleAgents: ["OpenClaw"],
            tags: tags,
            markdownContent: content,
            frontmatter: frontmatter,
            installState: .installed
        )
    }

    private func relativePath(of url: URL, under root: URL) -> String? {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
        if path == rootPath { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private func sanitize(_ value: String) -> String {
        let normalized = value.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}._/-]+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: "/", with: "--")
            .replacingOccurrences(of: #"^[.\-_/]+|[.\-_/]+$"#, with: "", options: .regularExpression)
        return normalized.isEmpty ? "unnamed-skill" : normalized
    }

    private func dedupe(_ skills: [Skill]) -> [Skill] {
        var seen = Set<String>()
        var output: [Skill] = []
        for skill in skills.sorted(by: { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }) {
            let key = skill.filePath.standardizedFileURL.path
            if seen.insert(key).inserted {
                output.append(skill)
            }
        }
        return output
    }
}

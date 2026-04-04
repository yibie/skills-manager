import Foundation

enum SkillFormatConverter {

    // MARK: - SKILL.md → .mdc

    /// Converts any Skill to Cursor .mdc format string.
    static func toMDC(skill: Skill) -> String {
        let body = SkillParser.parse(content: skill.markdownContent).body
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let globs: String
        if skill.tags.isEmpty {
            globs = "[]"
        } else {
            globs = "[\(skill.tags.map { "\"\($0)\"" }.joined(separator: ", "))]"
        }
        return """
        ---
        description: \(skill.description)
        globs: \(globs)
        alwaysApply: true
        ---

        \(body)
        """
    }

    // MARK: - .mdc → SKILL.md

    /// Converts .mdc content + a skill name to SKILL.md format string.
    static func toSKILLMD(name: String, mdcContent: String) -> String {
        let parsed = parseMDC(content: mdcContent)
        let description = parsed.frontmatter["description"] ?? ""
        let tags = parseGlobs(parsed.frontmatter["globs"] ?? "[]")
        let tagsLine = tags.isEmpty ? "" : "\ntags: \(tags.joined(separator: ", "))"
        let body = parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        ---
        name: \(name)
        description: \(description)\(tagsLine)
        compatible_agents: [Cursor, Claude Code]
        ---

        \(body)
        """
    }

    // MARK: - Parse .mdc

    /// Parses .mdc content into frontmatter dict and body string.
    /// .mdc frontmatter is identical in structure to SKILL.md frontmatter.
    static func parseMDC(content: String) -> (frontmatter: [String: String], body: String) {
        // Reuse SkillParser — the frontmatter format is identical
        let result = SkillParser.parse(content: content)
        return (frontmatter: result.frontmatter, body: result.body)
    }

    // MARK: - Private

    private static func parseGlobs(_ raw: String) -> [String] {
        raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                  .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            .filter { !$0.isEmpty }
    }
}

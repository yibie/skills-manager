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
        // alwaysApply: true when unscoped (no globs), false when glob-scoped
        let alwaysApply = skill.tags.isEmpty ? "true" : "false"
        return """
        ---
        description: \(yamlString(skill.description))
        globs: \(globs)
        alwaysApply: \(alwaysApply)
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
        name: \(yamlString(name))
        description: \(yamlString(description))\(tagsLine)
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

    // MARK: - Helpers

    /// Parses a YAML/JSON-style globs array string like ["*.ts", "*.tsx"] into [String].
    static func parseGlobs(_ raw: String) -> [String] {
        raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .components(separatedBy: ",")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                  .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            .filter { !$0.isEmpty }
    }

    /// Wraps a string in YAML double-quote syntax, escaping embedded double quotes.
    private static func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

import Foundation

enum SkillParser {

    struct ParseResult: Sendable {
        let frontmatter: [String: String]
        let body: String
    }

    static func parse(fileAt url: URL) throws -> ParseResult {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content: content)
    }

    static func parse(content: String) -> ParseResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("---") else {
            return ParseResult(frontmatter: [:], body: content)
        }

        let lines = content.components(separatedBy: "\n")
        var frontmatterLines: [String] = []
        var bodyStartIndex = 0
        var foundEnd = false

        // Skip first "---"
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                bodyStartIndex = i + 1
                foundEnd = true
                break
            }
            frontmatterLines.append(lines[i])
        }

        guard foundEnd else {
            return ParseResult(frontmatter: [:], body: content)
        }

        // Simple YAML key-value parser (handles: key: value and key: "value")
        var fm: [String: String] = [:]
        for line in frontmatterLines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            // Strip quotes
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            fm[key] = value
        }

        let body = lines[bodyStartIndex...].joined(separator: "\n")
        return ParseResult(frontmatter: fm, body: body)
    }
}

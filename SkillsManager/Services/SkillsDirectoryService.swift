import Foundation

/// skills.sh directory loader used by Discover.
///
/// Loads the public skills directory homepage and individual detail pages used
/// by the macOS Discover experience.
actor SkillsDirectoryService {
    private let session: URLSession

    init(session: URLSession = NetworkSessionFactory.makeEphemeralSession()) {
        self.session = session
    }

    private struct DirectoryEntryPayload: Decodable {
        var source: String
        var skillId: String
        var name: String?
        var installs: Int?
    }

    func loadSkillsDirectory(category: DiscoverDirectoryCategory = .allTime) async throws -> (skills: [DiscoverSkill], total: Int) {
        let html = try await fetchHTML(at: category.url)
        return parseSkillsDirectoryHTML(html)
    }

    func loadSkillDetail(_ skill: DiscoverSkill) async throws -> DiscoverSkill {
        let html = try await fetchHTML(at: skill.detailURL)

        let installCommand = firstMatch(
            in: html,
            pattern: #"<code[^>]*>\s*(?:<span[^>]*>\$</span>\s*(?:<!-- -->)?\s*)?(npx skills add https://github\.com/[^<\s]+ --skill [^<\s]+)\s*</code>"#,
            captureGroup: 1
        )

        let summaryHTML = firstMatch(
            in: html,
            pattern: #"<div class="prose[^"]*">([\s\S]*?)</div></div></div><div class="bg-background"><div class="flex items-center[^>]*"><span>SKILL\.md</span>"#,
            captureGroup: 1
        )

        let readmeHTML = firstMatch(
            in: html,
            pattern: #"<span>SKILL\.md</span></div><div class="prose[^"]*">([\s\S]*?)</div></div></div>"#,
            captureGroup: 1
        )

        let summary = summaryHTML.map(stripTags) ?? firstParagraph(fromHTML: readmeHTML) ?? skill.summary
        let readmeExcerpt = readmeHTML.map(stripTags).flatMap { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(1200))
        } ?? skill.readmeExcerpt

        return DiscoverSkill(
            id: skill.id,
            source: skill.source,
            skillId: skill.skillId,
            name: skill.name,
            installs: skill.installs,
            repoURL: skill.repoURL,
            installCommand: installCommand ?? skill.installCommand,
            summary: summary,
            readmeExcerpt: readmeExcerpt
        )
    }

    private func fetchHTML(at url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("skills-manager-macos", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SkillsDirectoryError.fetchFailed(url.absoluteString)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseSkillsDirectoryHTML(_ html: String) -> (skills: [DiscoverSkill], total: Int) {
        if let payload = parseSkillsDirectoryPayload(html) {
            return payload
        }

        let escapedPattern = #"\{\\"source\\":\\"([^\\]+)\\",\\"skillId\\":\\"([^\\]+)\\",\\"name\\":\\"([^\\]+)\\",\\"installs\\":(\d+)\}"#
        let directPattern = "\\{\"source\":\"([^\"]+)\",\"skillId\":\"([^\"]+)\",\"name\":\"([^\"]+)\",\"installs\":(\\d+)\\}"
        let fallbackEntries = parseSkillsDirectoryMatches(html, pattern: escapedPattern)
            + parseSkillsDirectoryMatches(html, pattern: directPattern)
        let skills = buildDiscoverSkills(from: fallbackEntries)
        return (skills, extractSkillsDirectoryTotal(html) ?? skills.count)
    }

    private func parseSkillsDirectoryPayload(_ html: String) -> (skills: [DiscoverSkill], total: Int)? {
        guard let rawArray = extractBalancedJSONSection(
            in: html,
            marker: "\\\"initialSkills\\\":",
            opening: "[",
            closing: "]"
        ) else {
            return nil
        }

        let normalized = rawArray.replacingOccurrences(of: "\\\"", with: "\"")
        guard let data = normalized.data(using: .utf8),
              let entries = try? JSONDecoder().decode([DirectoryEntryPayload].self, from: data)
        else {
            return nil
        }

        let skills = buildDiscoverSkills(from: entries)
        return (skills, extractSkillsDirectoryTotal(html) ?? skills.count)
    }

    private func parseSkillsDirectoryMatches(_ html: String, pattern: String) -> [DirectoryEntryPayload] {
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex?.matches(in: html, range: range) ?? []

        return matches.compactMap { match in
            guard
                let sourceRange = Range(match.range(at: 1), in: html),
                let skillIdRange = Range(match.range(at: 2), in: html),
                let nameRange = Range(match.range(at: 3), in: html),
                let installsRange = Range(match.range(at: 4), in: html)
            else { return nil }

            return DirectoryEntryPayload(
                source: String(html[sourceRange]),
                skillId: String(html[skillIdRange]),
                name: String(html[nameRange]),
                installs: Int(html[installsRange])
            )
        }
    }

    private func buildDiscoverSkills(from entries: [DirectoryEntryPayload]) -> [DiscoverSkill] {
        var seen = Set<String>()
        var skills: [DiscoverSkill] = []

        for entry in entries {
            let source = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let skillId = entry.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !skillId.isEmpty else { continue }

            let id = "\(source):\(skillId)"
            guard seen.insert(id).inserted else { continue }

            skills.append(DiscoverSkill(
                id: id,
                source: source,
                skillId: skillId,
                name: entry.name?.isEmpty == false ? entry.name! : skillId,
                installs: entry.installs ?? 0,
                repoURL: URL(string: "https://github.com/\(source)")!,
                installCommand: "npx skills add https://github.com/\(source) --skill \(skillId)",
                summary: nil,
                readmeExcerpt: nil
            ))
        }

        return skills
    }

    private func extractSkillsDirectoryTotal(_ html: String) -> Int? {
        for pattern in ["\\\\\"totalSkills\\\\\":(\\d+)", "\"totalSkills\":(\\d+)"] {
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex?.firstMatch(in: html, range: range),
               let valueRange = Range(match.range(at: 1), in: html) {
                return Int(html[valueRange])
            }
        }
        return nil
    }

    private func extractBalancedJSONSection(
        in html: String,
        marker: String,
        opening: Character,
        closing: Character
    ) -> String? {
        guard let markerRange = html.range(of: marker) else { return nil }
        guard let start = html[markerRange.upperBound...].firstIndex(of: opening) else { return nil }

        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start

        while index < html.endIndex {
            let character = html[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == opening {
                    depth += 1
                } else if character == closing {
                    depth -= 1
                    if depth == 0 {
                        return String(html[start...index])
                    }
                }
            }

            index = html.index(after: index)
        }

        return nil
    }

    private func firstMatch(in text: String, pattern: String, captureGroup: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let outputRange = Range(match.range(at: captureGroup), in: text)
        else {
            return nil
        }
        return String(text[outputRange])
    }

    private func firstParagraph(fromHTML html: String?) -> String? {
        guard let html else { return nil }
        guard let paragraph = firstMatch(in: html, pattern: #"<p>([\s\S]*?)</p>"#, captureGroup: 1) else {
            return nil
        }
        let stripped = stripTags(paragraph)
        return stripped.isEmpty ? nil : stripped
    }

    private func stripTags(_ html: String) -> String {
        let withoutScripts = html.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
        let withoutStyles = withoutScripts.replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: "", options: .regularExpression)
        let withoutTags = withoutStyles.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let decoded = decodeHTMLEntities(in: withoutTags)
        return decoded.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(in text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

enum SkillsDirectoryError: LocalizedError {
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let resource):
            return "Failed to fetch skills directory resource: \(resource)"
        }
    }
}

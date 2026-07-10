import Foundation

/// skills.sh directory loader used by Discover.
///
/// Loads the public skills directory homepage and individual detail pages used
/// by the macOS Discover experience.
actor SkillsDirectoryService {
    private let session: URLSession
    private let searchResultLimit = 1000

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

    func searchSkills(query: String) async throws -> (skills: [DiscoverSkill], count: Int) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return ([], 0)
        }

        var components = URLComponents(url: URL(string: "https://skills.sh/api/search")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "limit", value: String(searchResultLimit))
        ]

        guard let url = components.url else {
            throw SkillsDirectoryError.fetchFailed("https://skills.sh/api/search")
        }

        let json = try await fetchJSON(at: url)
        guard let payload = parseSkillsSearchPayload(json) else {
            throw SkillsDirectoryError.fetchFailed(url.absoluteString)
        }
        return payload
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
            baseDescription: summary,
            baseDescriptionLocale: DescriptionLocale.descriptionLocale(description: summary ?? ""),
            localizedDescription: nil,
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

    private func fetchJSON(at url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("skills-manager-macos", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SkillsDirectoryError.fetchFailed(url.absoluteString)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func parseSkillsDirectoryHTML(_ html: String) -> (skills: [DiscoverSkill], total: Int) {
        if let payload = parseSkillsDirectoryPayload(html) {
            return payload
        }

        let normalized = html.replacingOccurrences(of: "\\\"", with: "\"")
        let fallbackEntries = parseSkillsDirectoryObjects(normalized)
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

    private func parseSkillsSearchPayload(_ json: String) -> (skills: [DiscoverSkill], count: Int)? {
        struct SearchPayload: Decodable {
            var skills: [DirectoryEntryPayload]
            var count: Int
        }

        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SearchPayload.self, from: data)
        else {
            return nil
        }

        return (buildDiscoverSkills(from: payload.skills), payload.count)
    }

    private func parseSkillsDirectoryObjects(_ text: String) -> [DirectoryEntryPayload] {
        var entries: [DirectoryEntryPayload] = []
        var searchStart = text.startIndex
        let marker = "{\"source\":"

        while let markerRange = text.range(of: marker, range: searchStart..<text.endIndex),
              let object = extractBalancedJSONSection(
                  in: text,
                  startingAt: markerRange.lowerBound,
                  opening: "{",
                  closing: "}"
              ) {
            if let data = object.section.data(using: .utf8),
               let entry = try? JSONDecoder().decode(DirectoryEntryPayload.self, from: data) {
                entries.append(entry)
            }
            searchStart = text.index(after: object.endIndex)
        }

        return entries
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
                baseDescription: nil,
                baseDescriptionLocale: "en",
                localizedDescription: nil,
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

        return extractBalancedJSONSection(in: html, startingAt: start, opening: opening, closing: closing)?.section
    }

    private func extractBalancedJSONSection(
        in text: String,
        startingAt start: String.Index,
        opening: Character,
        closing: Character
    ) -> (section: String, endIndex: String.Index)? {
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]

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
                        return (String(text[start...index]), index)
                    }
                }
            }

            index = text.index(after: index)
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

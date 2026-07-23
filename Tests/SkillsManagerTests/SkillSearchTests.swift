import Testing
@testable import SkillsManager

struct SkillSearchTests {
    @Test
    func searchMatchesAllTermsAcrossUsefulMetadata() {
        let result = SkillSearch.results(
            in: Skill.mockSkills,
            query: SkillSearchQuery(text: "swift macos")
        )

        #expect(result.map(\.name) == ["swiftui-expert-skill"])
    }

    @Test
    func searchIncludesPluginSourceAndTags() {
        let result = SkillSearch.results(
            in: Skill.mockSkills,
            query: SkillSearchQuery(text: "plugin-cache discovery")
        )

        #expect(result.map(\.name) == ["find-skills"])
    }

    @Test
    func filtersComposeAsAnIntersection() {
        let result = SkillSearch.results(
            in: Skill.mockSkills,
            query: SkillSearchQuery(
                installState: .trial,
                source: "plugin-cache",
                agent: "Claude Code"
            )
        )

        #expect(result.map(\.name) == ["find-skills"])

        let starred = SkillSearch.results(
            in: Skill.mockSkills,
            query: SkillSearchQuery(
                installState: .trial,
                source: "plugin-cache",
                agent: "Claude Code",
                starredOnly: true
            )
        )
        #expect(starred.isEmpty)
    }

    @Test
    func clearFiltersKeepsTheSearchText() {
        var query = SkillSearchQuery(
            text: "swift",
            installState: .installed,
            source: "Local",
            agent: "Claude Code",
            starredOnly: true
        )
        #expect(query.activeFilterCount == 4)

        query.clearFilters()

        #expect(query.text == "swift")
        #expect(query.activeFilterCount == 0)
    }

    @Test
    func emptyQueryPreservesScannerOrder() {
        let input = Array(Skill.mockSkills.reversed())

        #expect(SkillSearch.results(in: input, query: SkillSearchQuery()).map(\.id) == input.map(\.id))
    }

    @Test
    func exactNameRanksAheadOfDescriptionOnlyMatch() {
        var descriptionMatch = Skill.mockSkills[0]
        descriptionMatch.displayName = "Version Control"
        descriptionMatch.name = "version-control"

        var exactMatch = Skill.mockSkills[1]
        exactMatch.displayName = "Commit"
        exactMatch.name = "commit"

        let result = SkillSearch.results(
            in: [descriptionMatch, exactMatch],
            query: SkillSearchQuery(text: "commit")
        )

        #expect(result.map(\.name) == ["commit", "version-control"])
    }
}

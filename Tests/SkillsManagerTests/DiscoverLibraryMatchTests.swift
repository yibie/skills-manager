import Foundation
import Testing
@testable import SkillsManager

struct DiscoverLibraryMatchTests {
    private func makeEntry(
        source: String = "vercel-labs/agent-skills",
        skillId: String = "commit",
        name: String = "commit"
    ) -> DiscoverSkill {
        DiscoverSkill(
            id: "\(source):\(skillId)",
            source: source,
            skillId: skillId,
            name: name,
            installs: 0,
            repoURL: URL(string: "https://github.com/\(source)")!,
            installCommand: ""
        )
    }

    private func makeSkill(name: String, provenance: SkillProvenance) -> Skill {
        let dir = URL(fileURLWithPath: "/tmp/skills/\(name)")
        return Skill(
            id: "local:\(name)",
            name: name,
            displayName: name,
            baseDescription: "",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            source: .local,
            version: nil,
            filePath: dir.appendingPathComponent("SKILL.md"),
            directoryPath: dir,
            provenance: provenance,
            compatibleAgents: [],
            tags: [],
            markdownContent: "",
            frontmatter: [:]
        )
    }

    @Test
    func provenanceExactMatchIsInstalled() {
        let skill = makeSkill(name: "commit", provenance: SkillProvenance(
            provider: .skillsManager,
            sourceURL: URL(string: "https://github.com/vercel-labs/agent-skills")!,
            skillID: "commit"
        ))
        #expect(DiscoverLibraryMatcher.match(entry: makeEntry(), in: [skill]) == .installed(skill))
        #expect(DiscoverLibraryMatcher.isInstalled(entry: makeEntry(), in: [skill]))
    }

    @Test
    func sameNameFromDifferentRepoIsNotInstalled() {
        let skill = makeSkill(name: "commit", provenance: SkillProvenance(
            provider: .skillsManager,
            sourceURL: URL(string: "https://github.com/someone-else/other-skills")!,
            skillID: "commit"
        ))
        #expect(DiscoverLibraryMatcher.match(entry: makeEntry(), in: [skill]) == .sameNameOnly)
        #expect(!DiscoverLibraryMatcher.isInstalled(entry: makeEntry(), in: [skill]))
    }

    @Test
    func handWrittenSkillWithPopularNameIsNotInstalled() {
        let skill = makeSkill(name: "commit", provenance: .manual)
        #expect(DiscoverLibraryMatcher.match(entry: makeEntry(), in: [skill]) == .sameNameOnly)
        #expect(!DiscoverLibraryMatcher.isInstalled(entry: makeEntry(), in: [skill]))
    }

    @Test
    func gitSuffixAndCasingDoNotBreakTheMatch() {
        let skill = makeSkill(name: "commit", provenance: SkillProvenance(
            provider: .skillsCLI,
            sourceURL: URL(string: "https://github.com/Vercel-Labs/Agent-Skills.git")!,
            skillID: "commit"
        ))
        #expect(DiscoverLibraryMatcher.isInstalled(entry: makeEntry(), in: [skill]))
    }

    @Test
    func unrelatedSkillsProduceNoMatch() {
        let skill = makeSkill(name: "review", provenance: .manual)
        #expect(DiscoverLibraryMatcher.match(entry: makeEntry(), in: [skill]) == DiscoverLibraryMatch.none)
    }
}

import Foundation
import Testing
@testable import SkillsManager

struct CollectionSupportTests {
    private func skill(
        id: String,
        name: String,
        directoryPath: URL? = nil,
        sourceURL: URL? = nil,
        provenanceSkillID: String? = nil
    ) -> Skill {
        let directoryPath = directoryPath ?? URL(fileURLWithPath: "/tmp/sk/\(name)")
        return Skill(
            id: id, name: name, displayName: name,
            baseDescription: "", baseDescriptionLocale: "en", localizedDescription: nil,
            source: .local, version: nil,
            filePath: directoryPath.appendingPathComponent("SKILL.md"),
            directoryPath: directoryPath,
            provenance: SkillProvenance(
                provider: sourceURL == nil ? .manual : .skillsManager,
                sourceURL: sourceURL,
                skillID: provenanceSkillID
            ),
            compatibleAgents: [], tags: [], markdownContent: "", frontmatter: [:]
        )
    }

    @Test
    func resolvesStableIDBeforeLegacyID() {
        let stable = skill(
            id: "legacy:wrong",
            name: "review",
            sourceURL: URL(string: "https://github.com/example/repo"),
            provenanceSkillID: "review"
        )
        let legacyCollision = skill(id: stable.persistenceID, name: "other")

        let result = CollectionSupport.resolveMemberIDs([stable.persistenceID], skills: [stable, legacyCollision])

        #expect(result.members.map(\.id) == ["legacy:wrong"])
        #expect(result.missingIDs.isEmpty)
        #expect(result.reconciledIDs == [stable.persistenceID])
    }

    @Test
    func resolvesLegacyIDAndReconcilesToStableID() {
        let current = skill(
            id: "legacy:review",
            name: "review",
            sourceURL: URL(string: "https://github.com/example/repo"),
            provenanceSkillID: "review"
        )

        let result = CollectionSupport.resolveMemberIDs(["legacy:review"], skills: [current])

        #expect(result.members == [current])
        #expect(result.missingIDs.isEmpty)
        #expect(result.reconciledIDs == [current.persistenceID])
    }

    // 迁移后 Universal id 从 path-keyed 变 sanitized name-keyed:精确候选 → 重写到稳定 id
    @Test
    func rewritesMigratedUniversalPathKeyedIDByExactCandidate() {
        let skills = [
            skill(id: "universal:code-review", name: "Code Review"),
            skill(id: "local:commit", name: "commit"),
        ]
        let result = CollectionSupport.reconcileMemberIDs(
            ["universal:/Users/x/.codex/skills/Code Review", "local:commit"],
            skills: skills
        )
        #expect(result == skills.map(\.persistenceID))
    }

    // 库里没有同名技能:保持原 id(诚实显示缺失)
    @Test
    func keepsUnresolvedID() {
        #expect(CollectionSupport.reconcileMemberIDs(["local:ghost"], skills: []) == ["local:ghost"])
        let skills = [skill(id: "local:commit", name: "commit")]
        #expect(CollectionSupport.reconcileMemberIDs(["local:ghost"], skills: skills) == ["local:ghost"])
        #expect(CollectionSupport.resolveMemberIDs(["local:ghost"], skills: skills).missingIDs == ["local:ghost"])
    }

    @Test
    func doesNotRebindGenericStalePathOrSourceIDByName() {
        let skills = [skill(id: "local:commit", name: "commit")]

        #expect(CollectionSupport.reconcileMemberIDs(
            ["local:/Users/x/.codex/skills/commit", "plugin:old:commit", "universal:other/commit"],
            skills: skills
        ) == ["local:/Users/x/.codex/skills/commit", "plugin:old:commit", "universal:other/commit"])
    }

    @Test
    func keepsUniversalPathMissingWithoutExactMigratedCandidate() {
        let skills = [
            skill(id: "local:review", name: "review"),
            skill(id: "plugin:src:plug:review", name: "review"),
        ]
        let old = "universal:/Users/x/.codex/skills/review"

        #expect(CollectionSupport.resolveMemberIDs([old], skills: skills).missingIDs == [old])
    }

    @Test
    func protectsMembersMountedByAnotherCollectionOnSameAgentOnly() {
        let shared = skill(id: "local:shared", name: "shared")
        let mine = CollectionRecord(name: "Mine", memberSkillIDs: [shared.persistenceID], mountedAgentIDs: ["codex"])
        let sameAgent = CollectionRecord(name: "Same", memberSkillIDs: [shared.persistenceID], mountedAgentIDs: ["codex"])
        let differentAgent = CollectionRecord(name: "Different", memberSkillIDs: [shared.persistenceID], mountedAgentIDs: ["claude-code"])

        #expect(CollectionSupport.protectedMountedMemberIDs(
            excluding: mine,
            agentID: "codex",
            collections: [mine, sameAgent, differentAgent],
            skills: [shared]
        ) == [shared.persistenceID])

        #expect(CollectionSupport.protectedMountedMemberIDs(
            excluding: mine,
            agentID: "claude-code",
            collections: [mine, sameAgent, differentAgent],
            skills: [shared]
        ) == [shared.persistenceID])

        #expect(CollectionSupport.protectedMountedMemberIDs(
            excluding: mine,
            agentID: "codex",
            collections: [mine, differentAgent],
            skills: [shared]
        ).isEmpty)
    }
}

import Foundation
import Testing
@testable import SkillsManager

struct CollectionSupportTests {
    private func skill(id: String, name: String) -> Skill {
        Skill(
            id: id, name: name, displayName: name,
            baseDescription: "", baseDescriptionLocale: "en", localizedDescription: nil,
            source: .local, version: nil,
            filePath: URL(fileURLWithPath: "/tmp/sk/\(name)/SKILL.md"),
            directoryPath: URL(fileURLWithPath: "/tmp/sk/\(name)"),
            compatibleAgents: [], tags: [], markdownContent: "", frontmatter: [:]
        )
    }

    // 迁移后 id 从 path-keyed 变 name-keyed:唯一同名 → 重写到新 id
    @Test
    func rewritesMigratedPathKeyedIDByName() {
        let skills = [
            skill(id: "universal:review", name: "review"),
            skill(id: "local:commit", name: "commit"),
        ]
        let result = CollectionSupport.reconcileMemberIDs(
            ["universal:/Users/x/.codex/skills/review", "local:commit"],
            skills: skills
        )
        #expect(result == ["universal:review", "local:commit"])
    }

    // 库里没有同名技能:保持原 id(诚实显示缺失)
    @Test
    func keepsUnresolvedID() {
        #expect(CollectionSupport.reconcileMemberIDs(["local:ghost"], skills: []) == ["local:ghost"])
        let skills = [skill(id: "local:commit", name: "commit")]
        #expect(CollectionSupport.reconcileMemberIDs(["local:ghost"], skills: skills) == ["local:ghost"])
    }

    // 多个同名技能:无法判断是哪个,保持原 id
    @Test
    func keepsAmbiguousID() {
        let skills = [
            skill(id: "universal:review", name: "review"),
            skill(id: "plugin:src:plug:review", name: "review"),
        ]
        let old = "universal:/Users/x/.codex/skills/review"
        #expect(CollectionSupport.reconcileMemberIDs([old], skills: skills) == [old])
    }
}

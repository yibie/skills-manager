import Foundation
import Testing
@testable import SkillsManager

struct SkillPromotionTests {
    @Test
    func stripsPathTraversalFromFrontmatterNames() {
        #expect(SkillStore.promotedDirectoryName(
            displayName: "../../../etc", directoryName: "safe-skill") == "etc")
    }

    @Test
    func neverProducesAPathSeparator() {
        let name = SkillStore.promotedDirectoryName(
            displayName: "weird/nested\\name", directoryName: "x")
        #expect(!name.contains("/"))
        #expect(name == "weird-nested-name")
    }

    @Test
    func fallsBackToTheDirectoryNameWhenDisplayNameIsEmpty() {
        #expect(SkillStore.promotedDirectoryName(
            displayName: "", directoryName: "My Skill") == "my-skill")
    }

    @Test
    func degenerateNamesStillGetAUsableDirectory() {
        #expect(SkillStore.promotedDirectoryName(
            displayName: "///", directoryName: "") == "unnamed-skill")
    }
}

import Foundation
import Testing
@testable import SkillsManager

struct SkillConflictDetectionTests {
    private func skill(
        name: String,
        directory: String,
        content: String,
        agents: [String] = ["Claude Code"],
        source: SkillSource = .local
    ) -> Skill {
        Skill(
            id: "\(source):\(directory)",
            name: name,
            displayName: name,
            baseDescription: "",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            source: source,
            version: nil,
            filePath: URL(fileURLWithPath: directory).appendingPathComponent("SKILL.md"),
            directoryPath: URL(fileURLWithPath: directory),
            compatibleAgents: agents,
            tags: [],
            markdownContent: content,
            frontmatter: [:]
        )
    }

    @Test
    func divergedCopiesAcrossAgentsAreAConflict() {
        let scanned = [
            skill(name: "commit", directory: "/home/.claude/skills/commit", content: "v1", agents: ["Claude Code"]),
            skill(name: "commit", directory: "/home/.cursor/skills/commit", content: "v2", agents: ["Cursor"]),
        ]
        let conflicts = SkillConflictDetection.detect(in: scanned)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].name == "commit")
        #expect(conflicts[0].instances.count == 2)
        #expect(Set(conflicts[0].instances.flatMap(\.agents)) == ["Claude Code", "Cursor"])
        #expect(conflicts[0].instances[0].contentHash != conflicts[0].instances[1].contentHash)
    }

    @Test
    func identicalCopiesAreNotAConflict() {
        let scanned = [
            skill(name: "commit", directory: "/home/.claude/skills/commit", content: "same"),
            skill(name: "commit", directory: "/home/.cursor/skills/commit", content: "same"),
        ]
        #expect(SkillConflictDetection.detect(in: scanned).isEmpty)
    }

    @Test
    func singleCopyServingMultipleAgentsIsNotAConflict() {
        let scanned = [
            skill(name: "commit", directory: "/home/.agents/skills/commit", content: "v1", agents: ["Amp"]),
            skill(name: "commit", directory: "/home/.agents/skills/commit", content: "v1", agents: ["Kimi Code CLI"]),
        ]
        #expect(SkillConflictDetection.detect(in: scanned).isEmpty)
    }

    @Test
    func pluginAndProjectCopiesAreExcluded() {
        let scanned = [
            skill(name: "commit", directory: "/home/.claude/skills/commit", content: "v1"),
            skill(
                name: "commit",
                directory: "/home/.claude/plugins/cache/x/commit/1.0/skills/commit",
                content: "v2",
                source: .plugin(pluginSource: "x", pluginName: "commit")
            ),
            skill(
                name: "commit",
                directory: "/repo/.claude/skills/commit",
                content: "v3",
                source: .projectLocal(projectURL: URL(fileURLWithPath: "/repo"))
            ),
        ]
        #expect(SkillConflictDetection.detect(in: scanned).isEmpty)
    }

    @Test
    func differentNamesAreNotAConflict() {
        let scanned = [
            skill(name: "commit", directory: "/home/.claude/skills/commit", content: "v1"),
            skill(name: "done", directory: "/home/.cursor/skills/done", content: "v2"),
        ]
        #expect(SkillConflictDetection.detect(in: scanned).isEmpty)
    }
}

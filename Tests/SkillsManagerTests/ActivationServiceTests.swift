import Foundation
import Testing
@testable import SkillsManager

struct ActivationServiceTests {
    private func makeSandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("activation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 在 originDir 下造一个实体技能目录(source: .local)。
    private func makeLocalSkill(name: String, originDir: URL) throws -> Skill {
        let dir = originDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# \(name)".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
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
            compatibleAgents: [],
            tags: [],
            markdownContent: "# \(name)",
            frontmatter: [:]
        )
    }

    // MARK: status 纯函数

    @Test
    func statusMatrix() {
        #expect(ActivationService.status(intentMounted: true, linkedCount: 3, memberCount: 3) == .mounted)
        #expect(ActivationService.status(intentMounted: false, linkedCount: 0, memberCount: 3) == .unmounted)
        #expect(ActivationService.status(intentMounted: true, linkedCount: 1, memberCount: 3) == .diverged)
        #expect(ActivationService.status(intentMounted: false, linkedCount: 2, memberCount: 3) == .diverged)
        #expect(ActivationService.status(intentMounted: true, linkedCount: 0, memberCount: 0) == .diverged)
        #expect(ActivationService.status(intentMounted: false, linkedCount: 0, memberCount: 0) == .unmounted)
    }

    // MARK: 挂载:实体技能迁移 canonical + 原处留 link + 目标 agent 挂 link

    @Test
    func mountMigratesEntitySkillAndLinksBothSides() throws {
        let root = try makeSandbox()
        let origin = root.appendingPathComponent("claude-skills")
        let agentDir = root.appendingPathComponent("codex-skills")
        let canonical = root.appendingPathComponent("canonical")
        let skill = try makeLocalSkill(name: "commit", originDir: origin)

        let report = try ActivationService.mount(skills: [skill], agentSkillsDir: agentDir, canonicalDir: canonical)
        #expect(report.changed == ["local:commit"])
        #expect(report.skipped.isEmpty)

        let fm = FileManager.default
        // canonical 持有实体
        #expect(fm.fileExists(atPath: canonical.appendingPathComponent("commit/SKILL.md").path))
        #expect(fm.fileExists(atPath: canonical.appendingPathComponent("commit/\(SymlinkInstaller.managedMarkerName)").path))
        // 原处变成指向 canonical 的 link(原 agent 不受影响)
        let originDest = try fm.destinationOfSymbolicLink(atPath: origin.appendingPathComponent("commit").path)
        #expect(originDest == canonical.appendingPathComponent("commit").path)
        // 目标 agent 挂上 link
        let agentDest = try fm.destinationOfSymbolicLink(atPath: agentDir.appendingPathComponent("commit").path)
        #expect(agentDest == canonical.appendingPathComponent("commit").path)
        #expect(ActivationService.probeLinkedCount(memberSkills: [skill], agentSkillsDir: agentDir, canonicalDir: canonical) == 1)
    }

    // MARK: 冲突:目标已有同名实体 → 跳过不阻塞

    @Test
    func mountSkipsConflictingRealDirectory() throws {
        let root = try makeSandbox()
        let origin = root.appendingPathComponent("claude-skills")
        let agentDir = root.appendingPathComponent("codex-skills")
        let canonical = root.appendingPathComponent("canonical")
        let skillA = try makeLocalSkill(name: "commit", originDir: origin)
        let skillB = try makeLocalSkill(name: "done", originDir: origin)
        // 目标 agent 已有同名实体目录(非 link)
        let conflictDir = agentDir.appendingPathComponent("commit")
        try FileManager.default.createDirectory(at: conflictDir, withIntermediateDirectories: true)
        try "other".write(to: conflictDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let report = try ActivationService.mount(skills: [skillA, skillB], agentSkillsDir: agentDir, canonicalDir: canonical)
        #expect(report.changed == ["local:done"])
        #expect(report.skipped.count == 1)
        #expect(report.skipped[0].skillID == "local:commit")
        // 冲突目录原样保留
        #expect(try String(contentsOf: conflictDir.appendingPathComponent("SKILL.md"), encoding: .utf8) == "other")
    }

    // MARK: 卸载:只删 link,canonical 保留;实体目录不动

    @Test
    func unmountRemovesLinkButKeepsCanonicalAndRealDirs() throws {
        let root = try makeSandbox()
        let origin = root.appendingPathComponent("claude-skills")
        let agentDir = root.appendingPathComponent("codex-skills")
        let canonical = root.appendingPathComponent("canonical")
        let skill = try makeLocalSkill(name: "commit", originDir: origin)
        _ = try ActivationService.mount(skills: [skill], agentSkillsDir: agentDir, canonicalDir: canonical)

        let report = ActivationService.unmount(skills: [skill], agentSkillsDir: agentDir, canonicalDir: canonical)
        #expect(report.changed == ["local:commit"])
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: agentDir.appendingPathComponent("commit").path))
        #expect(fm.fileExists(atPath: canonical.appendingPathComponent("commit/SKILL.md").path))

        // 实体目录(非 link)不删,记 skipped
        let realDir = agentDir.appendingPathComponent("realone")
        try fm.createDirectory(at: realDir, withIntermediateDirectories: true)
        let realSkill = Skill(
            id: "local:realone", name: "realone", displayName: "realone",
            baseDescription: "", baseDescriptionLocale: "en", localizedDescription: nil,
            source: .local, version: nil,
            filePath: realDir.appendingPathComponent("SKILL.md"), directoryPath: realDir,
            compatibleAgents: [], tags: [], markdownContent: "", frontmatter: [:]
        )
        let report2 = ActivationService.unmount(skills: [realSkill], agentSkillsDir: agentDir, canonicalDir: canonical)
        #expect(report2.skipped.count == 1)
        #expect(fm.fileExists(atPath: realDir.path))
    }
}

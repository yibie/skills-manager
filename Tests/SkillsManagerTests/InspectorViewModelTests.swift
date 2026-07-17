import Foundation
import Testing
import SkillsKernel
@testable import SkillsManager

// MARK: - 检视器(M3)单元测试
// 覆盖:spec 列表发现、报告 → 展示模型的转换、最近项目持久化、扫描错误路径。
// 全部不依赖 AppKit;文件系统操作使用临时目录,home 注入,不触碰真实 ~/.claude。

// MARK: 报告 → 展示模型

struct InspectorPresentationTests {
    /// 手写一份符合 effective-agent-schema 的报告 JSON(结构化构造走 Codable,
    /// 与内核的数据契约保持同一入口)。
    private func makeReport() throws -> EffectiveAgentReport {
        let json = """
        {
          "schema_version": 1,
          "generated_at": "2026-07-16T10:00:00Z",
          "platform": { "id": "claude-code", "name": "Claude Code", "version_range": ">=2.0" },
          "project": { "path": "/Users/me/prj/demo" },
          "spec": { "schema_version": 1, "generated_by": "human+ai", "last_verified": "2026-07-14" },
          "summary": { "resources": 5, "active": 3, "shadowed": 1, "missing": 1, "unmodeled": 1 },
          "resources": {
            "identity": [],
            "guidance": [
              { "key": "CLAUDE.md", "rule_id": "project-claude-md", "path": "/p/CLAUDE.md",
                "scope": "project", "status": "active", "required": false, "confidence": "high" },
              { "rule_id": "global-claude-md", "path": "/home/.claude/CLAUDE.md",
                "scope": "global", "status": "missing", "required": false, "confidence": "high" }
            ],
            "skill": [
              { "key": "demo", "rule_id": "project-skills", "path": "/p/.claude/skills/demo/SKILL.md",
                "scope": "project", "status": "active", "required": false, "confidence": "high" },
              { "key": "demo", "rule_id": "global-skills", "path": "/home/.claude/skills/demo/SKILL.md",
                "scope": "global", "status": "shadowed", "required": false, "confidence": "low",
                "shadowed_by": {
                  "shadow_rule_id": "project-skill-shadows-global",
                  "winner_rule_id": "project-skills",
                  "winner_path": "/p/.claude/skills/demo/SKILL.md"
                } }
            ],
            "runtime-config": [
              { "key": ".mcp.json", "rule_id": "project-mcp", "path": "/p/.mcp.json",
                "scope": "project", "status": "active", "required": false, "confidence": "high",
                "count": { "value": 2, "unit": "servers" } }
            ]
          },
          "unmodeled": [
            { "path": "/home/.claude/mystery", "root": "/home/.claude", "scope": "global" }
          ]
        }
        """
        return try JSONDecoder().decode(EffectiveAgentReport.self, from: Data(json.utf8))
    }

    @Test
    func sectionsAlwaysCoverFourResourceTypesInGoalOrder() throws {
        let presentation = InspectorPresentation(report: try makeReport())
        #expect(presentation.sections.map(\.title) == ["Identity", "Guidance", "Skills", "Runtime"])
        #expect(presentation.sections[0].rows.isEmpty)
        #expect(presentation.sections[1].rows.count == 2)
        #expect(presentation.sections[2].rows.count == 2)
        #expect(presentation.sections[3].rows.count == 1)
    }

    @Test
    func summaryAndHeaderFieldsAreCarriedThrough() throws {
        let presentation = InspectorPresentation(report: try makeReport())
        #expect(presentation.platformName == "Claude Code")
        #expect(presentation.projectPath == "/Users/me/prj/demo")
        #expect(presentation.specLastVerified == "2026-07-14")
        #expect(presentation.summary == InspectorSummary(
            resources: 5, active: 3, shadowed: 1, missing: 1, unmodeled: 1
        ))
    }

    @Test
    func shadowedRowExposesWinnerPathAndLowConfidenceFlag() throws {
        let presentation = InspectorPresentation(report: try makeReport())
        let shadowed = try #require(presentation.sections[2].rows.first { $0.status == .shadowed })
        #expect(shadowed.name == "demo")
        #expect(shadowed.scope == .global)
        #expect(shadowed.shadowedByPath == "/p/.claude/skills/demo/SKILL.md")
        #expect(shadowed.lowConfidence)

        let active = try #require(presentation.sections[2].rows.first { $0.status == .active })
        #expect(active.shadowedByPath == nil)
        #expect(!active.lowConfidence)
    }

    @Test
    func missingRowFallsBackToExpectedPathFileNameForItsName() throws {
        let presentation = InspectorPresentation(report: try makeReport())
        let missing = try #require(presentation.sections[1].rows.first { $0.status == .missing })
        #expect(missing.name == "CLAUDE.md")
        #expect(missing.path == "/home/.claude/CLAUDE.md")
    }

    @Test
    func runtimeRowRendersShallowCountText() throws {
        let presentation = InspectorPresentation(report: try makeReport())
        let runtime = try #require(presentation.sections[3].rows.first)
        #expect(runtime.countText == "2 servers")
    }

    @Test
    func unmodeledItemsAreListedSeparatelyAndRowLookupWorks() throws {
        let presentation = InspectorPresentation(report: try makeReport())
        #expect(presentation.unmodeled.map(\.path) == ["/home/.claude/mystery"])

        let someRow = try #require(presentation.sections[1].rows.first)
        #expect(presentation.row(withID: someRow.id) == someRow)
        #expect(presentation.row(withID: "not-a-row") == nil)
        #expect(presentation.row(withID: nil) == nil)
    }

    @Test
    func rowIDsAreUniqueEvenWhenRulesSharePaths() throws {
        let presentation = InspectorPresentation(report: try makeReport())
        let ids = presentation.sections.flatMap(\.rows).map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

// MARK: spec 列表发现 + 最近项目

@MainActor
struct InspectorViewModelStateTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "inspector-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func discoversBundledSpecsAndPreselectsFirstParseableOne() throws {
        let model = InspectorViewModel(defaults: try makeDefaults())
        #expect(model.specs.contains { $0.platformID == "claude-code" })
        let selected = try #require(model.selectedSpec)
        #expect(selected.loadError == nil)
    }

    @Test
    func specsDirectoryOverrideIsDiscoveredAndCanFallBackToBundled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("inspector-specs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundled = try #require(SpecCatalog.bundledSpecsDirectory)
        try FileManager.default.copyItem(
            at: bundled.appendingPathComponent("claude-code.yaml"),
            to: directory.appendingPathComponent("custom.yaml")
        )

        let model = InspectorViewModel(defaults: try makeDefaults())
        model.setSpecsDirectory(directory)
        #expect(model.specs.map { $0.url.lastPathComponent } == ["custom.yaml"])
        #expect(model.selectedSpec?.platformID == "claude-code")

        model.setSpecsDirectory(nil)
        #expect(model.specsDirectoryOverride == nil)
        #expect(model.specs.contains { $0.url.lastPathComponent == "claude-code.yaml" })
    }

    @Test
    func recentProjectsAreDedupedCappedAndPersisted() throws {
        let defaults = try makeDefaults()
        let model = InspectorViewModel(defaults: defaults)

        for index in 0..<(InspectorViewModel.recentProjectsLimit + 2) {
            model.selectProject(URL(fileURLWithPath: "/tmp/project-\(index)"))
        }
        model.selectProject(URL(fileURLWithPath: "/tmp/project-5"))

        #expect(model.recentProjects.count == InspectorViewModel.recentProjectsLimit)
        #expect(model.recentProjects.first == "/tmp/project-5")
        #expect(model.recentProjects.filter { $0 == "/tmp/project-5" }.count == 1)

        // 持久化:新实例从同一 defaults 读回同一列表
        let reloaded = InspectorViewModel(defaults: defaults)
        #expect(reloaded.recentProjects == model.recentProjects)
    }

    @Test
    func rescanWithoutProjectStaysIdle() throws {
        let model = InspectorViewModel(defaults: try makeDefaults())
        model.rescan()
        if case .idle = model.phase {} else {
            Issue.record("未选项目时应保持 idle,实际为 \(model.phase)")
        }
    }
}

// MARK: 扫描通路(内核进程内调用)

struct InspectorScannerTests {
    private func makeTempDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func scanProducesReportForEmptyProjectWithInjectedHome() async throws {
        let bundled = try #require(SpecCatalog.bundledSpecsDirectory)
        let home = try makeTempDirectory("inspector-home")
        let project = try makeTempDirectory("inspector-project")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: project)
        }
        try "# demo".write(
            to: project.appendingPathComponent("CLAUDE.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = await InspectorScanner.scan(
            specURL: bundled.appendingPathComponent("claude-code.yaml"),
            schemaURL: bundled.appendingPathComponent("schema.json"),
            projectURL: project,
            home: home
        )
        let report = try result.get()
        #expect(report.platform.id == "claude-code")
        let projectClaudeMD = report.resources.guidance.first { $0.ruleId == "project-claude-md" }
        #expect(projectClaudeMD?.status == .active)
        #expect(report.summary.resources > 0)
    }

    @Test
    func scanFailsReadablyForMissingProject() async throws {
        let bundled = try #require(SpecCatalog.bundledSpecsDirectory)
        let result = await InspectorScanner.scan(
            specURL: bundled.appendingPathComponent("claude-code.yaml"),
            schemaURL: bundled.appendingPathComponent("schema.json"),
            projectURL: URL(fileURLWithPath: "/nonexistent/project-\(UUID().uuidString)"),
            home: FileManager.default.temporaryDirectory
        )
        guard case .failure(let error) = result else {
            Issue.record("缺失项目目录时应失败")
            return
        }
        #expect(error.message.contains("项目目录不存在"))
    }

    @Test
    func scanFailsReadablyForInvalidSpec() async throws {
        let bundled = try #require(SpecCatalog.bundledSpecsDirectory)
        let directory = try makeTempDirectory("inspector-bad-spec")
        defer { try? FileManager.default.removeItem(at: directory) }
        let badSpec = directory.appendingPathComponent("bad.yaml")
        try "schema_version: 1\nplatform:\n  id: x\n".write(
            to: badSpec, atomically: true, encoding: .utf8
        )

        let result = await InspectorScanner.scan(
            specURL: badSpec,
            schemaURL: bundled.appendingPathComponent("schema.json"),
            projectURL: FileManager.default.temporaryDirectory,
            home: FileManager.default.temporaryDirectory
        )
        guard case .failure(let error) = result else {
            Issue.record("无效 spec 应失败而非产出报告")
            return
        }
        #expect(error.message.contains("spec 未通过校验") || error.message.contains("spec 无法读取"))
    }
}

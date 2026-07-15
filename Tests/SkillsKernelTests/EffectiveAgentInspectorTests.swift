import XCTest
@testable import SkillsKernel

/// 基于 Fixtures/tree 假目录树的 Effective-Agent 检视器(M2)测试。
/// home 注入为 Fixtures/tree/home,不依赖真实 ~/.claude。
final class EffectiveAgentInspectorTests: XCTestCase {
    private var fixturesURL: URL {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures") else {
            fatalError("测试资源 Fixtures 缺失")
        }
        return url
    }

    /// 仓库内的 effective-agent-schema.json(测试 bundle 外,经由源文件路径定位)。
    private var reportSchemaURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/SkillsKernelTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // 仓库根
            .appendingPathComponent("docs/goals/effective-agent-schema.json")
    }

    private func makeReport() throws -> EffectiveAgentReport {
        let spec = try SpecLoader.loadTyped(
            fileURL: fixturesURL.appendingPathComponent("specs/inspect.yaml")
        )
        let inspector = EffectiveAgentInspector(
            spec: spec,
            projectRoot: fixturesURL.appendingPathComponent("tree/project"),
            home: fixturesURL.appendingPathComponent("tree/home"),
            specPath: "specs/inspect.yaml"
        )
        return inspector.run()
    }

    private func instance(
        _ report: EffectiveAgentReport, rule: String, key: String?
    ) -> ResourceInstance? {
        report.resources.all.first { $0.ruleId == rule && $0.key == key }
    }

    // MARK: 遮蔽计算

    func testProjectSkillShadowsGlobalSameName() throws {
        let report = try makeReport()

        // 全局 demo 被项目 demo 遮蔽,归因到 shadowing 规则与遮蔽方路径
        let globalDemo = try XCTUnwrap(instance(report, rule: "global-skills", key: "demo"))
        XCTAssertEqual(globalDemo.status, .shadowed)
        let shadowedBy = try XCTUnwrap(globalDemo.shadowedBy)
        XCTAssertEqual(shadowedBy.shadowRuleId, "project-skill-shadows-global")
        XCTAssertEqual(shadowedBy.winnerRuleId, "project-skills")
        XCTAssertTrue(shadowedBy.winnerPath.hasSuffix("project/.claude/skills/demo/SKILL.md"))

        // 遮蔽方本身 active;不同名的全局 skill 不受影响
        XCTAssertEqual(instance(report, rule: "project-skills", key: "demo")?.status, .active)
        let globalOnly = try XCTUnwrap(instance(report, rule: "global-skills", key: "global-only"))
        XCTAssertEqual(globalOnly.status, .active)
        XCTAssertNil(globalOnly.shadowedBy)
    }

    func testIdentityShadowingByAgentName() throws {
        let report = try makeReport()

        let globalReviewer = try XCTUnwrap(instance(report, rule: "global-agents", key: "reviewer"))
        XCTAssertEqual(globalReviewer.status, .shadowed)
        XCTAssertEqual(globalReviewer.shadowedBy?.shadowRuleId, "project-agent-shadows-global")
        XCTAssertEqual(instance(report, rule: "global-agents", key: "helper")?.status, .active)
        XCTAssertEqual(instance(report, rule: "project-agents", key: "reviewer")?.status, .active)
    }

    func testMergeStrategyDoesNotShadow() throws {
        let report = try makeReport()
        // CLAUDE.md 叠加注入(merge):双方都 active,不产生 shadowed
        XCTAssertEqual(instance(report, rule: "global-claude-md", key: "CLAUDE.md")?.status, .active)
        XCTAssertEqual(instance(report, rule: "project-claude-md", key: "CLAUDE.md")?.status, .active)
        // 子目录 CLAUDE.md 由 glob 实例化
        let subdir = try XCTUnwrap(instance(report, rule: "subdir-claude-md", key: "CLAUDE.md"))
        XCTAssertTrue(subdir.path.hasSuffix("project/sub/CLAUDE.md"))
        XCTAssertEqual(subdir.scope, .directory)
    }

    // MARK: missing 与 runtime 计数

    func testMissingResourceInstance() throws {
        let report = try makeReport()
        let missing = try XCTUnwrap(instance(report, rule: "missing-config", key: nil))
        XCTAssertEqual(missing.status, .missing)
        XCTAssertTrue(missing.path.hasSuffix("/.claude/nope.json"))
        XCTAssertNil(missing.count)
        // required/confidence 显式透传,不被缺省值隐藏
        XCTAssertTrue(missing.required)
        XCTAssertEqual(missing.confidence, .low)
    }

    func testRuntimeConfigShallowCounts() throws {
        let report = try makeReport()
        XCTAssertEqual(
            instance(report, rule: "project-mcp", key: ".mcp.json")?.count,
            InstanceCount(value: 2, unit: "servers")
        )
        XCTAssertEqual(
            instance(report, rule: "global-settings", key: "settings.json")?.count,
            InstanceCount(value: 2, unit: "hook-events")
        )
        // 未配置计数的 runtime-config:count 缺席而非 0
        let local = try XCTUnwrap(
            instance(report, rule: "project-settings-local", key: "settings.local.json")
        )
        XCTAssertEqual(local.status, .active)
        XCTAssertNil(local.count)
    }

    // MARK: unmodeled 与 summary

    func testUnmodeledPassthroughWithScope() throws {
        let report = try makeReport()
        XCTAssertEqual(report.unmodeled.count, 2)

        let mystery = try XCTUnwrap(report.unmodeled.first { $0.path.hasSuffix("/mystery-dir") })
        XCTAssertEqual(mystery.scope, .global)
        let stray = try XCTUnwrap(report.unmodeled.first { $0.path.hasSuffix("/stray.txt") })
        XCTAssertEqual(stray.scope, .project)
    }

    func testSummaryCounts() throws {
        let report = try makeReport()
        XCTAssertEqual(
            report.summary,
            ReportSummary(resources: 13, active: 10, shadowed: 2, missing: 1, unmodeled: 2)
        )
        XCTAssertEqual(report.resources.guidance.count, 3)
        XCTAssertEqual(report.resources.skill.count, 3)
        XCTAssertEqual(report.resources.identity.count, 3)
        XCTAssertEqual(report.resources.runtimeConfig.count, 4)
    }

    // MARK: JSON 输出与公共契约

    func testJSONOutputValidatesAgainstEffectiveAgentSchema() throws {
        // 自举:用内核自己的 SchemaValidator 校验 inspect 输出是否符合公开契约
        let report = try makeReport()
        let json = try report.renderJSON(pretty: true)
        let instance = try JSONValue.fromJSON(Data(json.utf8))
        let validator = try SchemaValidator(schemaFileURL: reportSchemaURL)
        let issues = validator.validate(instance)
        XCTAssertTrue(issues.isEmpty, "输出违反 effective-agent-schema.json: \(issues)")
    }

    func testJSONCarriesMetadataAndStableShape() throws {
        let report = try makeReport()
        let json = try report.renderJSON()
        let value = try JSONValue.fromJSON(Data(json.utf8))

        XCTAssertEqual(value["schema_version"], .int(1))
        XCTAssertEqual(value["platform"]?["id"], .string("fixture-platform"))
        XCTAssertEqual(value["spec"]?["last_verified"], .string("2026-07-16"))
        XCTAssertEqual(value["spec"]?["path"], .string("specs/inspect.yaml"))
        // 四个类型分组键始终存在
        let groups = try XCTUnwrap(value["resources"]?.objectValue)
        XCTAssertEqual(
            Set(groups.keys),
            ["identity", "guidance", "skill", "runtime-config"]
        )
        // missing 实例的 key 以缺席表达"无实例可标识",而非空串
        let runtime = try XCTUnwrap(value["resources"]?["runtime-config"]?.arrayValue)
        let missing = try XCTUnwrap(runtime.first { $0["status"] == .string("missing") })
        XCTAssertNil(missing["key"])
    }

    func testInspectorIsReadOnly() throws {
        let treeURL = fixturesURL.appendingPathComponent("tree")
        func snapshot() -> Set<String> {
            let enumerator = FileManager.default.enumerator(atPath: treeURL.path)
            return Set(enumerator?.compactMap { $0 as? String } ?? [])
        }
        let before = snapshot()
        _ = try makeReport()
        XCTAssertEqual(before, snapshot())
    }
}

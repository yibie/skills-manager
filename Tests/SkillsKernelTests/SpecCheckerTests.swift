import XCTest
@testable import SkillsKernel

/// 基于 Fixtures/tree 假目录树的 check 逻辑测试。
/// home 注入为 Fixtures/tree/home,不依赖真实 ~/.claude。
final class SpecCheckerTests: XCTestCase {
    private var fixturesURL: URL {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures") else {
            fatalError("测试资源 Fixtures 缺失")
        }
        return url
    }

    private func makeReport() throws -> CheckReport {
        let spec = try SpecLoader.loadTyped(
            fileURL: fixturesURL.appendingPathComponent("specs/valid.yaml")
        )
        let checker = SpecChecker(
            spec: spec,
            projectRoot: fixturesURL.appendingPathComponent("tree/project"),
            home: fixturesURL.appendingPathComponent("tree/home")
        )
        return checker.run()
    }

    private func result(_ report: CheckReport, _ id: String) -> ResourceCheckResult? {
        report.resources.first { $0.resource.id == id }
    }

    func testPresentAndMissingStatuses() throws {
        let report = try makeReport()

        XCTAssertEqual(result(report, "global-claude-md")?.isPresent, true)
        XCTAssertEqual(result(report, "global-settings")?.isPresent, true)
        XCTAssertEqual(result(report, "global-skills")?.isPresent, true)
        XCTAssertEqual(result(report, "project-claude-md")?.isPresent, true)
        XCTAssertEqual(result(report, "project-mcp")?.isPresent, true)
        XCTAssertEqual(result(report, "project-skills")?.isPresent, true)
        XCTAssertEqual(result(report, "project-settings-local")?.isPresent, true)
        XCTAssertEqual(result(report, "global-missing-file")?.isPresent, false)

        XCTAssertEqual(report.presentCount, 8)
        XCTAssertEqual(report.missingCount, 1)
        XCTAssertTrue(report.requiredMissing.isEmpty)
    }

    func testRuntimeConfigCounts() throws {
        let report = try makeReport()

        // settings.json 的 hooks 有 PreToolUse/Stop 两个事件
        XCTAssertEqual(result(report, "global-settings")?.count, CountResult(value: 2, unit: "hook-events"))
        // .mcp.json 的 mcpServers 有 alpha/beta 两个
        XCTAssertEqual(result(report, "project-mcp")?.count, CountResult(value: 2, unit: "servers"))
        // 缺失的文件不产生计数
        XCTAssertNil(result(report, "global-missing-file")?.count)
    }

    func testDirectoryScopeGlobExcludesProjectRoot() throws {
        let report = try makeReport()
        guard case .present(let matches)? = result(report, "subdir-claude-md")?.status else {
            return XCTFail("subdir-claude-md 应为 present")
        }
        // 只命中 sub/CLAUDE.md;项目根 CLAUDE.md 由 project-claude-md 单独建模,不重复
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].hasSuffix("/sub/CLAUDE.md"))
    }

    func testUnmodeledScanFindsStraysAndRespectsIgnore() throws {
        let report = try makeReport()
        let unmodeledPaths = report.unmodeled.map(\.path)

        // 假 home 里的 mystery-dir 未建模 → 必须浮出
        XCTAssertTrue(unmodeledPaths.contains { $0.hasSuffix("/.claude/mystery-dir") })
        // 项目 .claude 里的 stray.txt 未建模 → 必须浮出
        XCTAssertTrue(unmodeledPaths.contains { $0.hasSuffix("/.claude/stray.txt") })
        // projects 在 ignore 列表 → 不得报告
        XCTAssertFalse(unmodeledPaths.contains { $0.hasSuffix("/.claude/projects") })
        // 已建模路径(settings.json、skills 等)不得误报
        XCTAssertFalse(unmodeledPaths.contains { $0.hasSuffix("/settings.json") })
        XCTAssertFalse(unmodeledPaths.contains { $0.hasSuffix("/skills") })
        XCTAssertEqual(report.unmodeled.count, 2)
    }

    func testRenderTextMentionsKeyFacts() throws {
        let report = try makeReport()
        let text = report.renderText(homePath: fixturesURL.appendingPathComponent("tree/home").path)

        XCTAssertTrue(text.contains("[present]"))
        XCTAssertTrue(text.contains("[missing]"))
        XCTAssertTrue(text.contains("[unmodeled]"))
        XCTAssertTrue(text.contains("(2 servers)"))
        XCTAssertTrue(text.contains("~/.claude/nope.json"))
        XCTAssertTrue(text.contains("8 present, 1 missing, 2 unmodeled"))
    }

    func testCheckerIsReadOnly() throws {
        // 跑一遍 check 前后,fixture 树的文件清单不应有任何变化
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

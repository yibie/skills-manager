import XCTest
@testable import SkillsKernel

/// SpecCatalog(M3:spec 目录发现 + 内置资源副本)的用例。
final class SpecCatalogTests: XCTestCase {
    /// 仓库根(经由源文件路径定位,用于对照 platform-specs/ 源文件)。
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/SkillsKernelTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // 仓库根
    }

    // MARK: 内置资源副本

    func testBundledSpecsDirectoryContainsClaudeCodeSpecAndSchema() throws {
        let directory = try XCTUnwrap(SpecCatalog.bundledSpecsDirectory, "内置 platform-specs 资源缺失")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("claude-code.yaml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("schema.json").path))
    }

    func testBundledSpecPassesSchemaAndSemanticValidation() throws {
        let directory = try XCTUnwrap(SpecCatalog.bundledSpecsDirectory)
        let specURL = directory.appendingPathComponent("claude-code.yaml")
        let raw = try SpecLoader.loadRaw(fileURL: specURL)
        let validator = try SchemaValidator(schemaFileURL: directory.appendingPathComponent("schema.json"))
        XCTAssertTrue(validator.validate(raw).isEmpty)

        let spec = try SpecLoader.loadTyped(fileURL: specURL)
        XCTAssertTrue(SpecLoader.semanticIssues(in: spec).isEmpty)
        XCTAssertEqual(spec.platform.id, "claude-code")
    }

    /// 内置副本必须与仓库 platform-specs/ 源文件逐字节一致——副本不许悄悄漂移。
    func testBundledSpecsStayInSyncWithRepositorySources() throws {
        let bundled = try XCTUnwrap(SpecCatalog.bundledSpecsDirectory)
        let source = repositoryRoot.appendingPathComponent("platform-specs")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: source.path),
            "仓库 platform-specs/ 不可达(测试在仓库外运行),跳过同步核对"
        )
        for name in ["claude-code.yaml", "schema.json"] {
            let bundledData = try Data(contentsOf: bundled.appendingPathComponent(name))
            let sourceData = try Data(contentsOf: source.appendingPathComponent(name))
            XCTAssertEqual(
                bundledData, sourceData,
                "\(name) 的内置副本与 platform-specs/\(name) 不一致;请重新复制到 Sources/SkillsKernel/Resources/platform-specs/"
            )
        }
    }

    // MARK: 目录发现

    func testDiscoverListsSpecsAndReportsBrokenOnesHonestly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-catalog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let bundled = try XCTUnwrap(SpecCatalog.bundledSpecsDirectory)
        try FileManager.default.copyItem(
            at: bundled.appendingPathComponent("claude-code.yaml"),
            to: directory.appendingPathComponent("claude-code.yaml")
        )
        try "platform: [broken".write(
            to: directory.appendingPathComponent("broken.yaml"),
            atomically: true,
            encoding: .utf8
        )
        try "not a spec".write(
            to: directory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let entries = SpecCatalog.discover(in: directory)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, ["broken.yaml", "claude-code.yaml"])

        let broken = entries[0]
        XCTAssertNil(broken.platformID)
        XCTAssertNotNil(broken.loadError)
        XCTAssertEqual(broken.displayName, "broken.yaml")

        let claude = entries[1]
        XCTAssertEqual(claude.platformID, "claude-code")
        XCTAssertEqual(claude.displayName, "Claude Code")
        XCTAssertNil(claude.loadError)
    }

    func testDiscoverReturnsEmptyForUnreadableDirectory() {
        let missing = URL(fileURLWithPath: "/nonexistent/spec-catalog-\(UUID().uuidString)")
        XCTAssertTrue(SpecCatalog.discover(in: missing).isEmpty)
    }

    func testSchemaURLPrefersSiblingAndFallsBackToBundled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-catalog-schema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // 无同目录 schema.json → 退回内置副本
        let bundledFallback = try XCTUnwrap(SpecCatalog.schemaURL(for: directory))
        XCTAssertEqual(
            bundledFallback,
            SpecCatalog.bundledSpecsDirectory?.appendingPathComponent("schema.json")
        )

        // 有同目录 schema.json → 优先同目录
        let sibling = directory.appendingPathComponent("schema.json")
        try "{}".write(to: sibling, atomically: true, encoding: .utf8)
        XCTAssertEqual(SpecCatalog.schemaURL(for: directory)?.path, sibling.path)
    }
}

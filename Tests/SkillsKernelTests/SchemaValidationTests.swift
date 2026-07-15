import XCTest
@testable import SkillsKernel

/// schema 校验(结构 + 语义)的用例。fixture 见 Fixtures/specs 与 Fixtures/schema.json。
final class SchemaValidationTests: XCTestCase {
    private var fixturesURL: URL {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("Fixtures") else {
            fatalError("测试资源 Fixtures 缺失")
        }
        return url
    }

    private func makeValidator() throws -> SchemaValidator {
        try SchemaValidator(schemaFileURL: fixturesURL.appendingPathComponent("schema.json"))
    }

    func testValidSpecPassesSchemaAndSemantics() throws {
        let specURL = fixturesURL.appendingPathComponent("specs/valid.yaml")
        let raw = try SpecLoader.loadRaw(fileURL: specURL)
        let issues = try makeValidator().validate(raw)
        XCTAssertTrue(issues.isEmpty, "结构校验应通过,实际问题: \(issues)")

        let spec = try SpecLoader.loadTyped(fileURL: specURL)
        XCTAssertEqual(spec.platform.id, "fixture-platform")
        XCTAssertEqual(spec.resources.count, 9)
        let semanticIssues = SpecLoader.semanticIssues(in: spec)
        XCTAssertTrue(semanticIssues.isEmpty, "语义校验应通过,实际问题: \(semanticIssues)")
    }

    func testStructurallyInvalidSpecIsRejected() throws {
        let specURL = fixturesURL.appendingPathComponent("specs/invalid-structural.yaml")
        let raw = try SpecLoader.loadRaw(fileURL: specURL)
        let issues = try makeValidator().validate(raw)

        // 缺 source、缺 confidence、type 枚举非法、未知字段 frobnicate
        XCTAssertTrue(issues.contains { $0.path == "/resources/0" && $0.message.contains("source") })
        XCTAssertTrue(issues.contains { $0.path == "/resources/0" && $0.message.contains("confidence") })
        XCTAssertTrue(issues.contains { $0.path == "/resources/1/type" && $0.message.contains("banana") })
        XCTAssertTrue(issues.contains { $0.path == "/resources/1/frobnicate" })
    }

    func testMissingTopLevelFieldsAreRejected() throws {
        let raw = try JSONValue.fromYAML("schema_version: 1")
        let issues = try makeValidator().validate(raw)
        XCTAssertTrue(issues.contains { $0.message.contains("platform") })
        XCTAssertTrue(issues.contains { $0.message.contains("metadata") })
        XCTAssertTrue(issues.contains { $0.message.contains("resources") })
    }

    func testUnquotedYAMLDateIsNormalizedToString() throws {
        // YAML 会把未加引号的日期解析成时间戳,归一化后应仍满足 pattern
        let raw = try JSONValue.fromYAML("last_verified: 2026-07-14")
        XCTAssertEqual(raw["last_verified"], .string("2026-07-14"))
    }

    func testSemanticallyInvalidSpecIsRejected() throws {
        let specURL = fixturesURL.appendingPathComponent("specs/invalid-semantic.yaml")
        // 该 fixture 结构合法(schema 层面通过)……
        let raw = try SpecLoader.loadRaw(fileURL: specURL)
        XCTAssertTrue(try makeValidator().validate(raw).isEmpty)

        // ……但语义层面必须报:id 重复、count 用错类型、引用悬空、路径与 scope 不符
        let spec = try SpecLoader.loadTyped(fileURL: specURL)
        let issues = SpecLoader.semanticIssues(in: spec)
        XCTAssertTrue(issues.contains { $0.message.contains("resource id 重复") })
        XCTAssertTrue(issues.contains { $0.message.contains("count 只允许用于 runtime-config") })
        XCTAssertTrue(issues.contains { $0.message.contains("ghost-resource") })
        XCTAssertTrue(issues.contains { $0.message.contains("global scope 的路径") })
    }

    func testJSONPointerLookup() throws {
        let json = try JSONValue.fromJSON(Data(#"{"a": {"b": [10, 20]}, "hooks": {"Stop": []}}"#.utf8))
        XCTAssertEqual(json.value(atPointer: "/a/b/1"), .int(20))
        XCTAssertEqual(json.value(atPointer: "/hooks")?.objectValue?.count, 1)
        XCTAssertNil(json.value(atPointer: "/missing"))
    }

    func testGlobMatching() {
        XCTAssertTrue(Glob.matches(path: "sub/CLAUDE.md", pattern: "**/CLAUDE.md"))
        XCTAssertTrue(Glob.matches(path: "a/b/c/CLAUDE.md", pattern: "**/CLAUDE.md"))
        XCTAssertTrue(Glob.matches(path: "CLAUDE.md", pattern: "**/CLAUDE.md"))
        XCTAssertFalse(Glob.matches(path: "sub/OTHER.md", pattern: "**/CLAUDE.md"))
        XCTAssertTrue(Glob.matches(path: "cache/m/p/1.0.0/skills", pattern: "cache/*/*/*/skills"))
        XCTAssertFalse(Glob.matches(path: "cache/m/p/skills", pattern: "cache/*/*/*/skills"))
        XCTAssertTrue(Glob.matchComponent(".last-update", pattern: ".last-*"))
        XCTAssertFalse(Glob.matchComponent("last-update", pattern: ".last-*"))
    }
}

/// 对仓库真实文件的验收测试:platform-specs/claude-code.yaml 必须能通过
/// platform-specs/schema.json 的校验。仓库布局不存在时跳过(如单独分发测试包)。
final class RepoSpecTests: XCTestCase {
    private var repoRoot: URL {
        // Tests/SkillsKernelTests/RepoSpecTests.swift → 仓库根
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testClaudeCodeSpecValidates() throws {
        let schemaURL = repoRoot.appendingPathComponent("platform-specs/schema.json")
        let specURL = repoRoot.appendingPathComponent("platform-specs/claude-code.yaml")
        guard FileManager.default.fileExists(atPath: schemaURL.path),
              FileManager.default.fileExists(atPath: specURL.path)
        else {
            throw XCTSkip("仓库 platform-specs 布局不存在,跳过")
        }

        let validator = try SchemaValidator(schemaFileURL: schemaURL)
        let raw = try SpecLoader.loadRaw(fileURL: specURL)
        let issues = validator.validate(raw)
        XCTAssertTrue(issues.isEmpty, "claude-code.yaml 结构问题: \(issues)")

        let spec = try SpecLoader.loadTyped(fileURL: specURL)
        XCTAssertEqual(spec.platform.id, "claude-code")
        let semanticIssues = SpecLoader.semanticIssues(in: spec)
        XCTAssertTrue(semanticIssues.isEmpty, "claude-code.yaml 语义问题: \(semanticIssues)")

        // 每条规则必须有 source(schema 已强制)且不确定的规则如实标注
        XCTAssertTrue(spec.resources.allSatisfy { !$0.source.isEmpty })
    }
}

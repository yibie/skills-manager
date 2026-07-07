import Foundation
import Testing
@testable import SkillsManager

struct AgentDocsServiceTests {
    @Test
    func manifestRoundTripsAndDetectsExistingTargets() throws {
        let project = try makeProject()
        try "# Project\n".write(to: project.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "Soul".write(to: project.appendingPathComponent("agent-docs/SOUL.md"), atomically: true, encoding: .utf8)

        let snapshot = try AgentDocsService().load(projectURL: project)

        #expect(snapshot.docs.map(\.file) == ["SOUL.md"])
        #expect(snapshot.manifest.targets.contains { $0.agentId == "claude-code" && $0.entryFile == "CLAUDE.md" })
    }

    @Test
    func injectSyncIsIdempotentAndDetectsDrift() throws {
        let project = try makeProject()
        let service = AgentDocsService()
        try "# Existing\n".write(to: project.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
        try "Soul".write(to: project.appendingPathComponent("agent-docs/SOUL.md"), atomically: true, encoding: .utf8)
        _ = try service.updateTargets(projectURL: project, targets: [
            .init(agentId: "claude-code", entryFile: "CLAUDE.md", mode: .inject)
        ])

        let synced = try service.sync(projectURL: project)
        let firstContent = try String(contentsOf: project.appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        let syncedAgain = try service.sync(projectURL: project)
        let secondContent = try String(contentsOf: project.appendingPathComponent("CLAUDE.md"), encoding: .utf8)

        #expect(firstContent == secondContent)
        #expect(synced.statuses.first?.state == .inSync)
        #expect(syncedAgain.statuses.first?.state == .inSync)

        try "Soul v2".write(to: project.appendingPathComponent("agent-docs/SOUL.md"), atomically: true, encoding: .utf8)
        let drifted = try service.load(projectURL: project)
        #expect(drifted.statuses.first?.state == .outOfSync)
    }

    @Test
    func referenceModeWritesLinksOnly() throws {
        let project = try makeProject()
        let service = AgentDocsService()
        try "Soul".write(to: project.appendingPathComponent("agent-docs/SOUL.md"), atomically: true, encoding: .utf8)
        _ = try service.updateTargets(projectURL: project, targets: [
            .init(agentId: "codex", entryFile: "AGENTS.md", mode: .reference)
        ])

        _ = try service.sync(projectURL: project)
        let content = try String(contentsOf: project.appendingPathComponent("AGENTS.md"), encoding: .utf8)

        #expect(content.contains("Read the following documents"))
        #expect(content.contains("[SOUL.md](agent-docs/SOUL.md)"))
        #expect(!content.contains("<!-- source: agent-docs/SOUL.md -->"))
    }

    @Test
    func bundledTemplatesLoad() throws {
        let templates = AgentDocTemplateService(
            userTemplatesURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-templates-\(UUID().uuidString)")
        ).templates()

        #expect(templates.map(\.fileName).contains("SOUL.md"))
        #expect(templates.count >= 5)
    }

    @Test
    func singleMarkerThrows() throws {
        let project = try makeProject()
        let service = AgentDocsService()
        try AgentDocsService.beginMarker.write(to: project.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)
        try "Soul".write(to: project.appendingPathComponent("agent-docs/SOUL.md"), atomically: true, encoding: .utf8)
        _ = try service.updateTargets(projectURL: project, targets: [
            .init(agentId: "codex", entryFile: "AGENTS.md", mode: .inject)
        ])

        do {
            _ = try service.sync(projectURL: project)
            Issue.record("Expected single marker error")
        } catch AgentDocsServiceError.singleManagedMarker("AGENTS.md") {
            #expect(Bool(true))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private func makeProject() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-docs-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url.appendingPathComponent("agent-docs"), withIntermediateDirectories: true)
    return url
}

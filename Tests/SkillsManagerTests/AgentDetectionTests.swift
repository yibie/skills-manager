import Foundation
import Testing
@testable import SkillsManager

struct AgentDetectionTests {
    @Test
    func openClawDoesNotClaimTheSharedAgentsDirectory() {
        let shared = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills")
            .standardizedFileURL

        #expect(!OpenClawAdapter().skillsDirectories.map(\.standardizedFileURL).contains(shared))
    }

    @Test
    func duplicateScansOfTheSameFileMergeTheirAgents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-detection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let canonical = root.appendingPathComponent("canonical/example")
        let codexLink = root.appendingPathComponent("codex/example")
        let openClawLink = root.appendingPathComponent("openclaw/example")
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        try "---\nname: example\n---\n".write(
            to: canonical.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(at: codexLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: openClawLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: codexLink, withDestinationURL: canonical)
        try FileManager.default.createSymbolicLink(at: openClawLink, withDestinationURL: canonical)

        let merged = SkillStore.mergeScannedSkills([
            scannedSkill(id: "universal:example", source: .local, directory: codexLink, agents: ["Codex"]),
            scannedSkill(id: "openclaw:example", source: .openClaw(root: "skills"), directory: openClawLink, agents: ["OpenClaw"]),
        ])

        #expect(merged.count == 1)
        #expect(merged.first?.source == .local)
        #expect(merged.first?.compatibleAgents == ["Codex", "OpenClaw"])
    }

    @Test
    func sameIDAtDifferentPathsDoesNotMerge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-id-collision-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first/example")
        let second = root.appendingPathComponent("second/example")
        try createSkill(at: first)
        try createSkill(at: second)

        let merged = SkillStore.mergeScannedSkills([
            scannedSkill(id: "same-id", source: .local, directory: first, agents: ["Codex"]),
            scannedSkill(id: "same-id", source: .openClaw(root: "workspace"), directory: second, agents: ["OpenClaw"]),
        ])

        #expect(merged.count == 2)
    }

    @Test
    func universalAdapterKeepsSameNamedSkillsAtDifferentPaths() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("universal-same-name-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try createSkill(at: first.appendingPathComponent("example"))
        try createSkill(at: second.appendingPathComponent("example"))

        let adapter = UniversalAdapter(
            canonicalSkillsDirectory: root.appendingPathComponent("canonical"),
            sharedSkillsDirectories: [first, second],
            installedAgents: [],
            importedPaths: [:]
        )
        let skills = try await adapter.scanSkills()

        #expect(skills.count == 2)
        #expect(Set(skills.map(\.id)).count == 2)
    }

    @Test
    func openClawRootsProduceDistinctIDs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-roots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first/skills")
        let second = root.appendingPathComponent("second/skills")
        try createSkill(at: first.appendingPathComponent("example"))
        try createSkill(at: second.appendingPathComponent("example"))

        let adapter = OpenClawAdapter(roots: [
            .init(id: "first", url: first),
            .init(id: "second", url: second),
        ])
        let skills = try await adapter.scanSkills()

        #expect(skills.count == 2)
        #expect(Set(skills.map(\.id)) == ["openclaw:first:example", "openclaw:second:example"])
    }

    @Test
    func universalAdapterAlwaysIncludesTheSharedAgentsDirectory() {
        let shared = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills")
            .standardizedFileURL

        #expect(UniversalAdapter().skillsDirectories.map(\.standardizedFileURL).contains(shared))
    }

    @Test
    func externalSkillsAreNotMarkedCanonical() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-skill-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let canonical = root.appendingPathComponent("canonical")
        let external = root.appendingPathComponent("external")
        try createSkill(at: external.appendingPathComponent("example"))

        let adapter = UniversalAdapter(
            canonicalSkillsDirectory: canonical,
            sharedSkillsDirectories: [external],
            installedAgents: [],
            importedPaths: [:]
        )
        let skill = try #require(try await adapter.scanSkills().first)

        #expect(skill.canonicalPath == nil)
    }

    @Test
    func canonicalSkillsAreMarkedCanonical() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-skill-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try SymlinkInstaller.install(
            content: "---\nname: example\n---\n",
            skillName: "example",
            agentIDs: [],
            canonicalSkillsDirectory: root,
            importedPaths: [:]
        )

        let adapter = UniversalAdapter(
            canonicalSkillsDirectory: root,
            sharedSkillsDirectories: [root],
            installedAgents: [],
            importedPaths: [:]
        )
        let skill = try #require(try await adapter.scanSkills().first)

        #expect(skill.canonicalPath?.standardizedFileURL.path == root.appendingPathComponent("example").standardizedFileURL.path)
    }

    @Test
    func unmarkedCanonicalSkillIsReadOnly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unmarked-canonical-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try createSkill(at: root.appendingPathComponent("example"))

        let adapter = UniversalAdapter(
            canonicalSkillsDirectory: root,
            sharedSkillsDirectories: [root],
            installedAgents: [],
            importedPaths: [:]
        )
        let skill = try #require(try await adapter.scanSkills().first)

        #expect(skill.canonicalPath == nil)
    }

    @MainActor
    @Test
    func uninstallDoesNotHideOrDeleteAnExternalSkill() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-uninstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try createSkill(at: root)

        let skill = scannedSkill(id: "external", source: .local, directory: root, agents: ["OpenCode"])
        let store = SkillStore()
        store.skills = [skill]

        await store.uninstallSkill(skill)

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("SKILL.md").path))
        #expect(store.skills.contains(where: { $0.id == skill.id }))
        #expect(store.errorMessage != nil)
    }

    @Test
    func openCodeCanBeImportedAndDetectedFromItsCLI() throws {
        let missing = AgentRegistry.missingInstallTargets(
            importedPaths: [:],
            fileExists: { _ in false },
            executableExists: { _ in false }
        )
        #expect(missing.contains(where: { $0.id == "opencode" }))

        let installed = AgentRegistry.installedInstallTargets(
            importedPaths: [:],
            fileExists: { _ in false },
            executableExists: { $0 == "opencode" }
        )
        #expect(installed.contains(where: { $0.id == "opencode" }))

        let opencode = try #require(AgentRegistry.agent(id: "opencode"))
        #expect(opencode.cliCommands == ["opencode"])

        let importedPath = "/tmp/custom-opencode-skills"
        #expect(
            AgentRegistry.resolvedSkillsDir(
                for: opencode,
                importedPaths: ["opencode": importedPath]
            ).path == importedPath
        )
    }

    @Test
    func openCodeDetectionUsesTheConfiguredXDGDirectory() throws {
        let opencode = try #require(AgentRegistry.agent(id: "opencode"))
        let expected = AgentRegistry.xdgConfig.appendingPathComponent("opencode").path

        #expect(opencode.detectPath == expected)
        #expect(opencode.detectPath.hasPrefix("/"))
        #expect(AgentRegistry.resolvedDetectPath(for: opencode, importedPaths: [:]) == expected)
    }

    @Test
    func xdgDirectoryUsesInjectedEnvironment() {
        let home = URL(fileURLWithPath: "/tmp/home")

        #expect(
            AgentRegistry.xdgConfigDirectory(
                environment: ["XDG_CONFIG_HOME": "/tmp/custom-xdg"],
                home: home
            ).path == "/tmp/custom-xdg"
        )
        #expect(AgentRegistry.xdgConfigDirectory(environment: [:], home: home).path == "/tmp/home/.config")
        #expect(
            AgentRegistry.xdgConfigDirectory(
                environment: ["XDG_CONFIG_HOME": "relative-config"],
                home: home
            ).path == "/tmp/home/.config"
        )
    }
}

private func createSkill(at directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "---\nname: example\n---\n".write(
        to: directory.appendingPathComponent("SKILL.md"),
        atomically: true,
        encoding: .utf8
    )
}

private func scannedSkill(
    id: String,
    source: SkillSource,
    directory: URL,
    agents: [String]
) -> Skill {
    Skill(
        id: id,
        name: "example",
        displayName: "Example",
        baseDescription: "",
        baseDescriptionLocale: "en",
        localizedDescription: nil,
        source: source,
        version: nil,
        filePath: directory.appendingPathComponent("SKILL.md"),
        directoryPath: directory,
        compatibleAgents: agents,
        tags: [],
        markdownContent: "",
        frontmatter: [:]
    )
}

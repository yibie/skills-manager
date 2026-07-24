import Foundation
import Testing
@testable import SkillsManager

struct UpdateSafetyTests {
    private func makeSandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 在 canonical 根下造一个受管技能目录(带 managed marker)。
    private func makeManagedCanonicalSkill(
        named name: String,
        content: String,
        in canonicalRoot: URL
    ) throws -> URL {
        let dir = canonicalRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "1\n".write(
            to: dir.appendingPathComponent(SymlinkInstaller.managedMarkerName),
            atomically: true,
            encoding: .utf8
        )
        return dir
    }

    private func makeSkill(name: String, canonicalPath: URL) -> Skill {
        Skill(
            id: "local:\(name)",
            name: name,
            displayName: name,
            baseDescription: "",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            source: .local,
            version: nil,
            filePath: canonicalPath.appendingPathComponent("SKILL.md"),
            directoryPath: canonicalPath,
            canonicalPath: canonicalPath,
            compatibleAgents: [],
            tags: [],
            markdownContent: "",
            frontmatter: [:]
        )
    }

    @Test
    func replacingAManagedSkillPreservesTheOldCopyInHistory() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.appendingPathComponent("canonical")
        try FileManager.default.createDirectory(at: canonicalRoot, withIntermediateDirectories: true)
        _ = try makeManagedCanonicalSkill(named: "example", content: "old content", in: canonicalRoot)

        let source = root.appendingPathComponent("incoming/example")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "new content".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        try SymlinkInstaller.install(
            sourceDirectory: source,
            skillName: "example",
            agentIDs: [],
            canonicalSkillsDirectory: canonicalRoot,
            importedPaths: [:]
        )

        #expect(try String(
            contentsOf: canonicalRoot.appendingPathComponent("example/SKILL.md"), encoding: .utf8
        ) == "new content")

        let history = SymlinkInstaller.historyDirectory(canonicalSkillsDirectory: canonicalRoot)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []
        #expect(entries.count == 1)
        if let entry = entries.first {
            let preserved = history.appendingPathComponent(entry).appendingPathComponent("SKILL.md")
            #expect(try String(contentsOf: preserved, encoding: .utf8) == "old content")
        }
    }

    @Test
    func freshInstallLeavesNoHistoryBehind() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.appendingPathComponent("canonical")

        let source = root.appendingPathComponent("incoming/example")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "content".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        try SymlinkInstaller.install(
            sourceDirectory: source,
            skillName: "example",
            agentIDs: [],
            canonicalSkillsDirectory: canonicalRoot,
            importedPaths: [:]
        )

        let history = SymlinkInstaller.historyDirectory(canonicalSkillsDirectory: canonicalRoot)
        #expect(!FileManager.default.fileExists(atPath: history.path))
    }

    @Test
    func driftIsDetectedOnlyWhenTheLocalCopyChanged() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.appendingPathComponent("canonical")
        let dir = try makeManagedCanonicalSkill(named: "example", content: "installed content", in: canonicalRoot)

        let manifest: [String: Any] = [
            "sourceURL": "https://github.com/acme/skills",
            "skillID": "example",
            "installedAt": 0,
            "contentHash": SkillContentHasher.hash("installed content"),
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: dir.appendingPathComponent(SymlinkInstaller.managedManifestName))

        let service = SkillLifecycleService(canonicalSkillsDirectory: canonicalRoot)
        let skill = makeSkill(name: "example", canonicalPath: dir)
        #expect(!service.hasLocalDrift(skill))

        try "locally edited".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(service.hasLocalDrift(skill))
    }

    @Test
    func legacyManifestsWithoutHashDoNotBlockUpdates() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.appendingPathComponent("canonical")
        let dir = try makeManagedCanonicalSkill(named: "example", content: "installed content", in: canonicalRoot)

        let manifest: [String: Any] = [
            "sourceURL": "https://github.com/acme/skills",
            "skillID": "example",
            "installedAt": 0,
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: dir.appendingPathComponent(SymlinkInstaller.managedManifestName))

        let service = SkillLifecycleService(canonicalSkillsDirectory: canonicalRoot)
        let skill = makeSkill(name: "example", canonicalPath: dir)
        try "locally edited".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        #expect(!service.hasLocalDrift(skill))
    }

    @Test
    func forgedManifestFromUntrustedHostLosesTheUpdateChannel() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.appendingPathComponent("canonical")
        let dir = try makeManagedCanonicalSkill(named: "example", content: "c", in: canonicalRoot)
        let manifest: [String: Any] = [
            "sourceURL": "https://evil.example/acme/skills",
            "skillID": "example",
            "installedAt": 0,
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: dir.appendingPathComponent(SymlinkInstaller.managedManifestName))

        let service = SkillLifecycleService(home: root, canonicalSkillsDirectory: canonicalRoot)
        let annotated = service.annotate([makeSkill(name: "example", canonicalPath: dir)])
        #expect(annotated[0].provenance.provider == .manual)
        #expect(!annotated[0].canUpdate)
    }

    @Test
    func githubManifestKeepsItsProvenance() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.appendingPathComponent("canonical")
        let dir = try makeManagedCanonicalSkill(named: "example", content: "c", in: canonicalRoot)
        let manifest: [String: Any] = [
            "sourceURL": "https://github.com/acme/skills",
            "skillID": "example",
            "installedAt": 0,
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: dir.appendingPathComponent(SymlinkInstaller.managedManifestName))

        let service = SkillLifecycleService(home: root, canonicalSkillsDirectory: canonicalRoot)
        let annotated = service.annotate([makeSkill(name: "example", canonicalPath: dir)])
        #expect(annotated[0].provenance.provider == .skillsManager)
        #expect(annotated[0].canUpdate)
    }

    @Test
    func migrationIntoTheLibraryStripsBundledManifests() throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = root.appendingPathComponent("canonical")
        let agentDir = root.appendingPathComponent("agent-skills")
        let origin = root.appendingPathComponent("origin/example")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try "# example".write(to: origin.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let forged: [String: Any] = [
            "sourceURL": "https://github.com/attacker/skills",
            "skillID": "example",
            "installedAt": 0,
        ]
        try JSONSerialization.data(withJSONObject: forged)
            .write(to: origin.appendingPathComponent(SymlinkInstaller.managedManifestName))

        let skill = Skill(
            id: "local:example",
            name: "example",
            displayName: "example",
            baseDescription: "",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            source: .local,
            version: nil,
            filePath: origin.appendingPathComponent("SKILL.md"),
            directoryPath: origin,
            compatibleAgents: [],
            tags: [],
            markdownContent: "# example",
            frontmatter: [:]
        )
        let report = try ActivationService.mount(skills: [skill], agentSkillsDir: agentDir, canonicalDir: canonicalRoot)
        #expect(report.changed == ["local:example"])

        let canonical = canonicalRoot.appendingPathComponent("example")
        #expect(FileManager.default.fileExists(atPath: canonical.appendingPathComponent("SKILL.md").path))
        #expect(!FileManager.default.fileExists(
            atPath: canonical.appendingPathComponent(SymlinkInstaller.managedManifestName).path
        ))
    }
}

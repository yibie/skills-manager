import Foundation
import Testing
@testable import SkillsManager

struct SymlinkInstallerTests {
    @Test
    func rejectsAnExistingDirectoryWithoutDeletingIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("install-conflict-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let canonical = root.appendingPathComponent("canonical")
        let imported = root.appendingPathComponent("opencode")
        let existing = imported.appendingPathComponent("example")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let sentinel = existing.appendingPathComponent("KEEP.txt")
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)

        #expect(throws: SymlinkInstallerError.self) {
            try SymlinkInstaller.install(
                content: "---\nname: example\n---\n",
                skillName: "example",
                agentIDs: ["opencode"],
                canonicalSkillsDirectory: canonical,
                importedPaths: ["opencode": imported.path]
            )
        }

        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(!FileManager.default.fileExists(atPath: canonical.appendingPathComponent("example").path))
    }

    @Test
    func doesNotOverwriteAnUnmarkedCanonicalSkill() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-conflict-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let existing = root.appendingPathComponent("example")
        try createInstallerSkill(at: existing)
        let sentinel = existing.appendingPathComponent("KEEP.txt")
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)

        #expect(throws: SymlinkInstallerError.self) {
            try SymlinkInstaller.install(
                content: "---\nname: replacement\n---\n",
                skillName: "example",
                agentIDs: [],
                canonicalSkillsDirectory: root,
                importedPaths: [:]
            )
        }

        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(try String(contentsOf: existing.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("name: example"))
    }

    @Test
    func safelyAdoptsMatchingLegacyCanonicalSkill() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let content = "---\nname: example\n---\n"
        let canonical = root.appendingPathComponent("canonical")
        let canonicalSkill = canonical.appendingPathComponent("example")
        let imported = root.appendingPathComponent("opencode")
        let link = imported.appendingPathComponent("example")
        try createInstallerSkill(at: canonicalSkill)
        try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: canonicalSkill)

        try SymlinkInstaller.install(
            content: content,
            skillName: "example",
            agentIDs: ["opencode"],
            canonicalSkillsDirectory: canonical,
            importedPaths: ["opencode": imported.path]
        )

        #expect(SymlinkInstaller.isManagedCanonicalDirectory(canonicalSkill))
        #expect(link.resolvingSymlinksInPath().standardizedFileURL.path == canonicalSkill.standardizedFileURL.path)
    }

    @Test
    func findsLegacyLinkOutsideTheNewlySelectedTargets() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-legacy-cross-target-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let content = "---\nname: example\n---\n"
        let canonical = root.appendingPathComponent("canonical")
        let canonicalSkill = canonical.appendingPathComponent("example")
        let codex = root.appendingPathComponent("codex")
        let codexLink = codex.appendingPathComponent("example")
        let openCode = root.appendingPathComponent("opencode")
        try createInstallerSkill(at: canonicalSkill)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: codexLink, withDestinationURL: canonicalSkill)

        try SymlinkInstaller.install(
            content: content,
            skillName: "example",
            agentIDs: ["opencode"],
            canonicalSkillsDirectory: canonical,
            importedPaths: ["codex": codex.path, "opencode": openCode.path]
        )

        #expect(SymlinkInstaller.isManagedCanonicalDirectory(canonicalSkill))
        #expect(
            openCode.appendingPathComponent("example").resolvingSymlinksInPath().standardizedFileURL.path
                == canonicalSkill.standardizedFileURL.path
        )
    }

    @Test
    func requiresMatchingContentAndExistingLinkForLegacyAdoption() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-legacy-guards-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let canonical = root.appendingPathComponent("canonical")
        let canonicalSkill = canonical.appendingPathComponent("example")
        let imported = root.appendingPathComponent("opencode")
        let link = imported.appendingPathComponent("example")
        try createInstallerSkill(at: canonicalSkill)

        #expect(throws: SymlinkInstallerError.self) {
            try SymlinkInstaller.install(
                content: "---\nname: example\n---\n",
                skillName: "example",
                agentIDs: ["opencode"],
                canonicalSkillsDirectory: canonical,
                importedPaths: ["opencode": imported.path]
            )
        }

        try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: canonicalSkill)
        #expect(throws: SymlinkInstallerError.self) {
            try SymlinkInstaller.install(
                content: "---\nname: replacement\n---\n",
                skillName: "example",
                agentIDs: ["opencode"],
                canonicalSkillsDirectory: canonical,
                importedPaths: ["opencode": imported.path]
            )
        }

        #expect(!SymlinkInstaller.isManagedCanonicalDirectory(canonicalSkill))
        #expect(
            try String(contentsOf: canonicalSkill.appendingPathComponent("SKILL.md"), encoding: .utf8)
                == "---\nname: example\n---\n"
        )
    }

    @Test
    func createsAndUninstallsOnlyItsOwnLink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("install-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let canonical = root.appendingPathComponent("canonical")
        let imported = root.appendingPathComponent("opencode")
        let importedPaths = ["opencode": imported.path]

        try SymlinkInstaller.install(
            content: "---\nname: example\n---\n",
            skillName: "example",
            agentIDs: ["opencode"],
            canonicalSkillsDirectory: canonical,
            importedPaths: importedPaths
        )

        let canonicalSkill = canonical.appendingPathComponent("example")
        let link = imported.appendingPathComponent("example")
        #expect(link.resolvingSymlinksInPath() == canonicalSkill.resolvingSymlinksInPath())

        try SymlinkInstaller.install(
            content: "---\nname: example\ndescription: updated\n---\n",
            skillName: "example",
            agentIDs: ["opencode"],
            canonicalSkillsDirectory: canonical,
            importedPaths: importedPaths
        )
        #expect(
            try String(contentsOf: canonicalSkill.appendingPathComponent("SKILL.md"), encoding: .utf8)
                .contains("description: updated")
        )

        try SymlinkInstaller.uninstall(
            skillName: "example",
            canonicalSkillsDirectory: canonical,
            importedPaths: importedPaths
        )

        let remainingDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        #expect(!FileManager.default.fileExists(atPath: canonicalSkill.path))
        #expect(remainingDestination == nil)
    }

    @Test
    func doesNotReplaceCanonicalDirectoryWithASelfLink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("install-self-link-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try SymlinkInstaller.install(
            content: "---\nname: example\n---\n",
            skillName: "example",
            agentIDs: ["opencode"],
            canonicalSkillsDirectory: root,
            importedPaths: ["opencode": root.path]
        )

        let skill = root.appendingPathComponent("example")
        let attributes = try FileManager.default.attributesOfItem(atPath: skill.path)
        #expect(attributes[.type] as? FileAttributeType == .typeDirectory)
        #expect(FileManager.default.fileExists(atPath: skill.appendingPathComponent("SKILL.md").path))
    }
}

private func createInstallerSkill(at directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "---\nname: example\n---\n".write(
        to: directory.appendingPathComponent("SKILL.md"),
        atomically: true,
        encoding: .utf8
    )
}

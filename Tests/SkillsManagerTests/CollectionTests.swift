import Foundation
import SwiftData
import Testing
@testable import SkillsManager

struct CollectionTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func skill(name: String, canonicalPath: URL) -> Skill {
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

    @Test @MainActor
    func recordPersistsMembersAndIntent() throws {
        let context = try makeContext()
        let record = CollectionRecord(
            name: "iOS 开发",
            sortOrder: 0,
            memberSkillIDs: ["local:commit", "plugin:cache:swiftui-expert"],
            mountedAgentIDs: ["claude-code"]
        )
        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CollectionRecord>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "iOS 开发")
        #expect(fetched[0].memberSkillIDs == ["local:commit", "plugin:cache:swiftui-expert"])
        #expect(fetched[0].mountedAgentIDs == ["claude-code"])
        #expect(fetched[0].projectPaths.isEmpty)
    }

    @Test @MainActor
    func memberMutationRoundTrips() throws {
        let context = try makeContext()
        let record = CollectionRecord(name: "写作")
        context.insert(record)
        try context.save()

        record.memberSkillIDs.append("local:renwei-writing")
        record.mountedAgentIDs.append("codex")
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CollectionRecord>())
        #expect(fetched[0].memberSkillIDs == ["local:renwei-writing"])
        #expect(fetched[0].mountedAgentIDs == ["codex"])
    }

    @Test @MainActor
    func refreshMountStatusesReportsPartialMissingMembers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let previousImports = UserDefaults.standard.dictionary(forKey: AppSettings.importedAgentFoldersKey)
        defer { UserDefaults.standard.set(previousImports, forKey: AppSettings.importedAgentFoldersKey) }

        let agentDir = root.appendingPathComponent("agent")
        let canonical = root.appendingPathComponent("canonical/linked")
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        try "# linked".write(to: canonical.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: agentDir.appendingPathComponent("linked").path,
            withDestinationPath: canonical.path
        )
        AgentRegistry.importManagedFolder(agentID: "codex", folderURL: agentDir)

        let linked = skill(name: "linked", canonicalPath: canonical)
        let collection = CollectionRecord(
            name: "Partial",
            memberSkillIDs: [linked.persistenceID, "path:/missing"],
            mountedAgentIDs: ["codex"]
        )
        let store = SkillStore()
        store.skills = [linked]

        store.refreshMountStatuses(collections: [collection])

        #expect(store.mountStatus(collectionID: collection.id, agentID: "codex") == .diverged)
        let report = try #require(store.mountReport(collectionID: collection.id, agentID: "codex"))
        #expect(report.skipped.contains {
            $0.skillID == "path:/missing" && $0.reason == ActivationService.missingLibraryMemberReason
        })
    }
}

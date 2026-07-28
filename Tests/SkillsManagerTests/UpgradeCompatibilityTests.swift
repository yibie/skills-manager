import Foundation
import SwiftData
import Testing
@testable import SkillsManager

struct UpgradeCompatibilityTests {
    private func currentSkill() -> Skill {
        let dir = URL(fileURLWithPath: "/tmp/skills/review")
        return Skill(
            id: "legacy:review",
            name: "review",
            displayName: "Review",
            baseDescription: "",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            source: .local,
            version: nil,
            filePath: dir.appendingPathComponent("SKILL.md"),
            directoryPath: dir,
            provenance: SkillProvenance(
                provider: .skillsManager,
                sourceURL: URL(string: "https://github.com/example/repo"),
                skillID: "review"
            ),
            compatibleAgents: [],
            tags: [],
            markdownContent: "",
            frontmatter: [:]
        )
    }

    @MainActor
    private func makeCurrentContext(storeURL: URL) throws -> ModelContext {
        let currentSchema = Schema([
            SkillRecord.self,
            CollectionRecord.self,
        ])
        let container = try ModelContainer(
            for: currentSchema,
            configurations: [
                ModelConfiguration("SkillsManager", schema: currentSchema, url: storeURL),
            ]
        )
        return ModelContext(container)
    }

    @Test @MainActor
    func skillRecordStoreOpensWithCurrentSchemaAndRoundTripsCollections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftdata-upgrade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("SkillsManager.sqlite")

        do {
            let oldSchema = Schema([SkillRecord.self])
            let oldContainer = try ModelContainer(
                for: oldSchema,
                configurations: [
                    ModelConfiguration("SkillsManager", schema: oldSchema, url: storeURL),
                ]
            )
            let oldContext = ModelContext(oldContainer)
            oldContext.insert(SkillRecord(skillID: "legacy:review", isStarred: true, installState: "trial"))
            try oldContext.save()
        }

        do {
            let currentContext = try makeCurrentContext(storeURL: storeURL)

            let skills = try currentContext.fetch(FetchDescriptor<SkillRecord>())
            #expect(skills.count == 1)
            #expect(skills[0].skillID == "legacy:review")
            #expect(skills[0].isStarred)
            #expect(skills[0].installState == "trial")

            let collection = CollectionRecord(
                name: "Pinned",
                memberSkillIDs: ["legacy:review"],
                mountedAgentIDs: ["codex"]
            )
            currentContext.insert(collection)
            try currentContext.save()

            let collections = try currentContext.fetch(FetchDescriptor<CollectionRecord>())
            #expect(collections.count == 1)
            #expect(collections[0].memberSkillIDs == ["legacy:review"])
            #expect(collections[0].mountedAgentIDs == ["codex"])
        }

        for _ in 0..<2 {
            let currentContext = try makeCurrentContext(storeURL: storeURL)
            let skills = try currentContext.fetch(FetchDescriptor<SkillRecord>())
            let collections = try currentContext.fetch(FetchDescriptor<CollectionRecord>())

            #expect(skills.count == 1)
            #expect(skills[0].skillID == "legacy:review")
            #expect(skills[0].isStarred)
            #expect(skills[0].installState == "trial")
            #expect(collections.count == 1)
            #expect(collections[0].memberSkillIDs == ["legacy:review"])
            #expect(collections[0].mountedAgentIDs == ["codex"])
        }

        do {
            let currentContext = try makeCurrentContext(storeURL: storeURL)
            let skill = currentSkill()

            let first = SkillRecord.recordForStarWrite(for: skill, in: currentContext)
            first.isStarred = false
            try currentContext.save()

            let second = SkillRecord.recordForStarWrite(for: skill, in: currentContext)
            second.isStarred = true
            try currentContext.save()

            let skills = try currentContext.fetch(FetchDescriptor<SkillRecord>())
            #expect(skills.count == 1)
            #expect(skills[0].skillID == skill.persistenceID)
            #expect(skills[0].isStarred)
            #expect(skills[0].installState == "trial")
        }
    }
}

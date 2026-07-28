import Foundation
import SwiftData
import Testing
@testable import SkillsManager

struct SkillIdentityTests {
    private func skill(
        id: String = "scan:review",
        name: String = "review",
        displayName: String = "Review",
        sourceURL: URL? = nil,
        provenanceSkillID: String? = nil,
        filePath: URL = URL(fileURLWithPath: "/tmp/skills/review/SKILL.md"),
        directoryPath: URL = URL(fileURLWithPath: "/tmp/skills/review")
    ) -> Skill {
        Skill(
            id: id,
            name: name,
            displayName: displayName,
            baseDescription: "",
            baseDescriptionLocale: "en",
            localizedDescription: nil,
            source: .local,
            version: nil,
            filePath: filePath,
            directoryPath: directoryPath,
            provenance: SkillProvenance(
                provider: sourceURL == nil ? .manual : .skillsManager,
                sourceURL: sourceURL,
                skillID: provenanceSkillID
            ),
            compatibleAgents: [],
            tags: [],
            markdownContent: "",
            frontmatter: [:]
        )
    }

    @Test
    func githubProvenanceUsesNormalizedSourceURLAndSkillID() {
        let first = skill(
            sourceURL: URL(string: "http://GitHub.com/OpenAI/Skills.git/?tab=readme#install"),
            provenanceSkillID: "review"
        )
        let second = skill(
            sourceURL: URL(string: "https://github.com/openai/skills"),
            provenanceSkillID: "review"
        )

        #expect(first.persistenceID == "github:openai/skills:review")
        #expect(second.persistenceID == first.persistenceID)
    }

    @Test
    func nonGitHubProvenanceFallsBackToPathIdentity() {
        let file = URL(fileURLWithPath: "/tmp/skills/review/SKILL.md")
        let current = skill(
            sourceURL: URL(string: "https://gitlab.com/openai/skills"),
            provenanceSkillID: "review",
            filePath: file,
            directoryPath: file.deletingLastPathComponent()
        )

        #expect(current.persistenceID == "path:\(file.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path)")
    }

    @Test
    func displayNameAndScanIDDoNotAffectProvenanceIdentity() {
        let sourceURL = URL(string: "https://github.com/example/repo")!
        let firstScan = skill(
            id: "scan:0",
            displayName: "First Name",
            sourceURL: sourceURL,
            provenanceSkillID: "lint"
        )
        let secondScan = skill(
            id: "scan:1",
            displayName: "Renamed",
            sourceURL: sourceURL,
            provenanceSkillID: "lint"
        )

        #expect(firstScan.persistenceID == secondScan.persistenceID)
    }

    @Test
    func manualIdentityUsesDedicatedDirectoryOrLooseFilePath() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-identity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let dedicatedDir = root.appendingPathComponent("review")
        let dedicated = skill(
            filePath: dedicatedDir.appendingPathComponent("SKILL.md"),
            directoryPath: dedicatedDir
        )
        let looseFile = root.appendingPathComponent("review.md")
        let loose = skill(
            id: "scan:loose",
            filePath: looseFile,
            directoryPath: root
        )

        #expect(dedicated.persistenceID == "path:\(dedicatedDir.resolvingSymlinksInPath().standardizedFileURL.path)")
        #expect(loose.persistenceID == "path:\(looseFile.resolvingSymlinksInPath().standardizedFileURL.path)")
        #expect(dedicated.persistenceID != loose.persistenceID)
    }

    @Test @MainActor
    func legacyRecordStillAppliesAfterStableIDChange() {
        let store = SkillStore()
        let current = skill(
            id: "legacy:review",
            sourceURL: URL(string: "https://github.com/example/repo"),
            provenanceSkillID: "review"
        )
        store.skills = [current]

        store.merge(records: [
            SkillRecord(skillID: "legacy:review", isStarred: true, installState: "trial"),
        ])

        #expect(store.skills[0].isStarred)
        #expect(store.skills[0].installState == .trial)
    }

    @Test @MainActor
    func stableRecordTakesPrecedenceOverLegacyRecord() {
        let store = SkillStore()
        let current = skill(
            id: "legacy:review",
            sourceURL: URL(string: "https://github.com/example/repo"),
            provenanceSkillID: "review"
        )
        store.skills = [current]

        store.merge(records: [
            SkillRecord(skillID: "legacy:review", isStarred: true, installState: "trial"),
            SkillRecord(skillID: current.persistenceID, isStarred: false, installState: "installed"),
        ])

        #expect(!store.skills[0].isStarred)
        #expect(store.skills[0].installState == .installed)
    }

    @Test @MainActor
    func sharedStarredNameDoesNotOverrideRecordOrAmbiguousNames() {
        let store = SkillStore()
        let first = skill(
            id: "scan:first",
            name: "commit",
            displayName: "Commit A",
            sourceURL: URL(string: "https://github.com/example/first"),
            provenanceSkillID: "commit"
        )
        let second = skill(
            id: "scan:second",
            name: "commit",
            displayName: "Commit B",
            sourceURL: URL(string: "https://github.com/example/second"),
            provenanceSkillID: "commit"
        )
        store.skills = [first, second]

        store.merge(
            records: [SkillRecord(skillID: first.persistenceID, isStarred: false, installState: "trial")],
            sharedStarredNames: ["commit"]
        )

        #expect(!store.skills[0].isStarred)
        #expect(!store.skills[1].isStarred)
        #expect(store.skills[0].installState == .trial)
    }

    @Test @MainActor
    func sharedStarredNameAppliesOnlyWhenNoRecordAndNameIsUnique() {
        let store = SkillStore()
        store.skills = [skill(name: "unique")]

        store.merge(records: [], sharedStarredNames: ["unique"])

        #expect(store.skills[0].isStarred)
    }

    @Test @MainActor
    func starWriteMigratesLegacyRecordWithoutDuplicating() throws {
        let schema = Schema([SkillRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let current = skill(
            id: "legacy:review",
            sourceURL: URL(string: "https://github.com/example/repo"),
            provenanceSkillID: "review"
        )

        context.insert(SkillRecord(skillID: "legacy:review", isStarred: false, installState: "trial"))
        try context.save()

        let record = SkillRecord.recordForStarWrite(for: current, in: context)
        record.isStarred = true
        try context.save()

        let records = try context.fetch(FetchDescriptor<SkillRecord>())
        #expect(records.count == 1)
        #expect(records[0].skillID == current.persistenceID)
        #expect(records[0].isStarred)
        #expect(records[0].installState == "trial")
    }
}

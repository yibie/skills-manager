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
}

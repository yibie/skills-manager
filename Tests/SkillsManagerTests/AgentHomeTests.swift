import Foundation
import Testing
import SkillsKernel
@testable import SkillsManager

struct AgentHomeTests {
    private func specEntry(platformID: String?, loadError: String? = nil) -> SpecCatalogEntry {
        SpecCatalogEntry(
            url: URL(fileURLWithPath: "/specs/\(platformID ?? "broken").yaml"),
            platformID: platformID,
            platformName: platformID,
            loadError: loadError
        )
    }

    private func conflict(name: String, agents: [String]) -> SkillConflict {
        SkillConflict(
            name: name,
            instances: [
                SkillConflictInstance(path: "/a/\(name)", agents: agents, contentHash: "aaaa"),
                SkillConflictInstance(path: "/b/\(name)", agents: ["Other"], contentHash: "bbbb"),
            ]
        )
    }

    @Test
    func specEntryMatchesByPlatformID() {
        let specs = [specEntry(platformID: "claude-code"), specEntry(platformID: "codex")]
        #expect(AgentHomeSupport.specEntry(forAgentID: "codex", in: specs)?.platformID == "codex")
        #expect(AgentHomeSupport.specEntry(forAgentID: "cursor", in: specs) == nil)
        #expect(AgentHomeSupport.specEntry(forAgentID: nil, in: specs) == nil)
    }

    @Test
    func specEntrySkipsUnloadableSpecs() {
        let specs = [specEntry(platformID: "claude-code", loadError: "bad yaml")]
        #expect(AgentHomeSupport.specEntry(forAgentID: "claude-code", in: specs) == nil)
    }

    @Test
    func conflictsInvolvingAgentAreFiltered() {
        let conflicts = [
            conflict(name: "commit", agents: ["Claude Code"]),
            conflict(name: "done", agents: ["Cursor"]),
        ]
        let forClaude = AgentHomeSupport.conflicts(involving: "Claude Code", from: conflicts)
        #expect(forClaude.map(\.name) == ["commit"])
        #expect(AgentHomeSupport.conflicts(involving: "Nobody", from: conflicts).isEmpty)
    }
}

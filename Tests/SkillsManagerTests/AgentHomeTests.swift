import Foundation
import Testing
@testable import SkillsManager

struct AgentHomeTests {
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

import Foundation
import Observation

/// Observable state for a single sandbox comparison slot.
/// Each slot holds one optional skill, the LLM output, and loading/error state.
@Observable
final class SandboxSlot: Identifiable {
    let id = UUID()
    var skill: Skill?
    var output: String?
    var isLoading: Bool = false
    var error: String?

    init(skill: Skill? = nil) {
        self.skill = skill
    }
}

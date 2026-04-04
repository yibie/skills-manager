import Foundation
import Observation

@Observable
final class SkillStore {
    var skills: [Skill] = []
    var isLoading = false

    func reload(adapter: any AgentAdapter) async {
        isLoading = true
        defer { isLoading = false }
        do {
            skills = try await adapter.scanSkills()
        } catch {
            // Scan failed; keep existing skills unchanged
        }
    }

    func merge(records: [SkillRecord]) {
        let lookup = Dictionary(uniqueKeysWithValues: records.map { ($0.skillID, $0) })
        for index in skills.indices {
            let id = skills[index].id
            if let record = lookup[id] {
                skills[index].isStarred = record.isStarred
                skills[index].installState = InstallState(rawValue: record.installState) ?? .notInstalled
            }
        }
    }
}

import Foundation

protocol AgentAdapter: Sendable {
    var agentName: String { get }
    var agentIcon: String { get }  // SF Symbol name
    var skillsDirectories: [URL] { get }

    func scanSkills() async throws -> [Skill]
    func installSkill(_ skill: Skill) throws
    func uninstallSkill(_ skill: Skill) throws
}

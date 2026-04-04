import Foundation
import SwiftData

// Persistent record for local metadata (stars, install state)
@Model
final class SkillRecord {
    @Attribute(.unique) var skillID: String  // derived from source + name
    var isStarred: Bool
    var installState: String  // "notInstalled", "installed", "trial"
    var installedAt: Date?
    var notes: String?

    init(skillID: String, isStarred: Bool = false, installState: String = "notInstalled") {
        self.skillID = skillID
        self.isStarred = isStarred
        self.installState = installState
    }
}

// In-memory skill representation (not persisted via SwiftData, built from file scanning)
struct Skill: Identifiable, Hashable, Sendable {
    let id: String              // unique: "{source}:{name}"
    var name: String
    var displayName: String
    var description: String
    var source: SkillSource
    var version: String?
    var filePath: URL           // primary file (SKILL.md)
    var directoryPath: URL      // skill directory
    var compatibleAgents: [String]
    var tags: [String]
    var markdownContent: String // raw SKILL.md content
    var frontmatter: [String: String] // parsed YAML frontmatter

    // Merged from SkillRecord
    var isStarred: Bool = false
    var installState: InstallState = .installed
}

enum SkillSource: Hashable, Codable, Sendable {
    case local           // user-created in ~/.claude/skills/
    case plugin(marketplace: String, pluginName: String)  // from marketplace plugin
    case symlinked       // symlinked from another location
}

enum InstallState: String, Codable, CaseIterable, Sendable {
    case notInstalled
    case installed
    case trial
}

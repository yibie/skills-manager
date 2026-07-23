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
    var baseDescription: String
    var baseDescriptionLocale: String
    var localizedDescription: String?
    var source: SkillSource
    var version: String?
    var filePath: URL           // primary file (SKILL.md)
    var directoryPath: URL      // skill directory
    /// Path to the canonical .agents/skills/<name>/ directory, if known.
    /// Nil for skills that were not installed via the universal symlink mechanism.
    var canonicalPath: URL? = nil
    var provenance: SkillProvenance = .manual
    var compatibleAgents: [String]
    var tags: [String]
    var markdownContent: String // raw SKILL.md content
    var frontmatter: [String: String] // parsed YAML frontmatter

    // Merged from SkillRecord
    var isStarred: Bool = false
    var installState: InstallState = .installed

    var description: String {
        localizedDescription ?? baseDescription
    }

    var isDescriptionTranslated: Bool {
        guard let localizedDescription else { return false }
        return localizedDescription != baseDescription
    }

    var canMoveToTrash: Bool {
        provenance.provider == .manual && canonicalPath == nil
    }

    var canUpdate: Bool {
        provenance.sourceURL != nil
    }

    var isDedicatedDirectory: Bool {
        filePath.lastPathComponent == "SKILL.md"
            && filePath.deletingLastPathComponent().standardizedFileURL
                == directoryPath.standardizedFileURL
    }

    var trashTargetURL: URL {
        isDedicatedDirectory ? directoryPath.standardizedFileURL : filePath.standardizedFileURL
    }
}

enum SkillManagementProvider: String, Codable, Hashable, Sendable {
    case skillsManager
    case skillsCLI
    case manual
    case plugin
    case openClaw

    var displayName: String {
        switch self {
        case .skillsManager: "Skills Manager"
        case .skillsCLI: "Skills CLI"
        case .manual: "External"
        case .plugin: "Plugin"
        case .openClaw: "OpenClaw"
        }
    }
}

struct SkillProvenance: Codable, Hashable, Sendable {
    var provider: SkillManagementProvider
    var sourceURL: URL?
    var skillID: String?
    var sourceRef: String? = nil

    static let manual = SkillProvenance(provider: .manual, sourceURL: nil, skillID: nil)
}

enum SkillSource: Hashable, Codable, Sendable {
    case local           // user-created in ~/.claude/skills/
    case openClaw(root: String)
    case plugin(pluginSource: String, pluginName: String)  // scanned from local plugin cache
    case symlinked       // symlinked from another location
    case projectLocal(projectURL: URL)
}

enum InstallState: String, Codable, CaseIterable, Sendable {
    case notInstalled
    case installed
    case trial
}

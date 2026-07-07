import Foundation

struct AgentDoc: Identifiable, Hashable, Sendable {
    var id: String { file }
    var file: String
    var url: URL
    var content: String
}

enum AgentDocSyncMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case inject
    case reference

    var id: String { rawValue }
}

enum AgentDocTargetState: String, Codable, Sendable {
    case inSync
    case outOfSync
    case notSynced
    case missingEntryFile

    var label: String {
        switch self {
        case .inSync: "In sync"
        case .outOfSync: "Out of sync"
        case .notSynced: "Not synced"
        case .missingEntryFile: "Missing file"
        }
    }
}

struct AgentDocTargetStatus: Identifiable, Hashable, Sendable {
    var id: String { entryFile }
    var agentIDs: [String]
    var entryFile: String
    var mode: AgentDocSyncMode
    var state: AgentDocTargetState
}

struct AgentDocsManifest: Codable, Equatable, Sendable {
    var version: Int = 1
    var docs: [Doc] = []
    var targets: [Target] = []

    struct Doc: Codable, Equatable, Sendable {
        var file: String
    }

    struct Target: Codable, Equatable, Sendable {
        var agentId: String
        var entryFile: String
        var mode: AgentDocSyncMode
        var lastSync: LastSync?
    }

    struct LastSync: Codable, Equatable, Sendable {
        var hash: String
        var syncedAt: Date
    }
}

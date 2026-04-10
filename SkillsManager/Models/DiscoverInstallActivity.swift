import Foundation

struct DiscoverInstallActivity: Identifiable, Equatable, Sendable {
    let id: String
    let skillID: String
    let skillName: String
    let targetAgents: [String]
    let command: String
    let startedAt: Date
    var finishedAt: Date?
    var status: DiscoverInstallStatus
    var log: [String]
}

enum DiscoverInstallStatus: String, Equatable, Sendable {
    case queued
    case running
    case succeeded
    case failed
}

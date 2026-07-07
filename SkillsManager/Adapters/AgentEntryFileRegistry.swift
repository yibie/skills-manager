import Foundation

struct AgentDocEntryTarget: Identifiable, Hashable, Sendable {
    var id: String { agentId }
    var agentId: String
    var displayName: String
    var entryFile: String
    var exists: Bool
}

enum AgentEntryFileRegistry {
    private static let overrides: [String: String] = [
        "claude-code": "CLAUDE.md",
        "gemini-cli": "GEMINI.md",
        "github-copilot": ".github/copilot-instructions.md",
        "iflow-cli": "IFLOW.md",
        "qwen-code": "QWEN.md",
        "augment": ".augment/guidelines.md",
    ]

    static func entryFile(for agentID: String) -> String {
        overrides[agentID] ?? "AGENTS.md"
    }

    static func supportedTargets(in projectURL: URL, fileManager: FileManager = .default) -> [AgentDocEntryTarget] {
        AgentRegistry.all
            .map { agent in
                let entryFile = entryFile(for: agent.id)
                return AgentDocEntryTarget(
                    agentId: agent.id,
                    displayName: agent.displayName,
                    entryFile: entryFile,
                    exists: fileManager.fileExists(atPath: projectURL.appendingPathComponent(entryFile).path)
                )
            }
            .sorted {
                if $0.exists != $1.exists { return $0.exists && !$1.exists }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    static func detectedTargets(in projectURL: URL, fileManager: FileManager = .default) -> [AgentDocEntryTarget] {
        supportedTargets(in: projectURL, fileManager: fileManager).filter(\.exists)
    }
}

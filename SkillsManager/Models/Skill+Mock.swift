#if DEBUG
import Foundation

extension Skill {
    static let mockSkills: [Skill] = [
        Skill(
            id: "local:commit",
            name: "commit",
            displayName: "Commit",
            description: "Create well-formatted git commits with conventional commit messages and co-author attribution.",
            source: .local,
            version: "1.2.0",
            filePath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/commit/SKILL.md"),
            directoryPath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/commit"),
            compatibleAgents: ["Claude Code"],
            tags: ["git", "workflow"],
            markdownContent: "# Commit\n\nCreates well-formatted commits.\n\n## Usage\n\nRun `/commit` to stage and commit changes.",
            frontmatter: ["version": "1.2.0"],
            isStarred: true,
            installState: .installed
        ),
        Skill(
            id: "local:done",
            name: "done",
            displayName: "Done",
            description: "Save session summary with decisions, discoveries, and next steps to a markdown file.",
            source: .local,
            version: "1.0.0",
            filePath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/done/SKILL.md"),
            directoryPath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/done"),
            compatibleAgents: ["Claude Code"],
            tags: ["workflow", "notes"],
            markdownContent: "# Done\n\nSaves session summaries.\n\n## Usage\n\nRun `/done` at end of a session.",
            frontmatter: ["version": "1.0.0"],
            isStarred: false,
            installState: .installed
        ),
        Skill(
            id: "plugin:marketplace:swiftui-expert",
            name: "swiftui-expert-skill",
            displayName: "SwiftUI Expert",
            description: "Write, review, or improve SwiftUI code for iOS/macOS with modern APIs and best practices.",
            source: .plugin(marketplace: "marketplace", pluginName: "swiftui-expert-skill"),
            version: "2.1.0",
            filePath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/swiftui-expert-skill/SKILL.md"),
            directoryPath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/swiftui-expert-skill"),
            compatibleAgents: ["Claude Code"],
            tags: ["swift", "swiftui", "ios", "macos"],
            markdownContent: "# SwiftUI Expert\n\nBuild, review, or improve SwiftUI features with correct state management and modern APIs.",
            frontmatter: ["version": "2.1.0"],
            isStarred: true,
            installState: .installed
        ),
        Skill(
            id: "plugin:marketplace:find-skills",
            name: "find-skills",
            displayName: "Find Skills",
            description: "Helps users discover and install agent skills from the marketplace.",
            source: .plugin(marketplace: "marketplace", pluginName: "find-skills"),
            version: "1.0.0",
            filePath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/find-skills/SKILL.md"),
            directoryPath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/find-skills"),
            compatibleAgents: ["Claude Code"],
            tags: ["marketplace", "discovery"],
            markdownContent: "# Find Skills\n\nDiscover and install skills from the marketplace.",
            frontmatter: ["version": "1.0.0"],
            isStarred: false,
            installState: .trial
        ),
        Skill(
            id: "local:start-phase",
            name: "start-phase",
            displayName: "Start Phase",
            description: "Start a new development phase by creating a spec file and setting context for the session.",
            source: .local,
            version: nil,
            filePath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/start-phase/SKILL.md"),
            directoryPath: URL(fileURLWithPath: "/Users/chenyibin/.claude/skills/start-phase"),
            compatibleAgents: ["Claude Code"],
            tags: ["workflow", "planning"],
            markdownContent: "# Start Phase\n\nBegin a new development phase with structured context.",
            frontmatter: [:],
            isStarred: false,
            installState: .notInstalled
        ),
    ]
}
#endif

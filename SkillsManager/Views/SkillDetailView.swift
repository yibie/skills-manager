import SwiftUI
import AppKit

struct SkillDetailView: View {
    let skill: Skill?
    var onToggleStar: () -> Void = {}
    var onPromote: (Skill) async -> Void = { _ in }

    @State private var showVersionHistory = false
    @State private var commits: [GitCommit] = []

    var body: some View {
        Group {
            if let skill {
                DetailContent(
                    skill: skill,
                    showVersionHistory: $showVersionHistory,
                    commits: $commits,
                    onToggleStar: onToggleStar,
                    // Fire-and-forget tasks: errors surface via SkillStore.errorMessage, not thrown here.
                    onPromote: { Task { await onPromote(skill) } }
                )
            } else {
                placeholder
            }
        }
        .frame(minWidth: 320)
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "Select a Skill",
            systemImage: "square.grid.2x2",
            description: Text("Choose a skill from the list to view its details.")
        )
    }
}

// MARK: - Detail content (extracted to keep body simple)

private struct DetailContent: View {
    let skill: Skill
    @Binding var showVersionHistory: Bool
    @Binding var commits: [GitCommit]
    let onToggleStar: () -> Void
    let onPromote: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metaRow
                agentTags
                Divider()
                markdownBody
            }
            .padding(20)
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showVersionHistory) {
            VersionHistoryView(commits: commits)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            Text(skill.displayName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .textSelection(.enabled)
            Spacer()
            openInEditorButton
        }
    }

    private var openInEditorButton: some View {
        Button {
            NSWorkspace.shared.open(skill.filePath)
        } label: {
            Label("Open in Editor", systemImage: "square.and.pencil")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: Meta row

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let version = skill.version {
                Text("v\(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            sourceBadge
        }
    }

    private var sourceBadge: some View {
        let label: String
        switch skill.source {
        case .local:                          label = "Local"
        case .symlinked:                      label = "Symlinked"
        case .plugin(let marketplace, _):     label = marketplace.capitalized
        case .projectLocal:                   label = "Project"
        }
        return Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Agent tags

    private var agentTags: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(skill.compatibleAgents, id: \.self) { agent in
                Text(agent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.08), in: Capsule())
            }
        }
    }

    // MARK: Markdown body

    private var markdownBody: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: skill.markdownContent,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            ) {
                Text(attributed)
                    .textSelection(.enabled)
            } else {
                Text(skill.markdownContent)
                    .textSelection(.enabled)
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                onToggleStar()
            } label: {
                Label(
                    skill.isStarred ? "Unstar" : "Star",
                    systemImage: skill.isStarred ? "star.fill" : "star"
                )
            }
            .foregroundStyle(skill.isStarred ? .yellow : .secondary)
            .help(skill.isStarred ? "Remove from starred" : "Add to starred")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showVersionHistory = true
            } label: {
                Label("Version History", systemImage: "clock.arrow.circlepath")
            }
            .help("Show version history")
        }

        // "Promote to Global" only for project-local skills
        if case .projectLocal = skill.source {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onPromote()
                } label: {
                    Label("Promote to Global", systemImage: "arrow.up.circle")
                }
                .help("Copy this skill to ~/.claude/skills/")
            }
        }
    }
}

#Preview {
    SkillDetailView(skill: Skill.mockSkills.first)
        .frame(width: 500, height: 600)
}

#Preview("Empty") {
    SkillDetailView(skill: nil)
        .frame(width: 500, height: 600)
}

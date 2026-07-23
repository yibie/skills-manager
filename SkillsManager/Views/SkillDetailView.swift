import SwiftUI
import AppKit
import MarkdownView

struct SkillDetailView: View {
    let skill: Skill?
    var isTranslatingDescription = false
    var onToggleStar: () -> Void = {}
    var onPromote: (Skill) async -> Void = { _ in }
    var onInstallToAgent: (Skill, [String]) async -> Void = { _, _ in }
    var onUpdate: (Skill) async -> Void = { _ in }
    var onTranslate: (Skill) async -> Void = { _ in }

    var body: some View {
        Group {
            if let skill {
                DetailContent(
                    skill: skill,
                    isTranslatingDescription: isTranslatingDescription,
                    onToggleStar: onToggleStar,
                    // Fire-and-forget tasks: errors surface via SkillStore.errorMessage, not thrown here.
                    onPromote: { Task { await onPromote(skill) } },
                    onInstallToAgent: { agentIDs in Task { await onInstallToAgent(skill, agentIDs) } },
                    onUpdate: { Task { await onUpdate(skill) } },
                    onTranslate: { Task { await onTranslate(skill) } }
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
    let isTranslatingDescription: Bool
    let onToggleStar: () -> Void
    let onPromote: () -> Void
    let onInstallToAgent: ([String]) -> Void
    let onUpdate: () -> Void
    let onTranslate: () -> Void

    @State private var showInstallToAgent = false

    private var renderedMarkdownContent: String {
        SkillParser.parse(content: skill.markdownContent)
            .body
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !renderedMarkdownContent.isEmpty {
                    Divider()
                    markdownBody
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showInstallToAgent) {
            InstallToAgentView(skill: skill, onInstall: onInstallToAgent)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                Text(skill.displayName)
                    .font(.title2)
                    .bold()
                    .textSelection(.enabled)

                Spacer(minLength: 12)

                metaRow
            }

            if !skill.compatibleAgents.isEmpty {
                agentInfoRow
            }

            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            actionRow
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
        FlowLayout(hSpacing: 6, vSpacing: 6) {
            if let version = skill.version {
                SkillMetaBadge(text: "v\(version)")
            }
            if skill.isDescriptionTranslated {
                SkillMetaBadge(text: "Translated", tint: .blue)
            }
            sourceBadge
            if [.skillsManager, .skillsCLI, .manual].contains(skill.provenance.provider) {
                SkillMetaBadge(text: skill.provenance.provider.displayName)
            }
        }
        .frame(maxWidth: 180, alignment: .trailing)
    }

    private var sourceBadge: some View {
        let label: String
        switch skill.source {
        case .local:                          label = "Local"
        case .openClaw:                       label = "OpenClaw"
        case .symlinked:                      label = "Symlinked"
        case .plugin(let pluginSource, _):    label = pluginSource
        case .projectLocal:                   label = "Project"
        }
        return SkillMetaBadge(text: label)
    }

    private var actionRow: some View {
        FlowLayout(hSpacing: 8, vSpacing: 8) {
            translateButton
            openInEditorButton
            starButton

            if case .projectLocal = skill.source {
                promoteButton
            }

            if skill.canUpdate {
                updateButton
            }
            installButton
        }
    }

    private var translateButton: some View {
        Button(action: onTranslate) {
            if isTranslatingDescription {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Translating")
                }
            } else {
                Label("Translate Missing", systemImage: "globe")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isTranslatingDescription || skill.baseDescription.isEmpty)
        .help("Translate this description only when the bundled translation catalog does not cover it")
    }

    private var agentInfoRow: some View {
        FlowLayout(hSpacing: 8, vSpacing: 8) {
            agentPill

            ForEach(skill.compatibleAgents, id: \.self) { agent in
                SkillMetaBadge(text: agent)
            }
        }
    }

    private var starButton: some View {
        Button {
            onToggleStar()
        } label: {
            Label(
                skill.isStarred ? "Unstar" : "Star",
                systemImage: skill.isStarred ? "star.fill" : "star"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .foregroundStyle(skill.isStarred ? .yellow : .secondary)
    }

    private var promoteButton: some View {
        Button {
            onPromote()
        } label: {
            Label("Promote to Global", systemImage: "arrow.up.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var installButton: some View {
        Button {
            showInstallToAgent = true
        } label: {
            Label("Install to Agent…", systemImage: "square.and.arrow.down.on.square")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var updateButton: some View {
        Button(action: onUpdate) {
            Label("Update", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Update using \(skill.provenance.provider.displayName)")
    }

    private var agentPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.caption)
            Text("Agents")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Markdown body

    private var markdownBody: some View {
        MarkdownView(renderedMarkdownContent)
            .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    SkillDetailView(skill: Skill.mockSkills.first)
        .frame(width: 500, height: 600)
}

#Preview("Empty") {
    SkillDetailView(skill: nil)
        .frame(width: 500, height: 600)
}
#endif

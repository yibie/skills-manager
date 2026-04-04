import SwiftUI

struct SkillListView: View {
    let skills: [Skill]
    let filter: SidebarFilter
    @Binding var selectedSkill: Skill?
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    let onTry: (Skill) -> Void

    private var filteredSkills: [Skill] {
        switch filter {
        case .discover:
            // ContentView routes .discover to DiscoverView; SkillListView is never shown for this filter
            return []
        case .all:
            return skills
        case .installed:
            return skills.filter { $0.installState == .installed }
        case .starred:
            return skills.filter { $0.isStarred }
        case .trial:
            return skills.filter { $0.installState == .trial }
        case .agent(let name):
            return skills.filter { $0.compatibleAgents.contains(name) }
        case .source(let name):
            return skills.filter { skill in
                switch skill.source {
                case .local: name.lowercased() == "local"
                case .symlinked: name.lowercased() == "symlinked"
                case .plugin(let marketplace, _): marketplace.lowercased() == name.lowercased()
                }
            }
        }
    }

    var body: some View {
        Group {
            if filteredSkills.isEmpty {
                emptyState
            } else {
                List(filteredSkills, selection: $selectedSkill) { skill in
                    SkillRow(
                        skill: skill,
                        onInstall: { Task { await onInstall(skill) } },
                        onUninstall: { Task { await onUninstall(skill) } },
                        onTry: { onTry(skill) }
                    )
                    .tag(skill)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(filter.title)
        .frame(minWidth: 260)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Skills",
            systemImage: "tray",
            description: Text("No skills match the current filter.")
        )
    }
}

// MARK: - Row

private struct SkillRow: View {
    let skill: Skill
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onTry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(skill.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                if skill.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
                InstallStateBadge(state: skill.installState)
            }

            Text(skill.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            SkillActionButtons(skill: skill, onInstall: onInstall, onUninstall: onUninstall, onTry: onTry)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Action buttons (inline, below row content)

private struct SkillActionButtons: View {
    let skill: Skill
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onTry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            switch skill.installState {
            case .notInstalled:
                ActionButton(icon: "arrow.down.circle", label: "Install", action: onInstall)
            case .installed:
                ActionButton(icon: "trash", label: "Uninstall", action: onUninstall)
            case .trial:
                ActionButton(icon: "arrow.down.circle", label: "Keep", action: onInstall)
                ActionButton(icon: "xmark.circle", label: "Discard", action: onUninstall)
            }

            ActionButton(icon: "flask", label: "Try", action: onTry)

            Menu {
                Button("Copy ID") { }
                Button("Show in Finder") { }
                Divider()
                Button("Copy Path") { }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22, height: 22)
            .help("More")
        }
        .padding(.top, 2)
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
    }
}

// MARK: - Install state badge

private struct InstallStateBadge: View {
    let state: InstallState

    var body: some View {
        switch state {
        case .installed:
            EmptyView()
        case .trial:
            Text("Trial")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.1), in: Capsule())
        case .notInstalled:
            Text("Not Installed")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.1), in: Capsule())
        }
    }
}

#Preview {
    @Previewable @State var selected: Skill? = nil
    SkillListView(
        skills: Skill.mockSkills,
        filter: .all,
        selectedSkill: $selected,
        onInstall: { _ in },
        onUninstall: { _ in },
        onTry: { _ in }
    )
    .frame(width: 300, height: 500)
}

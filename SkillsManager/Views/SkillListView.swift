import SwiftUI

struct SkillListView: View {
    let skills: [Skill]
    let filter: SidebarFilter
    @Binding var selectedSkill: Skill?

    @State private var hoveredSkillID: String?

    // Prefiltered list — avoids inline filtering in ForEach
    private var filteredSkills: [Skill] {
        switch filter {
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
                        isHovered: hoveredSkillID == skill.id
                    )
                    .tag(skill)
                    .onHover { hovering in
                        hoveredSkillID = hovering ? skill.id : nil
                    }
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
    let isHovered: Bool

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

            if isHovered {
                SkillActionBar(skill: skill)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
    }
}

// MARK: - Action bar

private struct SkillActionBar: View {
    let skill: Skill
    // In a real app these would call into a SkillService; using no-ops for now
    var body: some View {
        HStack(spacing: 6) {
            switch skill.installState {
            case .notInstalled:
                Button("Install") { }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            case .installed:
                Button("Uninstall") { }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            case .trial:
                Button("Install") { }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                Button("Remove Trial") { }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }

            Button("Try") { }
                .controlSize(.small)
                .buttonStyle(.bordered)

            Menu {
                Button("Copy ID") { }
                Button("Show in Finder") { }
                Divider()
                Button("Copy Path") { }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .frame(width: 24)
        }
        .padding(.top, 4)
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
    SkillListView(skills: Skill.mockSkills, filter: .all, selectedSkill: $selected)
        .frame(width: 300, height: 500)
}

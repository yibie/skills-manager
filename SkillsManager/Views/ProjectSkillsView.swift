import SwiftUI

struct ProjectSkillsView: View {
    let projectURL: URL?
    let skills: [Skill]
    let isLoading: Bool
    @Binding var selectedSkill: Skill?
    let onPromote: (Skill) async -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Scanning project...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if skills.isEmpty {
                emptyState
            } else {
                List(skills, selection: $selectedSkill) { skill in
                    ProjectSkillRow(
                        skill: skill,
                        onPromote: { Task { await onPromote(skill) } }
                    )
                    .tag(skill)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(projectURL.map { "Project: \($0.lastPathComponent)" } ?? "Project")
        .frame(minWidth: 260)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            projectURL == nil ? "No Project Open" : "No Skills Found",
            systemImage: projectURL == nil ? "folder" : "tray",
            description: Text(projectURL == nil
                ? "Click the folder button in the toolbar to open a project."
                : "No SKILL.md or .mdc files found in this project.")
        )
    }
}

// MARK: - Row

private struct ProjectSkillRow: View {
    let skill: Skill
    let onPromote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(skill.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(skill.filePath.pathExtension == "mdc" ? ".mdc" : "SKILL.md")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
            if !skill.description.isEmpty {
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button(action: onPromote) {
                Label("Promote to Global", systemImage: "arrow.up.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    @Previewable @State var selected: Skill? = nil
    ProjectSkillsView(
        projectURL: URL(fileURLWithPath: "/Users/user/my-project"),
        skills: [],
        isLoading: false,
        selectedSkill: $selected,
        onPromote: { _ in }
    )
    .frame(width: 300, height: 400)
}

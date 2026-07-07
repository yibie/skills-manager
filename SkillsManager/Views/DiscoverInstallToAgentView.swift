import SwiftUI

struct DiscoverInstallToAgentView: View {
    let skill: DiscoverSkill
    let onInstall: ([String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install Skill")
                        .font(.headline)
                    Text(skill.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            AgentMultiSelectList(selected: $selected)
                .frame(minHeight: 220)

            Divider()

            HStack {
                Text(selected.isEmpty ? "Select install targets" : "\(selected.count) target\(selected.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install") {
                    isInstalling = true
                    let agentIDs = Array(selected)
                    Task {
                        await onInstall(agentIDs)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || isInstalling)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 360, height: 430)
        .task {
            if selected.isEmpty, AgentRegistry.installedInstallTargets().contains(where: { $0.id == "claude-code" }) {
                selected = ["claude-code"]
            }
        }
    }
}

import SwiftUI

struct InstallToAgentView: View {
    let skill: Skill
    let onInstall: ([String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var isInstalling = false

    private var installedAgents: [AgentDefinition] {
        AgentRegistry.installedAgents()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install to Agent")
                        .font(.headline)
                    Text(skill.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if installedAgents.isEmpty {
                ContentUnavailableView(
                    "No Agents Detected",
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                    description: Text("No supported coding agents were found on this Mac.")
                )
                .frame(minHeight: 200)
            } else {
                List(installedAgents, id: \.id, selection: $selected) { agent in
                    Label(agent.displayName, systemImage: agent.icon)
                        .tag(agent.id)
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text(selected.isEmpty ? "Select agents above" : "\(selected.count) agent\(selected.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Install") {
                    isInstalling = true
                    Task {
                        await onInstall(Array(selected))
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || isInstalling)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 340, height: 420)
    }
}

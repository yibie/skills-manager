import AppKit
import SwiftUI

struct DiscoverInstallToAgentView: View {
    let skill: DiscoverSkill
    let onInstall: ([String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var isInstalling = false
    @State private var refreshToken = UUID()

    private var installedAgents: [AgentDefinition] {
        _ = refreshToken
        return AgentRegistry.installedInstallTargets()
    }

    private var importableAgents: [AgentDefinition] {
        _ = refreshToken
        return AgentRegistry.missingInstallTargets()
    }

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

            if installedAgents.isEmpty {
                importPanel
                    .frame(minHeight: 220)
            } else {
                List(selection: $selected) {
                    Section("Install Targets") {
                        ForEach(installedAgents, id: \.id) { agent in
                            Text(agent.displayName)
                                .tag(agent.id)
                        }
                    }

                    if !importableAgents.isEmpty {
                        Section("Import Folder") {
                            ForEach(importableAgents, id: \.id) { agent in
                                HStack {
                                    Text(agent.displayName)
                                    Spacer()
                                    Button("Import Folder") {
                                        importFolder(for: agent)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

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
            if selected.isEmpty, installedAgents.contains(where: { $0.id == "claude-code" }) {
                selected = ["claude-code"]
            }
        }
    }

    private var importPanel: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "No Agents Detected",
                systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                description: Text("Import a known coding agent folder to manage it here.")
            )

            if !importableAgents.isEmpty {
                Menu("Import Folder") {
                    ForEach(importableAgents, id: \.id) { agent in
                        Button(agent.displayName) {
                            importFolder(for: agent)
                        }
                    }
                }
            }
        }
    }

    private func importFolder(for agent: AgentDefinition) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose the folder used by \(agent.displayName)."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let url = panel.url else { return }
        AgentRegistry.importManagedFolder(agentID: agent.id, folderURL: url)
        selected.insert(agent.id)
        refreshToken = UUID()
    }
}

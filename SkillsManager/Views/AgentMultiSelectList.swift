import AppKit
import SwiftUI

struct AgentMultiSelectList: View {
    @Binding var selected: Set<String>
    @State private var refreshToken = UUID()

    var emptyDescription = "Import a known coding agent folder to manage it here."

    private var installedAgents: [AgentDefinition] {
        _ = refreshToken
        return AgentRegistry.installedInstallTargets()
    }

    private var importableAgents: [AgentDefinition] {
        _ = refreshToken
        return AgentRegistry.missingInstallTargets()
    }

    var body: some View {
        if installedAgents.isEmpty {
            importPanel
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
    }

    private var importPanel: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "No Agents Detected",
                systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                description: Text(emptyDescription)
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

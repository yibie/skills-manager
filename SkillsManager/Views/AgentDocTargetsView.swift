import SwiftUI

struct AgentDocTargetsView: View {
    let projectURL: URL
    let manifest: AgentDocsManifest
    let onSave: ([AgentDocsManifest.Target]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAgentIDs: Set<String>
    @State private var modesByEntryFile: [String: AgentDocSyncMode]
    @State private var isSaving = false

    private var targets: [AgentDocEntryTarget] {
        AgentEntryFileRegistry.supportedTargets(in: projectURL)
    }

    private var groupedTargets: [(entryFile: String, targets: [AgentDocEntryTarget])] {
        Dictionary(grouping: targets, by: \.entryFile)
            .map { ($0.key, $0.value.sorted { $0.displayName < $1.displayName }) }
            .sorted { lhs, rhs in
                if lhs.1.contains(where: \.exists) != rhs.1.contains(where: \.exists) {
                    return lhs.1.contains(where: \.exists)
                }
                return lhs.0 < rhs.0
            }
    }

    init(projectURL: URL, manifest: AgentDocsManifest, onSave: @escaping ([AgentDocsManifest.Target]) async -> Void) {
        self.projectURL = projectURL
        self.manifest = manifest
        self.onSave = onSave
        _selectedAgentIDs = State(initialValue: Set(manifest.targets.map(\.agentId)))
        _modesByEntryFile = State(initialValue: Dictionary(uniqueKeysWithValues: manifest.targets.map { ($0.entryFile, $0.mode) }))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            List {
                ForEach(groupedTargets, id: \.entryFile) { group in
                    Section {
                        Picker("Mode", selection: modeBinding(for: group.entryFile)) {
                            ForEach(AgentDocSyncMode.allCases) { mode in
                                Text(mode.rawValue.capitalized).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        ForEach(group.targets) { target in
                            Toggle(isOn: selectedBinding(for: target.agentId)) {
                                HStack {
                                    Text(target.displayName)
                                    Spacer()
                                    if target.exists {
                                        Text("Detected")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(group.entryFile)
                    }
                }
            }
            .listStyle(.inset)

            Divider()
            footer
        }
        .frame(width: 460, height: 560)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Doc Targets")
                    .font(.headline)
                Text(projectURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Text("\(selectedAgentIDs.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Save") {
                isSaving = true
                let targets = selectedAgentIDs.sorted().map { agentID in
                    let entryFile = AgentEntryFileRegistry.entryFile(for: agentID)
                    return AgentDocsManifest.Target(
                        agentId: agentID,
                        entryFile: entryFile,
                        mode: modesByEntryFile[entryFile, default: .inject]
                    )
                }
                Task {
                    await onSave(targets)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private func selectedBinding(for agentID: String) -> Binding<Bool> {
        Binding {
            selectedAgentIDs.contains(agentID)
        } set: { isSelected in
            if isSelected {
                selectedAgentIDs.insert(agentID)
            } else {
                selectedAgentIDs.remove(agentID)
            }
        }
    }

    private func modeBinding(for entryFile: String) -> Binding<AgentDocSyncMode> {
        Binding {
            modesByEntryFile[entryFile, default: .inject]
        } set: { mode in
            modesByEntryFile[entryFile] = mode
        }
    }
}

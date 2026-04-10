import SwiftUI

struct SkillListView: View {
    let skills: [Skill]
    let filter: SidebarFilter
    @Binding var selectedSkill: Skill?
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void

    @State private var listSelection: Set<Skill> = []
    @State private var showPluginSkills = false

    private var pluginSkills: [Skill] {
        filteredSkills.filter {
            if case .plugin = $0.source { return true }
            return false
        }
    }

    private var standaloneSkills: [Skill] {
        filteredSkills.filter {
            if case .plugin = $0.source { return false }
            return true
        }
    }

    private var filteredSkills: [Skill] {
        switch filter {
        case .discover, .project:
            return []
        case .all:
            return showPluginSkills ? skills : skills.filter {
                if case .plugin = $0.source { return false }
                return true
            }
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
                case .openClaw: name.lowercased() == "openclaw"
                case .symlinked: name.lowercased() == "symlinked"
                case .plugin(let pluginSource, _): pluginSource.lowercased() == name.lowercased()
                case .projectLocal: false
                }
            }
        }
    }

    var body: some View {
        Group {
            if filteredSkills.isEmpty {
                ContentUnavailableView(
                    "No Skills",
                    systemImage: "tray",
                    description: Text("No skills match the current filter.")
                )
            } else {
                List(selection: $listSelection) {
                    if filter == .all && !pluginSkills.isEmpty && !standaloneSkills.isEmpty {
                        Section("From Plugins") {
                            ForEach(pluginSkills) { skill in
                                SkillRow(
                                    skill: skill,
                                    onInstall: { Task { await onInstall(skill) } },
                                    onUninstall: { Task { await onUninstall(skill) } }
                                )
                                .tag(skill)
                            }
                        }
                        Section("Installed") {
                            ForEach(standaloneSkills) { skill in
                                SkillRow(
                                    skill: skill,
                                    onInstall: { Task { await onInstall(skill) } },
                                    onUninstall: { Task { await onUninstall(skill) } }
                                )
                                .tag(skill)
                            }
                        }
                    } else {
                        ForEach(filteredSkills) { skill in
                            SkillRow(
                                skill: skill,
                                onInstall: { Task { await onInstall(skill) } },
                                onUninstall: { Task { await onUninstall(skill) } }
                            )
                            .tag(skill)
                        }
                    }
                }
                .listStyle(.plain)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if listSelection.count > 1 {
                        BatchActionBar(
                            selection: listSelection,
                            onInstall: {
                                let batch = Array(listSelection)
                                listSelection = []
                                Task { await installBatch(batch) }
                            },
                            onUninstall: {
                                let batch = Array(listSelection)
                                listSelection = []
                                Task { await uninstallBatch(batch) }
                            },
                            onDeselect: { listSelection = [] }
                        )
                    }
                }
            }
        }
        .navigationTitle(filter.title)
        .frame(minWidth: 260)
        .toolbar {
            if filter == .all {
                ToolbarItem(placement: .automatic) {
                    Group {
                        if showPluginSkills {
                            Button("Plugin Skills") { showPluginSkills.toggle() }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Plugin Skills") { showPluginSkills.toggle() }
                                .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        // Sync single-selection → detail panel
        .onChange(of: listSelection) {
            selectedSkill = listSelection.count == 1 ? listSelection.first : nil
        }
        // Clear selection when filter changes
        .onChange(of: filter) {
            listSelection = []
        }
    }

    // MARK: - Batch helpers

    private func installBatch(_ batch: [Skill]) async {
        for skill in batch { await onInstall(skill) }
    }

    private func uninstallBatch(_ batch: [Skill]) async {
        for skill in batch { await onUninstall(skill) }
    }
}

// MARK: - Batch action bar

private struct BatchActionBar: View {
    let selection: Set<Skill>
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onDeselect: () -> Void

    private var hasInstallable: Bool { selection.contains { $0.installState != .installed } }
    private var hasUninstallable: Bool { selection.contains { $0.installState == .installed } }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if hasInstallable {
                Button("Install") { onInstall() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if hasUninstallable {
                Button("Uninstall") { onUninstall() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            }
            Button("Deselect") { onDeselect() }
                .buttonStyle(.plain)
                .controlSize(.small)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Row

private struct SkillRow: View {
    let skill: Skill
    let onInstall: () -> Void
    let onUninstall: () -> Void

    @State private var isHovered = false

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

            SkillActionButtons(skill: skill, onInstall: onInstall, onUninstall: onUninstall)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Action buttons

private struct SkillActionButtons: View {
    let skill: Skill
    let onInstall: () -> Void
    let onUninstall: () -> Void

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
            .menuIndicator(.hidden)
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

#if DEBUG
#Preview {
    @Previewable @State var selected: Skill? = nil
    SkillListView(
        skills: Skill.mockSkills,
        filter: .all,
        selectedSkill: $selected,
        onInstall: { _ in },
        onUninstall: { _ in }
    )
    .frame(width: 300, height: 500)
}
#endif

import SwiftUI
import AppKit

struct SkillListView: View {
    private enum AllSkillsTab: String, CaseIterable, Identifiable {
        case local
        case plugin

        var id: String { rawValue }

        var title: String {
            switch self {
            case .local: "From Local"
            case .plugin: "From Plugin"
            }
        }
    }

    let skills: [Skill]
    let filter: SidebarFilter
    var memberIDs: Set<String>? = nil  // filter == .collection 时的成员白名单;nil 视为空
    @Binding var selectedSkill: Skill?
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    let onToggleStar: (Skill) -> Void
    var onAddToCollection: ((Skill) -> Void)? = nil
    var onRemoveFromCollection: ((Skill) -> Void)? = nil

    @State private var listSelection: Set<Skill> = []
    @State private var selectedAllSkillsTab: AllSkillsTab = .local
    @State private var searchText = ""

    private var pluginSkills: [Skill] {
        skills.filter {
            if case .plugin = $0.source { return true }
            return false
        }
    }

    private var standaloneSkills: [Skill] {
        skills.filter {
            if case .plugin = $0.source { return false }
            return true
        }
    }

    private var filteredSkills: [Skill] {
        switch filter {
        case .controlCenter, .discover, .project, .agentDocs, .conflicts:
            return []
        case .all:
            return selectedAllSkillsTab == .plugin ? pluginSkills : standaloneSkills
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
        case .collection:
            return skills.filter { memberIDs?.contains($0.id) ?? false }
        }
    }

    private var searchedSkills: [Skill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filteredSkills }
        return filteredSkills.filter { skill in
            skill.name.localizedCaseInsensitiveContains(query)
                || skill.displayName.localizedCaseInsensitiveContains(query)
                || skill.description.localizedCaseInsensitiveContains(query)
                || skill.compatibleAgents.contains { $0.localizedCaseInsensitiveContains(query) }
                || skill.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        Group {
            if searchedSkills.isEmpty {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !filteredSkills.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No skills match \"\(searchText)\".")
                    )
                } else {
                    ContentUnavailableView(
                        filter == .all && selectedAllSkillsTab == .plugin ? "No Plugin Skills" : "No Skills",
                        systemImage: "tray",
                        description: Text(filter == .all && selectedAllSkillsTab == .plugin ? "No plugin-provided skills are available." : "No skills match the current filter.")
                    )
                }
            } else {
                VStack(spacing: 0) {
                    if filter == .all {
                        Picker("Skill Source", selection: $selectedAllSkillsTab) {
                            Text("From Local").tag(AllSkillsTab.local)
                            Text("From Plugin").tag(AllSkillsTab.plugin)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                    }

                    List(selection: $listSelection) {
                        ForEach(searchedSkills) { skill in
                            SkillRow(
                                skill: skill,
                                onInstall: { Task { await onInstall(skill) } },
                                onUninstall: { Task { await onUninstall(skill) } },
                                onToggleStar: { onToggleStar(skill) },
                                onAddToCollection: onAddToCollection.map { cb in { cb(skill) } },
                                onRemoveFromCollection: onRemoveFromCollection.map { cb in { cb(skill) } }
                            )
                            .listRowSeparator(.hidden)
                            .tag(skill)
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
        }
        .navigationTitle(filter.title)
        .frame(minWidth: 260)
        .searchable(text: $searchText, prompt: "Search skills")
        // Sync single-selection → detail panel
        .onChange(of: listSelection) {
            selectedSkill = listSelection.count == 1 ? listSelection.first : nil
        }
        // Clear selection when filter changes
        .onChange(of: filter) {
            listSelection = []
            if filter != .all {
                selectedAllSkillsTab = .local
            }
        }
        .onChange(of: selectedAllSkillsTab) {
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
    let onToggleStar: () -> Void
    var onAddToCollection: (() -> Void)? = nil
    var onRemoveFromCollection: (() -> Void)? = nil

    var body: some View {
        SkillCard(
            title: skill.displayName,
            description: skill.description
        ) {
            if skill.isDescriptionTranslated {
                SkillMetaBadge(text: "Translated", tint: .blue)
            }
            sourceTypeBadge
            sourceDetailBadge
            installStateBadge
        } actions: {
            SkillActionButtons(
                skill: skill,
                onInstall: onInstall,
                onUninstall: onUninstall,
                onToggleStar: onToggleStar
            )
        }
        .contextMenu {
            Button(skill.isStarred ? "Unstar" : "Star") { onToggleStar() }
            if let onAddToCollection {
                Button("Add to Collection…", action: onAddToCollection)
            }
            if let onRemoveFromCollection {
                Button("Remove from Collection", role: .destructive, action: onRemoveFromCollection)
            }
            Divider()
            switch skill.installState {
            case .notInstalled:
                Button("Install") { onInstall() }
            case .installed:
                Button("Uninstall", role: .destructive) { onUninstall() }
            case .trial:
                Button("Keep") { onInstall() }
                Button("Discard", role: .destructive) { onUninstall() }
            }
            Divider()
            Button("Copy ID") { copyToPasteboard(skill.id) }
            Button("Show in Finder") { showSkillInFinder(skill) }
            Button("Copy Path") { copyToPasteboard(skill.directoryPath.path()) }
        }
    }

    private var sourceTypeBadge: some View {
        let label: String
        let tint: Color
        switch skill.source {
        case .local:
            label = "Local"
            tint = .secondary
        case .openClaw:
            label = "OpenClaw"
            tint = .blue
        case .symlinked:
            label = "Symlinked"
            tint = .secondary
        case .plugin:
            label = "Plugin"
            tint = .purple
        case .projectLocal:
            label = "Project"
            tint = .secondary
        }
        return SkillMetaBadge(text: label, tint: tint)
    }

    @ViewBuilder
    private var sourceDetailBadge: some View {
        switch skill.source {
        case .plugin(let pluginSource, let pluginName):
            SkillMetaBadge(text: pluginSource)
            SkillMetaBadge(text: pluginName)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var installStateBadge: some View {
        switch skill.installState {
        case .installed:
            EmptyView()
        case .trial:
            SkillMetaBadge(text: "Trial", tint: .orange)
        case .notInstalled:
            SkillMetaBadge(text: "Not Installed")
        }
    }
}

// MARK: - Action buttons

private struct SkillActionButtons: View {
    let skill: Skill
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleStar) {
                Image(systemName: skill.isStarred ? "star.fill" : "star")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(skill.isStarred ? .yellow : .secondary)
            .help(skill.isStarred ? "Unstar" : "Star")

            switch skill.installState {
            case .notInstalled:
                TextActionButton(label: "Install", action: onInstall)
            case .installed:
                TextActionButton(label: "Uninstall", role: .destructive, action: onUninstall)
            case .trial:
                TextActionButton(label: "Keep", action: onInstall)
                TextActionButton(label: "Discard", role: .destructive, action: onUninstall)
            }

            Menu {
                Button("Copy ID") { copyToPasteboard(skill.id) }
                Button("Show in Finder") { showSkillInFinder(skill) }
                Divider()
                Button("Copy Path") { copyToPasteboard(skill.directoryPath.path()) }
            } label: {
                Text("More")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("More")
        }
        .padding(.top, 2)
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

private func showSkillInFinder(_ skill: Skill) {
    NSWorkspace.shared.activateFileViewerSelecting([skill.directoryPath])
}

private struct TextActionButton: View {
    let label: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(label)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
        onUninstall: { _ in },
        onToggleStar: { _ in }
    )
    .frame(width: 300, height: 500)
}
#endif

import SwiftUI
import AppKit

struct SkillListView: View {
    let skills: [Skill]
    let filter: SidebarFilter
    var memberIDs: Set<String>? = nil  // filter == .collection 时的成员白名单;nil 视为空
    @Binding var selectedSkill: Skill?
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    var onMoveToTrash: (Skill) async -> Void = { _ in }
    let onToggleStar: (Skill) -> Void
    var onAddToCollection: ((Skill) -> Void)? = nil
    var onRemoveFromCollection: ((Skill) -> Void)? = nil

    @State private var listSelection: Set<Skill> = []
    @State private var searchQuery = SkillSearchQuery()

    private var scopedSkills: [Skill] {
        switch filter {
        case .controlCenter, .discover, .project, .agentDocs, .conflicts:
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

    private var visibleSkills: [Skill] {
        SkillSearch.results(in: scopedSkills, query: searchQuery)
    }

    private var sourceOptions: [String] {
        Set(scopedSkills.map(SkillSearch.sourceName(for:))).sorted()
    }

    private var agentOptions: [String] {
        Set(scopedSkills.flatMap(\.compatibleAgents)).sorted()
    }

    private var batchRemovableSkills: [Skill] {
        listSelection.filter { skill in
            skill.installState == InstallState.installed && !skill.canMoveToTrash
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SkillFilterBar(
                query: $searchQuery,
                resultCount: visibleSkills.count,
                totalCount: scopedSkills.count,
                sources: sourceOptions,
                agents: agentOptions
            )

            Divider()

            if visibleSkills.isEmpty {
                if scopedSkills.isEmpty {
                    ContentUnavailableView(
                        "No Skills",
                        systemImage: "tray",
                        description: Text("There are no skills in this view yet.")
                    )
                } else {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No skills match the current search and filters.")
                    } actions: {
                        Button("Clear Search and Filters") {
                            searchQuery = SkillSearchQuery()
                        }
                    }
                }
            } else {
                List(selection: $listSelection) {
                    ForEach(visibleSkills) { skill in
                        row(for: skill)
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
                                let batch = batchRemovableSkills
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
        .searchable(text: $searchQuery.text, prompt: "Search names, descriptions, tags, agents")
        // Sync single-selection → detail panel
        .onChange(of: listSelection) {
            selectedSkill = listSelection.count == 1 ? listSelection.first : nil
        }
        // Clear selection when filter changes
        .onChange(of: filter) {
            listSelection = []
            searchQuery.clearFilters()
        }
        .onChange(of: visibleSkills.map(\.id)) {
            let visibleIDs = Set(visibleSkills.map(\.id))
            listSelection = listSelection.filter { visibleIDs.contains($0.id) }
        }
    }

    // MARK: - Batch helpers

    private func row(for skill: Skill) -> some View {
        SkillRow(
            skill: skill,
            onInstall: { Task { await onInstall(skill) } },
            onUninstall: { Task { await onUninstall(skill) } },
            onMoveToTrash: { Task { await onMoveToTrash(skill) } },
            onToggleStar: { onToggleStar(skill) },
            onAddToCollection: onAddToCollection.map { callback in
                { callback(skill) }
            },
            onRemoveFromCollection: onRemoveFromCollection.map { callback in
                { callback(skill) }
            }
        )
        .tag(skill)
    }

    private func installBatch(_ batch: [Skill]) async {
        for skill in batch { await onInstall(skill) }
    }

    private func uninstallBatch(_ batch: [Skill]) async {
        for skill in batch { await onUninstall(skill) }
    }
}

// MARK: - Search and filters

private struct SkillFilterBar: View {
    @Binding var query: SkillSearchQuery
    let resultCount: Int
    let totalCount: Int
    let sources: [String]
    let agents: [String]

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Status", selection: $query.installState) {
                    Text("Any Status").tag(nil as InstallState?)
                    ForEach(InstallState.allCases, id: \.rawValue) { state in
                        Text(state.filterTitle).tag(state as InstallState?)
                    }
                }

                Picker("Source", selection: $query.source) {
                    Text("Any Source").tag(nil as String?)
                    ForEach(sources, id: \.self) { source in
                        Text(source).tag(source as String?)
                    }
                }

                Picker("Agent", selection: $query.agent) {
                    Text("Any Agent").tag(nil as String?)
                    ForEach(agents, id: \.self) { agent in
                        Text(agent).tag(agent as String?)
                    }
                }

                Divider()
                Toggle("Starred Only", isOn: $query.starredOnly)

                if query.activeFilterCount > 0 {
                    Divider()
                    Button("Clear Filters") { query.clearFilters() }
                }
            } label: {
                Label(
                    query.activeFilterCount == 0 ? "Filter" : "Filters (\(query.activeFilterCount))",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Filter by status, source, agent, or starred state")

            Text(resultCount == totalCount ? "\(totalCount) skills" : "\(resultCount) of \(totalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer(minLength: 8)

            if query.activeFilterCount > 0 {
                Button("Clear") { query.clearFilters() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension InstallState {
    var filterTitle: String {
        switch self {
        case .installed: "Installed"
        case .trial: "Trial"
        case .notInstalled: "Not Installed"
        }
    }
}

// MARK: - Batch action bar

private struct BatchActionBar: View {
    let selection: Set<Skill>
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onDeselect: () -> Void
    @State private var isConfirmingRemoval = false

    private var hasInstallable: Bool { selection.contains { $0.installState != .installed } }
    private var removableCount: Int {
        selection.count { $0.installState == .installed && !$0.canMoveToTrash }
    }

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
            if removableCount > 0 {
                Button("Delete \(removableCount)…") { isConfirmingRemoval = true }
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
        .alert("Delete \(removableCount) Skills from Library?", isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onUninstall)
        } message: {
            Text("Each skill will be deleted through its detected lifecycle provider. External files that require separate Trash confirmation are excluded.")
        }
    }
}

// MARK: - Row

private struct SkillRow: View {
    let skill: Skill
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onMoveToTrash: () -> Void
    let onToggleStar: () -> Void
    var onAddToCollection: (() -> Void)? = nil
    var onRemoveFromCollection: (() -> Void)? = nil
    @State private var isConfirmingTrash = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(skill.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if skill.isDescriptionTranslated {
                        Image(systemName: "globe")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Translated description")
                    }
                }

                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Text(SkillSearch.sourceName(for: skill))
                    Text("·")
                    Label(skill.installState.filterTitle, systemImage: installStateIcon)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: onToggleStar) {
                Image(systemName: skill.isStarred ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
            .foregroundStyle(skill.isStarred ? .yellow : .secondary)
            .accessibilityLabel(skill.isStarred ? "Unstar \(skill.displayName)" : "Star \(skill.displayName)")
            .help(skill.isStarred ? "Unstar" : "Star")

            Menu {
                actionMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More actions for \(skill.displayName)")
            .help("More actions")
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
        .contextMenu {
            actionMenuItems
        }
        .alert("Move “\(skill.displayName)” to Trash?", isPresented: $isConfirmingTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive, action: onMoveToTrash)
        } message: {
            Text("This moves \(skill.trashTargetURL.path) to Trash. Links to this skill from other agents may stop working.")
        }
        .alert(removalConfirmationTitle, isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button(removalTitle, role: .destructive, action: onUninstall)
        } message: {
            Text(removalConfirmationMessage)
        }
    }

    @ViewBuilder
    private var actionMenuItems: some View {
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
            removalAction
        case .trial:
            Button("Keep") { onInstall() }
            removalAction
        }
        Divider()
        Button("Copy ID") { copyToPasteboard(skill.id) }
        Button("Show in Finder") { showSkillInFinder(skill) }
        Button("Copy Path") { copyToPasteboard(skill.directoryPath.standardizedFileURL.path) }
    }

    @ViewBuilder
    private var removalAction: some View {
        if skill.canMoveToTrash {
            Button("Move to Trash…", role: .destructive) {
                isConfirmingTrash = true
            }
        } else {
            Button("\(removalTitle)…", role: .destructive) {
                isConfirmingRemoval = true
            }
        }
    }

    private var removalTitle: String {
        if skill.installState == .trial { return "Discard" }
        return switch skill.provenance.provider {
        case .skillsCLI: "Remove via Skills CLI"
        case .skillsManager: "Delete from Library"
        case .manual: "Uninstall"
        case .plugin: "Move Plugin Cache to Trash"
        case .openClaw: "Move OpenClaw Skill to Trash"
        }
    }

    private var removalConfirmationTitle: String {
        "\(removalTitle) “\(skill.displayName)”?"
    }

    private var removalConfirmationMessage: String {
        switch skill.provenance.provider {
        case .skillsCLI:
            "Skills Manager will ask Skills CLI to remove this skill, then rescan every agent location."
        case .skillsManager:
            "This permanently deletes the canonical Library copy and removes its managed links from agents. Collection unmounting does not delete the Library copy."
        case .manual:
            "This removes the current installation."
        case .plugin:
            "This moves the cached plugin skill to Trash. Reinstalling or refreshing the plugin may restore it."
        case .openClaw:
            "This moves the OpenClaw skill from its current location to Trash."
        }
    }

    private var installStateIcon: String {
        switch skill.installState {
        case .installed: "checkmark.circle"
        case .trial: "clock"
        case .notInstalled: "circle.dashed"
        }
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

private func showSkillInFinder(_ skill: Skill) {
    NSWorkspace.shared.activateFileViewerSelecting([skill.directoryPath.standardizedFileURL])
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
        onMoveToTrash: { _ in },
        onToggleStar: { _ in }
    )
    .frame(width: 300, height: 500)
}
#endif

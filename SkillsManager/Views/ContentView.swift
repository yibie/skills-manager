import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var skillRecords: [SkillRecord]

    @State private var store = SkillStore()
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedSkill: Skill? = nil
    @State private var sandboxInitialSkill: Skill? = nil
    @State private var sandboxPreviewSkills: [Skill] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isProjectPickerPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedFilter: $selectedFilter, skills: store.skills, discoverableCount: store.discoverablePlugins.count, projectSkillCount: store.projectSkills.count, currentProjectURL: store.currentProjectURL)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } content: {
            if selectedFilter == .discover {
                DiscoverView(
                    plugins: store.discoverablePlugins,
                    isLoading: store.isLoadingPlugins,
                    isSyncing: store.isSyncing,
                    onInstall: { plugin in await store.install(plugin: plugin) },
                    onUninstall: { plugin in await store.uninstall(plugin: plugin) },
                    onRefresh: { await store.syncAndReloadPlugins() },
                    onTrySandbox: { plugin in
                        if plugin.isInstalled {
                            // Already installed — use existing skills, match by marketplace + name
                            sandboxPreviewSkills = []
                            sandboxInitialSkill = store.skills.first {
                                if case .plugin(let m, let name) = $0.source {
                                    return m == plugin.marketplace && name == plugin.name
                                }
                                return false
                            }
                        } else {
                            // Not installed — preview all skills without installing
                            let previews = await store.previewPluginSkills(plugin)
                            sandboxPreviewSkills = previews
                            sandboxInitialSkill = previews.first
                        }
                    }
                )
            } else if selectedFilter == .project {
                ProjectSkillsView(
                    projectURL: store.currentProjectURL,
                    skills: store.projectSkills,
                    isLoading: store.isLoadingProject,
                    selectedSkill: $selectedSkill,
                    onPromote: { skill in await store.promoteSkill(skill) }
                )
            } else {
                SkillListView(
                    skills: store.skills,
                    filter: selectedFilter,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) }
                )
            }
        } detail: {
            if selectedFilter == .discover, sandboxInitialSkill != nil {
                SandboxView(
                    initialSkill: sandboxInitialSkill,
                    availableSkills: store.skills + sandboxPreviewSkills,
                    onKeep: { skill in
                        // Preview skills (id starts with "preview:") need real plugin installation
                        if skill.id.hasPrefix("preview:"),
                           case .plugin(let marketplace, let pluginName) = skill.source,
                           let plugin = store.discoverablePlugins.first(where: {
                               $0.marketplace == marketplace && $0.name == pluginName
                           }) {
                            await store.install(plugin: plugin)
                        } else {
                            await store.installSkill(skill)
                        }
                    },
                    onDismiss: {
                        sandboxInitialSkill = nil
                        sandboxPreviewSkills = []
                    }
                )
            } else {
                SkillDetailView(
                    skill: selectedSkill,
                    onToggleStar: {
                        guard let skill = selectedSkill else { return }
                        let skillID = skill.id
                        let descriptor = FetchDescriptor<SkillRecord>(
                            predicate: #Predicate { $0.skillID == skillID }
                        )
                        if let record = try? modelContext.fetch(descriptor).first {
                            record.isStarred.toggle()
                        } else {
                            let record = SkillRecord(skillID: skillID, isStarred: true, installState: skill.installState.rawValue)
                            modelContext.insert(record)
                        }
                    },
                    onPromote: { skill in await store.promoteSkill(skill) },
                    onInstallToAgent: { skill, agentIDs in
                        await store.installSkillToAgents(skill, agentIDs: agentIDs)
                    }
                )
            }
        }
        .onChange(of: selectedFilter) {
            selectedSkill = nil
            sandboxInitialSkill = nil
            sandboxPreviewSkills = []
        }
        .fileImporter(
            isPresented: $isProjectPickerPresented,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                Task { await store.openProject(url: url) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    isProjectPickerPresented = true
                } label: {
                    Label("Open Project", systemImage: "folder.badge.plus")
                }
                .help("Open a project folder to scan for local skills")
            }
        }
        .task {
            async let skills: Void = store.reloadSkills()
            async let plugins: Void = store.reloadDiscoverablePlugins()
            _ = await (skills, plugins)
            store.merge(records: skillRecords)
        }
        .onChange(of: skillRecords) {
            store.merge(records: skillRecords)
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SkillRecord.self, inMemory: true)
        .frame(width: 1100, height: 700)
}

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var skillRecords: [SkillRecord]

    @State private var store = SkillStore()
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedSkill: Skill? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sandboxSkill: Skill? = nil

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedFilter: $selectedFilter, skills: store.skills, discoverableCount: store.discoverablePlugins.count)
        } content: {
            if selectedFilter == .discover {
                DiscoverView(
                    plugins: store.discoverablePlugins,
                    isLoading: store.isLoadingPlugins,
                    isSyncing: store.isSyncing,
                    onInstall: { plugin in await store.install(plugin: plugin) },
                    onUninstall: { plugin in await store.uninstall(plugin: plugin) },
                    onRefresh: { await store.syncAndReloadPlugins() }
                )
            } else {
                SkillListView(
                    skills: store.skills,
                    filter: selectedFilter,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onTry: { skill in sandboxSkill = skill }
                )
            }
        } detail: {
            SkillDetailView(skill: selectedSkill) {
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
            }
        }
        .sheet(item: $sandboxSkill) { skill in
            SandboxView(
                initialSkill: skill,
                availableSkills: store.skills,
                onKeep: { skill in await store.installSkill(skill) }
            )
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

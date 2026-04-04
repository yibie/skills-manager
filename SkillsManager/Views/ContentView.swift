import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var skillRecords: [SkillRecord]

    @State private var store = SkillStore()
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedSkill: Skill? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedFilter: $selectedFilter, skills: store.skills)
        } content: {
            if selectedFilter == .discover {
                DiscoverView(
                    plugins: store.discoverablePlugins,
                    isLoading: store.isLoadingPlugins,
                    onInstall: { plugin in await store.install(plugin: plugin) },
                    onUninstall: { plugin in await store.uninstall(plugin: plugin) }
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
            SkillDetailView(skill: selectedSkill)
        }
        .task {
            await store.reloadSkills()
            await store.reloadDiscoverablePlugins()
            store.merge(records: skillRecords)
        }
        .onChange(of: skillRecords) {
            store.merge(records: skillRecords)
        }
        .alert("Error", isPresented: .constant(store.errorMessage != nil)) {
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

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query private var skillRecords: [SkillRecord]
    @AppStorage(AppSettings.descriptionLanguageModeKey) private var descriptionLanguageMode = DescriptionLanguageMode.system.rawValue
    @AppStorage(AppSettings.manualDescriptionLocaleKey) private var manualDescriptionLocale = ""

    @State private var store = SkillStore()
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedSkill: Skill? = nil
    @State private var selectedAgentDoc: AgentDoc? = nil
    @State private var selectedDiscoverSkillID: String? = nil
    @State private var pendingDiscoverTrySkill: DiscoverSkill? = nil
    @State private var pendingDiscoverInstallSkill: DiscoverSkill? = nil
    @State private var isNewAgentDocPresented = false
    @State private var isAgentDocTargetsPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isProjectPickerPresented = false

    private var resolvedDiscoverSkills: [DiscoverSkill] {
        store.discoverableSkills.map { store.discoverableSkillDetails[$0.id] ?? $0 }
    }

    private var resolvedDiscoverSearchResults: [DiscoverSkill] {
        store.discoverSearchResults.map { store.discoverableSkillDetails[$0.id] ?? $0 }
    }

    private var selectedDiscoverSkill: DiscoverSkill? {
        guard let selectedDiscoverSkillID else { return nil }
        if let detail = store.discoverableSkillDetails[selectedDiscoverSkillID] {
            return detail
        }
        return (resolvedDiscoverSkills + resolvedDiscoverSearchResults)
            .first { $0.id == selectedDiscoverSkillID }
    }

    private var currentSelectedSkill: Skill? {
        guard let selectedSkill else { return nil }
        switch selectedFilter {
        case .project:
            return store.projectSkills.first { $0.id == selectedSkill.id } ?? selectedSkill
        case .discover, .agentDocs:
            return selectedSkill
        case .all, .installed, .starred, .trial, .agent, .source:
            return store.skills.first { $0.id == selectedSkill.id } ?? selectedSkill
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedFilter: $selectedFilter,
                skills: store.skills,
                discoverableCount: store.discoverableSkillTotal,
                projectSkillCount: store.projectSkills.count,
                agentDocCount: store.agentDocs.count,
                currentProjectURL: store.currentProjectURL
            )
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } content: {
            if selectedFilter == .discover {
                DiscoverView(
                    category: store.discoverCategory,
                    skills: resolvedDiscoverSkills,
                    totalCount: store.discoverableSkillTotal,
                    installedSkills: store.skills,
                    isLoading: store.isLoadingDiscover,
                    isSyncing: store.isSyncing,
                    installingSkillIDs: Set(store.discoverInstallActivities.compactMap { $0.status == .running ? $0.skillID : nil }),
                    selectedSkillID: $selectedDiscoverSkillID,
                    onSelectCategory: { category in await store.setDiscoverCategory(category) },
                    onSearch: { query in try await store.searchDiscoverableSkillsDirectory(query: query) },
                    onLoadDetail: { entry in await store.loadDiscoverSkillDetail(entry) },
                    onTry: { entry in
                        await store.loadDiscoverSkillDetail(entry)
                        pendingDiscoverTrySkill = store.discoverableSkillDetails[entry.id] ?? entry
                    },
                    onInstall: { entry in pendingDiscoverInstallSkill = entry },
                    onUninstall: { entry in await store.uninstallDiscoverSkill(entry) },
                    onRefresh: { await store.refreshDiscoverableSkillsDirectory() },
                    onTranslateLoaded: { await store.translateDescriptions(using: locale, scope: .loadedDiscoverDetails) }
                )
            } else if selectedFilter == .project {
                ProjectSkillsView(
                    projectURL: store.currentProjectURL,
                    skills: store.projectSkills,
                    isLoading: store.isLoadingProject,
                    selectedSkill: $selectedSkill,
                    onPromote: { skill in await store.promoteSkill(skill) }
                )
            } else if selectedFilter == .agentDocs {
                AgentDocsView(
                    projectURL: store.currentProjectURL,
                    docs: store.agentDocs,
                    statuses: store.agentDocsStatus,
                    isLoading: store.isLoadingAgentDocs,
                    isSyncing: store.isSyncingAgentDocs,
                    selectedDoc: $selectedAgentDoc,
                    onRefresh: { await store.loadAgentDocs() },
                    onSync: { await store.syncAgentDocs() },
                    onNew: { isNewAgentDocPresented = true },
                    onTargets: { isAgentDocTargetsPresented = true },
                    onOpen: { doc in store.openDocInEditor(doc) }
                )
            } else {
                SkillListView(
                    skills: store.skills,
                    filter: selectedFilter,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onToggleStar: { skill in toggleStar(for: skill) }
                )
            }
        } detail: {
            if selectedFilter == .discover {
                DiscoverDetailView(
                    entry: selectedDiscoverSkill,
                    isInstalled: selectedDiscoverSkill.map { entry in
                        store.skills.contains { $0.name == entry.skillId || $0.name == entry.name }
                    } ?? false,
                    isInstalling: selectedDiscoverSkill.map { store.isInstallingDiscoverSkill($0) } ?? false,
                    installActivities: store.orderedDiscoverInstallActivities(prioritizing: selectedDiscoverSkillID),
                    isTranslatingDescriptions: store.isTranslatingDescriptions,
                    onLoadDetail: { entry in await store.loadDiscoverSkillDetail(entry) },
                    onTry: { entry in
                        await store.loadDiscoverSkillDetail(entry)
                        pendingDiscoverTrySkill = store.discoverableSkillDetails[entry.id] ?? entry
                    },
                    onInstall: { entry in pendingDiscoverInstallSkill = entry },
                    onUninstall: { entry in await store.uninstallDiscoverSkill(entry) },
                    onTranslate: { entry in await store.translateDescriptions(using: locale, scope: .discoverSkill(id: entry.id)) }
                )
            } else if selectedFilter == .agentDocs {
                AgentDocDetailView(doc: selectedAgentDoc)
            } else {
                SkillDetailView(
                    skill: currentSelectedSkill,
                    isTranslatingDescription: store.isTranslatingDescriptions,
                    onToggleStar: {
                        guard let skill = currentSelectedSkill else { return }
                        toggleStar(for: skill)
                    },
                    onPromote: { skill in await store.promoteSkill(skill) },
                    onInstallToAgent: { skill, agentIDs in
                        await store.installSkillToAgents(skill, agentIDs: agentIDs)
                    },
                    onTranslate: { skill in
                        let scope: DescriptionTranslationScope
                        if case .projectLocal = skill.source {
                            scope = .projectSkill(id: skill.id)
                        } else {
                            scope = .skill(id: skill.id)
                        }
                        await store.translateDescriptions(using: locale, scope: scope)
                    }
                )
            }
        }
        .onChange(of: selectedFilter) {
            selectedSkill = nil
            selectedAgentDoc = nil
            selectedDiscoverSkillID = nil
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

            ToolbarItem(placement: .automatic) {
                if let summary = store.lastTranslationSummary {
                    Text(summary.toolbarText)
                        .font(.caption)
                        .foregroundStyle(summary.failed > 0 ? .orange : .secondary)
                        .help(summary.helpText)
                }
            }
        }
        .sheet(item: $pendingDiscoverInstallSkill) { skill in
            DiscoverInstallToAgentView(skill: skill) { agentIDs in
                await store.installDiscoverSkill(skill, agentIDs: agentIDs)
            }
        }
        .sheet(item: $pendingDiscoverTrySkill) { skill in
            DiscoverTryView(skill: skill) {
                pendingDiscoverTrySkill = nil
                pendingDiscoverInstallSkill = skill
            }
        }
        .sheet(isPresented: $isNewAgentDocPresented) {
            NewAgentDocView { fileName, content in
                await store.createAgentDoc(fileName: fileName, content: content)
            }
        }
        .sheet(isPresented: $isAgentDocTargetsPresented) {
            if let projectURL = store.currentProjectURL {
                AgentDocTargetsView(projectURL: projectURL, manifest: store.agentDocsManifest) { targets in
                    await store.setAgentDocTargets(targets)
                }
            }
        }
        .task {
            async let skills: Void = store.reloadSkills()
            async let discover: Void = store.reloadDiscoverableSkillsDirectory()
            _ = await (skills, discover)
            store.merge(records: skillRecords)
            store.startDiscoverDirectoryRefreshLoop()
            store.startWatchingSkillDirectories()
        }
        .onChange(of: skillRecords) {
            store.merge(records: skillRecords)
        }
        .onChange(of: descriptionLanguageMode) {
            Task {
                await store.refreshLocalizedDescriptions(using: locale)
                store.startDiscoverHomeTranslationPrewarm(using: locale)
            }
        }
        .onChange(of: manualDescriptionLocale) {
            Task {
                await store.refreshLocalizedDescriptions(using: locale)
                store.startDiscoverHomeTranslationPrewarm(using: locale)
            }
        }
        .onChange(of: locale.identifier) {
            Task {
                await store.refreshLocalizedDescriptions(using: locale)
                store.startDiscoverHomeTranslationPrewarm(using: locale)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .focusedSceneValue(\.skillCommandActions, SkillCommandActions(
            refresh: { Task { await store.reloadSkills() } },
            toggleStar: currentSelectedSkill.map { skill in { toggleStar(for: skill) } },
            isStarred: currentSelectedSkill?.isStarred ?? false
        ))
    }

    /// Toggles a skill's star in both SwiftData and the state file shared with the TUI.
    private func toggleStar(for skill: Skill) {
        let newValue = !skill.isStarred
        let skillID = skill.id
        let descriptor = FetchDescriptor<SkillRecord>(
            predicate: #Predicate { $0.skillID == skillID }
        )
        if let record = try? modelContext.fetch(descriptor).first {
            record.isStarred = newValue
        } else {
            let record = SkillRecord(skillID: skillID, isStarred: newValue, installState: skill.installState.rawValue)
            modelContext.insert(record)
        }
        store.setSkillStarred(skill, isStarred: newValue)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SkillRecord.self, inMemory: true)
        .frame(width: 1100, height: 700)
}

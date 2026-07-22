import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query private var skillRecords: [SkillRecord]
    @Query(sort: \CollectionRecord.sortOrder) private var collectionRecords: [CollectionRecord]
    @AppStorage(AppSettings.descriptionLanguageModeKey) private var descriptionLanguageMode = DescriptionLanguageMode.system.rawValue
    @AppStorage(AppSettings.manualDescriptionLocaleKey) private var manualDescriptionLocale = ""

    @State private var store = SkillStore()
    @State private var selectedFilter: SidebarFilter = .controlCenter
    @State private var selectedSkill: Skill? = nil
    @State private var selectedAgentDoc: AgentDoc? = nil
    @State private var selectedConflict: SkillConflict? = nil
    @State private var selectedDiscoverSkillID: String? = nil
    @State private var pendingDiscoverTrySkill: DiscoverSkill? = nil
    @State private var pendingDiscoverInstallSkill: DiscoverSkill? = nil
    @State private var pendingCollectionSkill: Skill? = nil
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
        case .discover, .agentDocs, .conflicts, .controlCenter:
            return selectedSkill
        case .all, .installed, .starred, .trial, .agent, .source, .collection:
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
                conflictCount: store.conflicts.count,
                currentProjectURL: store.currentProjectURL
            )
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } content: {
            if selectedFilter == .controlCenter {
                ControlCenterView(
                    collections: collectionRecords,
                    skills: store.skills,
                    detectedAgents: AgentRegistry.installedAgents(),
                    statusFor: { store.mountStatus(collectionID: $0.id, agentID: $1) },
                    onOpen: { selectedFilter = .collection($0.id, name: $0.name) },
                    onCreate: { name in createCollection(name: name) },
                    onToggleAgent: { collection, agentID, mount in
                        setMounted(collection: collection, agentID: agentID, mount: mount)
                    },
                    onReapply: { collection, agentID in
                        setMounted(collection: collection, agentID: agentID, mount: true)
                    },
                    onRename: { collection, name in
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { collection.name = trimmed }
                    },
                    onDelete: { collection in
                        modelContext.delete(collection)
                        store.refreshMountStatuses(collections: collectionRecords)
                    }
                )
            } else if selectedFilter == .discover {
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
            } else if selectedFilter == .conflicts {
                ConflictsView(
                    conflicts: store.conflicts,
                    selectedConflict: $selectedConflict
                )
            } else if case .collection(let id, _) = selectedFilter,
                      let collection = collectionRecords.first(where: { $0.id == id }) {
                CollectionDetailView(
                    collection: collection,
                    skills: store.skills,
                    detectedAgents: AgentRegistry.installedAgents(),
                    statusFor: { store.mountStatus(collectionID: id, agentID: $0) },
                    selectedSkill: $selectedSkill,
                    onToggleAgent: { agentID, mount in
                        setMounted(collection: collection, agentID: agentID, mount: mount)
                    },
                    onReapply: { agentID in
                        setMounted(collection: collection, agentID: agentID, mount: true)
                    },
                    onAddMembers: { ids in
                        collection.memberSkillIDs.append(contentsOf: ids.filter { !collection.memberSkillIDs.contains($0) })
                        store.refreshMountStatuses(collections: collectionRecords)
                    },
                    onRemoveMember: { skill in
                        collection.memberSkillIDs.removeAll { $0 == skill.id }
                        store.refreshMountStatuses(collections: collectionRecords)
                    },
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onToggleStar: { skill in toggleStar(for: skill) }
                )
            } else if case .agent(let name) = selectedFilter {
                AgentHomeView(
                    agentName: name,
                    skills: store.skills,
                    conflicts: store.conflicts,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onToggleStar: { skill in toggleStar(for: skill) },
                    onShowConflicts: { selectedFilter = .conflicts }
                )
            } else {
                SkillListView(
                    skills: store.skills,
                    filter: selectedFilter,
                    selectedSkill: $selectedSkill,
                    onInstall: { skill in await store.installSkill(skill) },
                    onUninstall: { skill in await store.uninstallSkill(skill) },
                    onToggleStar: { skill in toggleStar(for: skill) },
                    onAddToCollection: { skill in pendingCollectionSkill = skill }
                )
            }
        } detail: {
            if selectedFilter == .controlCenter {
                ContentUnavailableView(
                    "选择分组",
                    systemImage: "rectangle.on.rectangle",
                    description: Text("在控制台打开分组查看成员,或从 Library 选择技能。")
                )
            } else if selectedFilter == .discover {
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
            } else if selectedFilter == .conflicts {
                ConflictsDetailView(conflict: selectedConflict)
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
            selectedConflict = nil
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
        .sheet(item: $pendingCollectionSkill) { skill in
            CollectionPickerSheet(
                collections: collectionRecords,
                onPick: { collection in
                    if !collection.memberSkillIDs.contains(skill.id) {
                        collection.memberSkillIDs.append(skill.id)
                        store.refreshMountStatuses(collections: collectionRecords)
                    }
                },
                onCreate: { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let record = CollectionRecord(
                        name: trimmed,
                        sortOrder: collectionRecords.count,
                        memberSkillIDs: [skill.id]
                    )
                    modelContext.insert(record)
                    store.refreshMountStatuses(collections: collectionRecords)
                }
            )
        }
        .task {
            async let skills: Void = store.reloadSkills()
            async let discover: Void = store.reloadDiscoverableSkillsDirectory()
            _ = await (skills, discover)
            store.refreshMountStatuses(collections: collectionRecords)
            store.merge(records: skillRecords)
            store.startDiscoverDirectoryRefreshLoop()
            store.startWatchingSkillDirectories()
        }
        .onChange(of: skillRecords) {
            store.merge(records: skillRecords)
        }
        .onChange(of: collectionRecords) {
            store.refreshMountStatuses(collections: collectionRecords)
        }
        .onChange(of: store.skills) {
            // 文件 watcher 重扫 / ⌘R 后重算状态灯(如 link 被手动删掉 → 黄灯)
            store.refreshMountStatuses(collections: collectionRecords)
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

    // MARK: - Collections

    private func createCollection(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let record = CollectionRecord(name: trimmed, sortOrder: collectionRecords.count)
        modelContext.insert(record)
        store.refreshMountStatuses(collections: collectionRecords)
    }

    /// 挂载/卸载 组→agent:先执行磁盘操作,再更新装载意图,最后刷新扫描与状态灯。
    private func setMounted(collection: CollectionRecord, agentID: String, mount: Bool) {
        guard let definition = AgentRegistry.agent(id: agentID) else { return }
        let members = collection.memberSkillIDs.compactMap { id in store.skills.first { $0.id == id } }
        let dir = AgentRegistry.resolvedSkillsDir(for: definition)
        if mount {
            do {
                let report = try ActivationService.mount(skills: members, agentSkillsDir: dir)
                if !collection.mountedAgentIDs.contains(agentID) {
                    collection.mountedAgentIDs.append(agentID)
                }
                if !report.skipped.isEmpty { store.errorMessage = report.summaryText }
            } catch {
                // 仅 agent skills 目录创建失败会抛出;逐技能错误已计入 report.skipped
                store.errorMessage = error.localizedDescription
            }
        } else {
            let report = ActivationService.unmount(skills: members, agentSkillsDir: dir)
            collection.mountedAgentIDs.removeAll { $0 == agentID }
            if !report.skipped.isEmpty { store.errorMessage = report.summaryText }
        }
        store.refreshMountStatuses(collections: collectionRecords)
        Task {
            await store.reloadSkills()
            // 迁移会把 path-keyed id 变成 name-keyed id:重扫后按名重对成员 id
            collection.memberSkillIDs = CollectionSupport.reconcileMemberIDs(
                collection.memberSkillIDs, skills: store.skills
            )
            store.refreshMountStatuses(collections: collectionRecords)
        }
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
        .modelContainer(for: [SkillRecord.self, CollectionRecord.self], inMemory: true)
        .frame(width: 1100, height: 700)
}

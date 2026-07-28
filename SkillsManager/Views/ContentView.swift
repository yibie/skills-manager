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

    private var detectedAgents: [AgentDefinition] {
        #if DEBUG
        if usesUIStateMatrixFixture { return Self.uiStateMatrixAgents }
        #endif
        return AgentRegistry.installedAgents()
    }

    private var usesUIStateMatrixFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-state-matrix")
        #else
        false
        #endif
    }

    var body: some View {
        splitView
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
            guard !usesUIStateMatrixFixture else { return }
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
                .disabled(usesUIStateMatrixFixture)
                .help("Open a project folder to scan for local skills")
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
                    if !collection.memberSkillIDs.contains(where: {
                        CollectionSupport.memberID($0, matches: skill, skills: store.skills)
                    }) {
                        collection.memberSkillIDs.append(skill.persistenceID)
                        refreshCollectionMountStatuses()
                    }
                },
                onCreate: { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let record = CollectionRecord(
                        name: trimmed,
                        sortOrder: collectionRecords.count,
                        memberSkillIDs: [skill.persistenceID]
                    )
                    modelContext.insert(record)
                    refreshCollectionMountStatuses()
                }
            )
        }
        .task {
            #if DEBUG
            if usesUIStateMatrixFixture {
                seedUIStateMatrixFixture()
                return
            }
            #endif
            async let skills: Void = store.reloadSkills()
            async let discover: Void = store.reloadDiscoverableSkillsDirectory()
            _ = await (skills, discover)
            reconcileCollectionMemberIDs()
            refreshCollectionMountStatuses()
            store.merge(records: skillRecords)
            store.startDiscoverDirectoryRefreshLoop()
            store.startWatchingSkillDirectories()
        }
        .onChange(of: skillRecords) {
            guard !usesUIStateMatrixFixture else { return }
            store.merge(records: skillRecords)
        }
        .onChange(of: collectionRecords) {
            refreshCollectionMountStatuses()
        }
        .onChange(of: store.skills) {
            guard !usesUIStateMatrixFixture else { return }
            // 文件 watcher 重扫 / ⌘R 后重算状态灯(如 link 被手动删掉 → 黄灯)
            reconcileCollectionMemberIDs()
            refreshCollectionMountStatuses()
        }
        .onChange(of: descriptionLanguageMode) {
            guard !usesUIStateMatrixFixture else { return }
            Task {
                await store.refreshLocalizedDescriptions(using: locale)
                store.startDiscoverHomeTranslationPrewarm(using: locale)
            }
        }
        .onChange(of: manualDescriptionLocale) {
            guard !usesUIStateMatrixFixture else { return }
            Task {
                await store.refreshLocalizedDescriptions(using: locale)
                store.startDiscoverHomeTranslationPrewarm(using: locale)
            }
        }
        .onChange(of: locale.identifier) {
            guard !usesUIStateMatrixFixture else { return }
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
        .alert("本地副本已被修改", isPresented: Binding(
            get: { store.pendingUpdateOverwrite != nil },
            set: { if !$0 { store.pendingUpdateOverwrite = nil } }
        )) {
            Button("仍要更新", role: .destructive) {
                if let skill = store.pendingUpdateOverwrite {
                    store.pendingUpdateOverwrite = nil
                    guard !usesUIStateMatrixFixture else { return }
                    Task { await store.updateSkill(skill, confirmedOverwrite: true) }
                }
            }
            Button("取消", role: .cancel) { store.pendingUpdateOverwrite = nil }
        } message: {
            Text("“\(store.pendingUpdateOverwrite?.displayName ?? "")”的内容与安装时的记录不一致。更新会用远端版本覆盖本地修改;被替换的副本会保留在库目录旁的 .skills-manager-history 中。")
        }
        .focusedSceneValue(\.skillCommandActions, SkillCommandActions(
            refresh: { refreshSkillsCommand() },
            toggleStar: currentSelectedSkill.map { skill in { toggleStar(for: skill) } },
            isStarred: currentSelectedSkill?.isStarred ?? false
        ))
    }

    private var usesWorkspaceSplit: Bool {
        if selectedFilter == .controlCenter { return true }
        if case .collection = selectedFilter { return true }
        return false
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { currentSelectedSkill != nil },
            set: { if !$0 { selectedSkill = nil } }
        )
    }

    @ViewBuilder
    private var splitView: some View {
        if usesWorkspaceSplit {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarColumn
            } detail: {
                if case .collection = selectedFilter {
                    primaryColumn
                        .inspector(isPresented: inspectorPresented) {
                            detailContent
                                .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
                        }
                } else {
                    primaryColumn
                }
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarColumn
            } content: {
                primaryColumn
            } detail: {
                detailContent
            }
        }
    }

    private var sidebarColumn: some View {
        SidebarView(
            selectedFilter: Binding(
                get: { selectedFilter },
                set: { filter in
                    guard !usesUIStateMatrixFixture || filter == .controlCenter else { return }
                    selectedFilter = filter
                }
            ),
            skills: store.skills,
            discoverableCount: store.discoverableSkillTotal,
            projectSkillCount: store.projectSkills.count,
            agentDocCount: store.agentDocs.count,
            conflictCount: store.conflicts.count,
            currentProjectURL: store.currentProjectURL,
            showsOnlyControlCenter: usesUIStateMatrixFixture
        )
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    @ViewBuilder
    private var primaryColumn: some View {
        if selectedFilter == .controlCenter {
            ControlCenterView(
                collections: collectionRecords,
                skills: store.skills,
                detectedAgents: detectedAgents,
                statusFor: { store.mountStatus(collectionID: $0.id, agentID: $1) },
                mountReportFor: { store.mountReport(collectionID: $0.id, agentID: $1) },
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
                onDelete: { collection, unmountFirst in
                    if unmountFirst {
                        for agentID in Array(collection.mountedAgentIDs) {
                            setMounted(collection: collection, agentID: agentID, mount: false)
                        }
                    }
                    modelContext.delete(collection)
                    refreshCollectionMountStatuses()
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
                onUninstall: { entry in await store.removeDiscoverSkillFromLibrary(entry) },
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
                detectedAgents: detectedAgents,
                statusFor: { store.mountStatus(collectionID: id, agentID: $0) },
                reportFor: { store.mountReport(collectionID: id, agentID: $0) },
                selectedSkill: $selectedSkill,
                onToggleAgent: { agentID, mount in
                    setMounted(collection: collection, agentID: agentID, mount: mount)
                },
                onReapply: { agentID in
                    setMounted(collection: collection, agentID: agentID, mount: true)
                },
                onAddMembers: { ids in
                    collection.memberSkillIDs.append(contentsOf: ids.filter { !collection.memberSkillIDs.contains($0) })
                    refreshCollectionMountStatuses()
                },
                onRemoveMember: { skill in
                    collection.memberSkillIDs.removeAll {
                        CollectionSupport.memberID($0, matches: skill, skills: store.skills)
                    }
                    refreshCollectionMountStatuses()
                },
                onInstall: { skill in
                    guard !usesUIStateMatrixFixture else { return }
                    await store.installSkill(skill)
                },
                onUninstall: { skill in
                    guard !usesUIStateMatrixFixture else { return }
                    await store.removeSkillFromLibrary(skill)
                },
                onMoveToTrash: { skill in
                    guard !usesUIStateMatrixFixture else { return }
                    await store.moveSkillToTrash(skill)
                },
                onToggleStar: { skill in toggleStar(for: skill) }
            )
        } else if case .agent(let name) = selectedFilter {
            AgentHomeView(
                agentName: name,
                skills: store.skills,
                conflicts: store.conflicts,
                selectedSkill: $selectedSkill,
                onInstall: { skill in await store.installSkill(skill) },
                onUninstall: { skill in await store.removeSkillFromLibrary(skill) },
                onMoveToTrash: { skill in await store.moveSkillToTrash(skill) },
                onToggleStar: { skill in toggleStar(for: skill) },
                onShowConflicts: { selectedFilter = .conflicts }
            )
        } else {
            SkillListView(
                skills: store.skills,
                filter: selectedFilter,
                selectedSkill: $selectedSkill,
                onInstall: { skill in await store.installSkill(skill) },
                onUninstall: { skill in await store.removeSkillFromLibrary(skill) },
                onMoveToTrash: { skill in await store.moveSkillToTrash(skill) },
                onToggleStar: { skill in toggleStar(for: skill) },
                onAddToCollection: { skill in pendingCollectionSkill = skill }
            )
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if selectedFilter == .discover {
            DiscoverDetailView(
                entry: selectedDiscoverSkill,
                isInstalled: selectedDiscoverSkill.map { entry in
                    DiscoverLibraryMatcher.isInstalled(entry: entry, in: store.skills)
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
                onUninstall: { entry in await store.removeDiscoverSkillFromLibrary(entry) },
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
                onPromote: { skill in
                    guard !usesUIStateMatrixFixture else { return }
                    await store.promoteSkill(skill)
                },
                onInstallToAgent: { skill, agentIDs in
                    guard !usesUIStateMatrixFixture else { return }
                    await store.installSkillToAgents(skill, agentIDs: agentIDs)
                },
                onUpdate: { skill in
                    guard !usesUIStateMatrixFixture else { return }
                    await store.updateSkill(skill)
                },
                onTranslate: { skill in
                    guard !usesUIStateMatrixFixture else { return }
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

    // MARK: - Collections

    private func createCollection(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let record = CollectionRecord(name: trimmed, sortOrder: collectionRecords.count)
        modelContext.insert(record)
        refreshCollectionMountStatuses()
    }

    /// 挂载/卸载 组→agent:先执行磁盘操作,再更新装载意图,最后刷新扫描与状态灯。
    private func setMounted(collection: CollectionRecord, agentID: String, mount: Bool) {
        #if DEBUG
        if usesUIStateMatrixFixture {
            setUIStateMatrixFixtureMounted(collection: collection, agentID: agentID, mount: mount)
            return
        }
        #endif
        guard let definition = AgentRegistry.agent(id: agentID) else { return }
        let resolution = CollectionSupport.resolveMemberIDs(collection.memberSkillIDs, skills: store.skills)
        let dir = AgentRegistry.resolvedSkillsDir(for: definition)
        if mount {
            var report = MountReport(
                skipped: resolution.missingIDs.map {
                    .init(skillID: $0, reason: ActivationService.missingLibraryMemberReason)
                }
            )
            guard !resolution.members.isEmpty else {
                store.recordMountReport(report, collectionID: collection.id, agentID: agentID)
                refreshCollectionMountStatuses()
                return
            }
            do {
                let mountReport = try ActivationService.mount(skills: resolution.members, agentSkillsDir: dir)
                report.changed.append(contentsOf: mountReport.changed)
                report.skipped.append(contentsOf: mountReport.skipped)
                if !collection.mountedAgentIDs.contains(agentID) {
                    collection.mountedAgentIDs.append(agentID)
                }
                store.recordMountReport(report, collectionID: collection.id, agentID: agentID)
            } catch {
                // 仅 agent skills 目录创建失败会抛出;逐技能错误已计入 report.skipped
                store.errorMessage = error.localizedDescription
            }
        } else {
            let protectedIDs = CollectionSupport.protectedMountedMemberIDs(
                excluding: collection,
                agentID: agentID,
                collections: collectionRecords,
                skills: store.skills
            )
            let protected = resolution.members.filter { protectedIDs.contains($0.persistenceID) }
            let unmountable = resolution.members.filter { !protectedIDs.contains($0.persistenceID) }
            let unmountReport = ActivationService.unmount(skills: unmountable, agentSkillsDir: dir)
            var report = unmountReport
            report.skipped.append(contentsOf: resolution.missingIDs.map {
                .init(skillID: $0, reason: ActivationService.missingLibraryMemberReason)
            })
            report.skipped.append(contentsOf: protected.map {
                .init(skillID: $0.persistenceID, reason: ActivationService.sharedCollectionReferenceReason)
            })
            // 有残留(如实体目录不删除)时保留挂载意图:状态灯持续黄灯并可"重新应用",
            // 冲突不能伪装成卸载成功
            if unmountReport.skipped.isEmpty {
                collection.mountedAgentIDs.removeAll { $0 == agentID }
            }
            store.recordMountReport(report, collectionID: collection.id, agentID: agentID)
        }
        refreshCollectionMountStatuses()
        Task {
            await store.reloadSkills()
            // 迁移会把 path-keyed id 变成 name-keyed id:重扫后按名重对成员 id
            reconcileCollectionMemberIDs()
            refreshCollectionMountStatuses()
        }
    }

    private func refreshCollectionMountStatuses() {
        #if DEBUG
        if usesUIStateMatrixFixture {
            applyUIStateMatrixFixtureStatuses(collections: collectionRecords)
            return
        }
        #endif
        store.refreshMountStatuses(collections: collectionRecords)
    }

    private func reconcileCollectionMemberIDs() {
        for collection in collectionRecords {
            let reconciled = CollectionSupport.reconcileMemberIDs(collection.memberSkillIDs, skills: store.skills)
            if collection.memberSkillIDs != reconciled {
                collection.memberSkillIDs = reconciled
            }
        }
    }

    private func refreshSkillsCommand() {
        #if DEBUG
        if usesUIStateMatrixFixture {
            seedUIStateMatrixFixture()
            return
        }
        #endif
        Task { await store.reloadSkills() }
    }

    /// Toggles a skill's star in both SwiftData and the state file shared with the TUI.
    private func toggleStar(for skill: Skill) {
        let newValue = !skill.isStarred
        let record = SkillRecord.recordForStarWrite(for: skill, in: modelContext)
        record.isStarred = newValue
        guard !usesUIStateMatrixFixture else {
            if let index = store.skills.firstIndex(where: { $0.id == skill.id }) {
                store.skills[index].isStarred = newValue
            }
            return
        }
        store.setSkillStarred(skill, isStarred: newValue)
    }

    #if DEBUG
    private static let uiStateMatrixAgentIDs = ["claude-code", "codex", "cursor"]

    private static var uiStateMatrixAgents: [AgentDefinition] {
        uiStateMatrixAgentIDs.compactMap { AgentRegistry.agent(id: $0) }
    }

    private func seedUIStateMatrixFixture() {
        let arguments = ProcessInfo.processInfo.arguments
        let skills = arguments.contains("--ui-state-matrix-empty") ? [] : Skill.mockSkills
        store.skills = skills
        store.conflicts = []
        store.discoverableSkills = []
        store.discoverSearchResults = []
        store.discoverableSkillDetails = [:]
        store.discoverableSkillTotal = 0

        guard !skills.isEmpty else {
            selectedFilter = .controlCenter
            applyUIStateMatrixFixtureStatuses(collections: [])
            return
        }

        let collections: [CollectionRecord]
        if collectionRecords.isEmpty {
            let ids = skills.map(\.persistenceID)
            collections = [
                CollectionRecord(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                    name: "2.0 RC：已挂载",
                    sortOrder: 0,
                    memberSkillIDs: Array(ids.prefix(2)),
                    mountedAgentIDs: ["claude-code"]
                ),
                CollectionRecord(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                    name: "2.0 RC：部分缺失",
                    sortOrder: 1,
                    memberSkillIDs: [ids[2], "legacy:missing-skill"],
                    mountedAgentIDs: ["codex"]
                ),
                CollectionRecord(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                    name: "2.0 RC：空分组",
                    sortOrder: 2,
                    memberSkillIDs: [],
                    mountedAgentIDs: ["cursor"]
                ),
                CollectionRecord(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
                    name: "2.0 RC：共享挂载",
                    sortOrder: 3,
                    memberSkillIDs: [ids[0]],
                    mountedAgentIDs: ["claude-code"]
                ),
            ]
            for collection in collections {
                modelContext.insert(collection)
            }
            do {
                try modelContext.save()
            } catch {
                store.errorMessage = "UI state matrix fixture failed: \(error.localizedDescription)"
            }
        } else {
            collections = collectionRecords
        }

        selectedFilter = .controlCenter
        applyUIStateMatrixFixtureStatuses(collections: collections)
        if arguments.contains("--ui-state-matrix-update-drift") {
            store.pendingUpdateOverwrite = skills[0]
        }
    }

    private func applyUIStateMatrixFixtureStatuses(collections: [CollectionRecord]) {
        var statuses: [String: MountStatus] = [:]
        var reports: [String: MountReport] = [:]
        for collection in collections {
            let resolution = CollectionSupport.resolveMemberIDs(collection.memberSkillIDs, skills: store.skills)
            for agentID in collection.mountedAgentIDs {
                let key = "\(collection.id.uuidString):\(agentID)"
                statuses[key] = ActivationService.status(
                    intentMounted: true,
                    linkedCount: resolution.members.count,
                    memberCount: collection.memberSkillIDs.count
                )
                var report = MountReport(changed: resolution.members.map(\.persistenceID))
                report.skipped = resolution.missingIDs.map {
                    .init(skillID: $0, reason: ActivationService.missingLibraryMemberReason)
                }
                if !report.skipped.isEmpty {
                    reports[key] = report
                }
            }
        }
        store.mountStatuses = statuses
        store.mountReports = reports
    }

    private func setUIStateMatrixFixtureMounted(collection: CollectionRecord, agentID: String, mount: Bool) {
        if mount {
            if !collection.mountedAgentIDs.contains(agentID) {
                collection.mountedAgentIDs.append(agentID)
            }
        } else {
            collection.mountedAgentIDs.removeAll { $0 == agentID }
        }
        applyUIStateMatrixFixtureStatuses(collections: collectionRecords)
    }
    #endif
}

#Preview {
    ContentView()
        .modelContainer(for: [SkillRecord.self, CollectionRecord.self], inMemory: true)
        .frame(width: 1100, height: 700)
}

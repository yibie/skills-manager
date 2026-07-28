import AppKit
import Combine
import Foundation
import Observation
import CryptoKit

enum DescriptionTranslationSkipReason: String, CaseIterable, Equatable, Sendable {
    case alreadyTranslated
    case missingBaseDescription
    case samePrimaryLanguage
    case unchanged

    var summaryLabel: String {
        switch self {
        case .alreadyTranslated: return "already translated"
        case .missingBaseDescription: return "no summary"
        case .samePrimaryLanguage: return "same language"
        case .unchanged: return "unchanged"
        }
    }

    var sortOrder: Int {
        switch self {
        case .missingBaseDescription: return 0
        case .alreadyTranslated: return 1
        case .samePrimaryLanguage: return 2
        case .unchanged: return 3
        }
    }
}

enum DescriptionTranslationFailureReason: String, CaseIterable, Equatable, Sendable {
    case providerCooldown
    case serviceUnavailable
    case modelUnavailable
    case requestTimedOut
    case requestFailed

    var summaryLabel: String {
        switch self {
        case .providerCooldown: return "cooldown"
        case .serviceUnavailable: return "service unavailable"
        case .modelUnavailable: return "model unavailable"
        case .requestTimedOut: return "timeout"
        case .requestFailed: return "request failed"
        }
    }

    var sortOrder: Int {
        switch self {
        case .requestTimedOut: return 0
        case .providerCooldown: return 1
        case .serviceUnavailable: return 2
        case .modelUnavailable: return 3
        case .requestFailed: return 4
        }
    }
}

enum DescriptionTranslationDeferredReason: String, CaseIterable, Equatable, Sendable {
    case summaryNotLoaded

    var summaryLabel: String {
        switch self {
        case .summaryNotLoaded: return "summary not loaded"
        }
    }

    var sortOrder: Int {
        switch self {
        case .summaryNotLoaded: return 0
        }
    }
}

enum DescriptionTranslationAttempt: Equatable, Sendable {
    case translated(String)
    case skipped(DescriptionTranslationSkipReason)
    case failed(DescriptionTranslationFailureReason)
}

enum DescriptionTranslationScope: Equatable, Sendable {
    case all
    case skill(id: String)
    case projectSkill(id: String)
    case discoverSkill(id: String)
    case loadedDiscoverDetails
}

struct DescriptionTranslationSummary: Equatable, Sendable {
    var translated = 0
    var skipped = 0
    var deferred = 0
    var failed = 0
    var skippedReasons: [DescriptionTranslationSkipReason: Int] = [:]
    var deferredReasons: [DescriptionTranslationDeferredReason: Int] = [:]
    var failedReasons: [DescriptionTranslationFailureReason: Int] = [:]

    mutating func formUnion(_ other: DescriptionTranslationSummary) {
        translated += other.translated
        skipped += other.skipped
        deferred += other.deferred
        failed += other.failed
        for (reason, count) in other.skippedReasons {
            skippedReasons[reason, default: 0] += count
        }
        for (reason, count) in other.deferredReasons {
            deferredReasons[reason, default: 0] += count
        }
        for (reason, count) in other.failedReasons {
            failedReasons[reason, default: 0] += count
        }
    }

    mutating func recordSkip(_ reason: DescriptionTranslationSkipReason) {
        skipped += 1
        skippedReasons[reason, default: 0] += 1
    }

    mutating func recordDeferred(_ reason: DescriptionTranslationDeferredReason) {
        deferred += 1
        deferredReasons[reason, default: 0] += 1
    }

    mutating func recordFailure(_ reason: DescriptionTranslationFailureReason) {
        failed += 1
        failedReasons[reason, default: 0] += 1
    }

    mutating func recordTranslation() {
        translated += 1
    }

    var statusText: String {
        var parts = ["Translated \(translated)", "Skipped \(skipped)"]
        if deferred > 0 {
            parts.append("Pending \(deferred)")
        }
        parts.append("Failed \(failed)")
        return parts.joined(separator: " · ")
    }

    var breakdownText: String? {
        var parts: [String] = []

        let failureParts = failedReasons.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.sortOrder < $1.key.sortOrder
        }.prefix(2).map { "\($0.key.summaryLabel) \($0.value)" }
        parts.append(contentsOf: failureParts)

        let deferredParts = deferredReasons.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.sortOrder < $1.key.sortOrder
        }.prefix(max(0, 3 - parts.count)).map { "\($0.key.summaryLabel) \($0.value)" }
        parts.append(contentsOf: deferredParts)

        let skipParts = skippedReasons.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.sortOrder < $1.key.sortOrder
        }.prefix(max(0, 3 - parts.count)).map { "\($0.key.summaryLabel) \($0.value)" }
        parts.append(contentsOf: skipParts)

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var toolbarText: String {
        guard let breakdownText else { return statusText }
        return "\(statusText) · \(breakdownText)"
    }

    var helpText: String {
        toolbarText
    }
}

@Observable
@MainActor
final class SkillStore {
    typealias DiscoverInstaller = @Sendable (DiscoverSkill, [String], @escaping @Sendable (String) -> Void) async throws -> Void
    typealias TranslationDebugLogger = @Sendable (String) -> Void

    // MARK: - State

    var skills: [Skill] = []
    var conflicts: [SkillConflict] = []
    var discoverableSkills: [DiscoverSkill] = []
    var discoverSearchResults: [DiscoverSkill] = []
    var discoverableSkillDetails: [String: DiscoverSkill] = [:]
    var discoverableSkillTotal: Int = 0
    var discoverCategory: DiscoverDirectoryCategory = .allTime
    var discoverInstallActivities: [DiscoverInstallActivity] = []
    var projectSkills: [Skill] = []
    var agentDocs: [AgentDoc] = []
    var agentDocsManifest = AgentDocsManifest()
    var agentDocsStatus: [AgentDocTargetStatus] = []
    var currentProjectURL: URL?
    var isLoading = false
    var isLoadingDiscover = false
    var isLoadingProject = false
    var isLoadingAgentDocs = false
    var isSyncingAgentDocs = false
    var isSyncing = false
    var isTranslatingDescriptions = false
    var lastTranslationSummary: DescriptionTranslationSummary?
    var errorMessage: String?
    /// 更新前发现本地副本被修改过、等待用户确认覆盖的技能。
    var pendingUpdateOverwrite: Skill?
    /// 挂载状态缓存:key 为内联的 "<collectionUUID>:<agentID>" 格式;由 refreshMountStatuses 重建。
    var mountStatuses: [String: MountStatus] = [:]
    /// 最近一次挂载/卸载的逐技能结果,key 同 mountStatuses;在相关对象附近呈现,不进全局 Error。
    var mountReports: [String: MountReport] = [:]

    // MARK: - Services

    private let claudeAdapter: ClaudeCodeAdapter
    private let universalAdapter: UniversalAdapter
    private let directoryService: SkillsDirectoryService
    private let discoverCache: DiscoverDirectoryCache
    private let discoverInstaller: DiscoverInstaller
    private let lifecycleService: SkillLifecycleService
    private let openClawAdapter: OpenClawAdapter
    private let descriptionLocalizer: any DescriptionLocalizing
    private let translationDebugLogger: TranslationDebugLogger
    private var discoverRefreshLoopTask: Task<Void, Never>?
    private var discoverHomeTranslationTask: Task<Void, Never>?
    private var loadingDiscoverSkillDetails = Set<String>()
    private var hasRequestedDescriptionTranslation = false
    private let discoverDetailRefreshInterval: TimeInterval = 7 * 24 * 60 * 60
    /// Last SwiftData records handed to `merge(records:)`; re-applied after every rescan.
    private var persistedRecords: [SkillRecord] = []

    // MARK: - Real-time directory monitoring

    private let fileWatcher = FileWatcher()
    private var fileWatcherCancellable: AnyCancellable?
    private var fileWatcherReloadTask: Task<Void, Never>?

    init(
        claudeAdapter: ClaudeCodeAdapter = ClaudeCodeAdapter(),
        universalAdapter: UniversalAdapter = UniversalAdapter(),
        directoryService: SkillsDirectoryService = SkillsDirectoryService(),
        discoverCache: DiscoverDirectoryCache = DiscoverDirectoryCache(),
        openClawAdapter: OpenClawAdapter = OpenClawAdapter(),
        descriptionLocalizer: any DescriptionLocalizing = DescriptionLocalizationService(),
        translationDebugLogger: @escaping TranslationDebugLogger = { Swift.print($0) },
        discoverInstaller: DiscoverInstaller? = nil
    ) {
        self.claudeAdapter = claudeAdapter
        self.universalAdapter = universalAdapter
        self.directoryService = directoryService
        self.discoverCache = discoverCache
        self.openClawAdapter = openClawAdapter
        self.descriptionLocalizer = descriptionLocalizer
        self.translationDebugLogger = translationDebugLogger
        let lifecycleService = SkillLifecycleService()
        self.lifecycleService = lifecycleService
        self.discoverInstaller = discoverInstaller ?? { skill, agentIDs, appendLog in
            try await lifecycleService.installDiscover(
                skill,
                agentIDs: agentIDs,
                appendLog: appendLog
            )
        }
    }

    // MARK: - Local skills

    func reloadSkills() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let claudeSkills = claudeAdapter.scanSkills()
            async let universalSkills = universalAdapter.scanSkills()
            async let openClawSkills = openClawAdapter.scanSkills()
            let (claude, universal, openclaw) = try await (claudeSkills, universalSkills, openClawSkills)
            let scanned = claude + universal + openclaw
            conflicts = SkillConflictDetection.detect(in: scanned)
            let merged = lifecycleService.annotate(Self.mergeScannedSkills(scanned))
            skills = await localizeSkills(merged)
            applyPersistedSkillState()
            if hasRequestedDescriptionTranslation {
                _ = await translateMissingSkillDescriptions()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated static func mergeScannedSkills(_ scanned: [Skill]) -> [Skill] {
        var merged: [Skill] = []
        var indexByPath: [String: Int] = [:]

        for skill in scanned {
            let path = skill.filePath.resolvingSymlinksInPath().standardizedFileURL.path
            if let index = indexByPath[path] {
                for agent in skill.compatibleAgents where !merged[index].compatibleAgents.contains(agent) {
                    merged[index].compatibleAgents.append(agent)
                }
                if merged[index].canonicalPath == nil {
                    merged[index].canonicalPath = skill.canonicalPath
                }
                indexByPath[path] = index
            } else {
                indexByPath[path] = merged.count
                merged.append(skill)
            }
        }

        return merged
    }

    func merge(records: [SkillRecord], sharedStarredNames: Set<String>? = nil) {
        persistedRecords = records
        applyPersistedSkillState(sharedStarredNames: sharedStarredNames)
    }

    /// Re-applies SwiftData records and the TUI-shared star file to the in-memory
    /// skills. Runs after every scan so stars and install states survive reloads.
    private func applyPersistedSkillState(sharedStarredNames: Set<String>? = nil) {
        let lookup = Dictionary(persistedRecords.map { ($0.skillID, $0) }, uniquingKeysWith: { first, _ in first })
        let sharedStarred = sharedStarredNames ?? SharedStarredState.starredNames()
        let nameCounts = Dictionary(grouping: skills, by: \.name).mapValues(\.count)
        for index in skills.indices {
            let record = lookup[skills[index].persistenceID] ?? lookup[skills[index].id]
            let sharedFallback = record == nil
                && nameCounts[skills[index].name] == 1
                && sharedStarred.contains(skills[index].name)
            skills[index].isStarred = record?.isStarred ?? sharedFallback
            if let record {
                skills[index].installState = InstallState(rawValue: record.installState) ?? .notInstalled
            }
        }
    }

    /// Sets a skill's star and writes through to the state file shared with the TUI.
    /// The SwiftData record is updated by the caller (the view owns the ModelContext).
    func setSkillStarred(_ skill: Skill, isStarred: Bool) {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index].isStarred = isStarred
        }
        SharedStarredState.setStarred(isStarred, skillName: skill.name)
    }

    // MARK: - Real-time directory monitoring

    /// Watches every known agent skills directory and reloads the library when one
    /// changes on disk (e.g. an install done from a terminal). Changes are debounced
    /// so a batch of file writes collapses into a single rescan.
    func startWatchingSkillDirectories() {
        refreshWatchedSkillDirectories()
        guard fileWatcherCancellable == nil else { return }
        fileWatcherCancellable = fileWatcher.$lastChange
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleWatchedSkillsReload()
            }
    }

    private func refreshWatchedSkillDirectories() {
        let directories = claudeAdapter.skillsDirectories
            + universalAdapter.skillsDirectories
            + openClawAdapter.skillsDirectories
        fileWatcher.watch(directories: directories)
    }

    private func scheduleWatchedSkillsReload() {
        fileWatcherReloadTask?.cancel()
        fileWatcherReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.reloadSkills()
            // Pick up skills directories that appeared since the last pass.
            self.refreshWatchedSkillDirectories()
        }
    }

    // MARK: - Discover (skills.sh)

    func reloadDiscoverableSkillsDirectory() async {
        isLoadingDiscover = true
        defer { isLoadingDiscover = false }

        let cachedSnapshot = await discoverCache.directorySnapshot(category: discoverCategory)
        if let cachedSnapshot {
            await applyDiscoverDirectorySnapshot(cachedSnapshot, translateIfRequested: false)
        }

        do {
            let directory = try await directoryService.loadSkillsDirectory(category: discoverCategory)
            await discoverCache.storeDirectory(
                skills: directory.skills,
                total: directory.total,
                category: discoverCategory
            )
            await applyDiscoverDirectorySnapshot(
                DiscoverDirectoryCache.Snapshot(
                    skills: directory.skills,
                    total: directory.total,
                    updatedAt: Date()
                ),
                translateIfRequested: true
            )
            startDiscoverHomeTranslationPrewarm()
        } catch {
            if cachedSnapshot == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setDiscoverCategory(_ category: DiscoverDirectoryCategory) async {
        guard discoverCategory != category else { return }
        discoverCategory = category
        discoverableSkills = []
        discoverSearchResults = []
        discoverableSkillDetails = [:]
        discoverableSkillTotal = 0
        if category != .allTime {
            cancelDiscoverHomeTranslationPrewarm()
        }
        await reloadDiscoverableSkillsDirectory()
    }

    func refreshDiscoverableSkillsDirectory() async {
        isSyncing = true
        defer { isSyncing = false }
        await reloadDiscoverableSkillsDirectory()
    }

    func searchDiscoverableSkillsDirectory(query: String) async throws -> (skills: [DiscoverSkill], count: Int) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return ([], 0)
        }

        let cachedSnapshot = await discoverCache.searchSnapshot(query: trimmedQuery)

        do {
            let searchResult = try await directoryService.searchSkills(query: trimmedQuery)
            await discoverCache.storeSearch(
                query: trimmedQuery,
                skills: searchResult.skills,
                count: searchResult.count
            )

            let mergedSnapshot = await discoverCache.searchSnapshot(query: trimmedQuery)
                ?? DiscoverDirectoryCache.Snapshot(
                    skills: searchResult.skills,
                    total: searchResult.count,
                    updatedAt: Date()
                )
            await mergeCachedDiscoverDetails()
            let localized = await localizeDiscoverSkills(mergedSnapshot.skills)
            discoverSearchResults = localized
            return (localized, mergedSnapshot.total)
        } catch {
            if let cachedSnapshot {
                await mergeCachedDiscoverDetails()
                let localized = await localizeDiscoverSkills(cachedSnapshot.skills)
                discoverSearchResults = localized
                return (localized, cachedSnapshot.total)
            }
            throw error
        }
    }

    func startDiscoverDirectoryRefreshLoop(interval: UInt64 = 6 * 60 * 60 * 1_000_000_000) {
        guard discoverRefreshLoopTask == nil else { return }

        discoverRefreshLoopTask = Task { [weak self] in
            defer {
                Task { @MainActor in
                    self?.discoverRefreshLoopTask = nil
                }
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    break
                }

                guard !Task.isCancelled, let self else { break }
                await self.refreshDiscoverableSkillsDirectory()
            }
        }
    }

    func startDiscoverHomeTranslationPrewarm(using locale: Locale = .autoupdatingCurrent) {
        cancelDiscoverHomeTranslationPrewarm()
        guard discoverCategory == .allTime, !discoverableSkills.isEmpty else { return }

        discoverHomeTranslationTask = Task { [weak self] in
            _ = await self?.translateDiscoverHomeSkills(using: locale)
        }
    }

    func cancelDiscoverHomeTranslationPrewarm() {
        discoverHomeTranslationTask?.cancel()
        discoverHomeTranslationTask = nil
    }

    @discardableResult
    func translateDiscoverHomeSkills(using locale: Locale = .autoupdatingCurrent) async -> DescriptionTranslationSummary {
        guard discoverCategory == .allTime, !discoverableSkills.isEmpty else {
            return DescriptionTranslationSummary()
        }
        guard !isTranslatingDescriptions else {
            return DescriptionTranslationSummary()
        }

        isTranslatingDescriptions = true
        defer { isTranslatingDescriptions = false }

        let entries = discoverableSkills
        let config = AppSettings.currentLLMConfig()
        logTranslationRunStart(locale: locale, config: config)
        var summary = DescriptionTranslationSummary()

        for entry in entries {
            if Task.isCancelled { break }
            await loadDiscoverSkillDetail(entry)
            guard discoverableSkillDetails[entry.id] != nil else {
                summary.recordDeferred(.summaryNotLoaded)
                continue
            }
            await translateDiscoverDetailDescription(
                key: entry.id,
                locale: locale,
                config: config,
                summary: &summary
            )
            if summary.failed > 0 { break }
        }

        lastTranslationSummary = summary
        logTranslationRunSummary(summary)
        return summary
    }

    func loadDiscoverSkillDetail(_ skill: DiscoverSkill) async {
        if discoverableSkillDetails[skill.id] != nil || loadingDiscoverSkillDetails.contains(skill.id) {
            return
        }

        if let cachedDetail = await discoverCache.detail(for: skill.id) {
            await storeLoadedDiscoverDetail(cachedDetail, persist: false)
            let isStale = await discoverCache.isDetailStale(
                for: skill.id,
                olderThan: discoverDetailRefreshInterval
            )
            if !isStale {
                return
            }
        }

        loadingDiscoverSkillDetails.insert(skill.id)
        defer { loadingDiscoverSkillDetails.remove(skill.id) }

        do {
            let detailed = try await directoryService.loadSkillDetail(skill)
            await storeLoadedDiscoverDetail(detailed, persist: true)
        } catch {
            // Keep discover browsing resilient even if a detail page changes.
        }
    }

    func installDiscoverSkill(_ skill: DiscoverSkill, agentIDs: [String]) async {
        guard !agentIDs.isEmpty else { return }
        guard !isInstallingDiscoverSkill(skill) else { return }

        let activityID = "\(skill.id):\(UUID().uuidString)"
        upsertDiscoverInstallActivity(
            DiscoverInstallActivity(
                id: activityID,
                skillID: skill.id,
                skillName: skill.name,
                targetAgents: agentIDs,
                command: "Skills Manager lifecycle",
                startedAt: Date(),
                finishedAt: nil,
                status: .running,
                log: ["Queued install for \(skill.name) to \(agentIDs.joined(separator: ", "))"]
            )
        )

        do {
            appendDiscoverInstallLog("Starting install through Skills Manager", activityID: activityID)
            try await discoverInstaller(skill, agentIDs) { [weak self] line in
                guard let self else { return }
                Task { @MainActor in
                    self.appendDiscoverInstallLog(line, activityID: activityID)
                }
            }
            await reloadSkills()
            finishDiscoverInstallActivity(activityID: activityID, status: .succeeded, finalMessage: "Install completed for \(agentIDs.joined(separator: ", "))")
        } catch {
            finishDiscoverInstallActivity(activityID: activityID, status: .failed, finalMessage: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func installDiscoverSkill(_ skill: DiscoverSkill) async {
        let defaultAgents = AgentRegistry.installedAgents().contains(where: { $0.id == "claude-code" }) ? ["claude-code"] : []
        await installDiscoverSkill(skill, agentIDs: defaultAgents)
    }

    func removeDiscoverSkillFromLibrary(_ skill: DiscoverSkill) async {
        // 同名不是充分证据:只删 provenance 与该条目精确对应的技能,防止误删用户的同名技能
        guard case let .installed(installed) = DiscoverLibraryMatcher.match(entry: skill, in: skills) else { return }
        await removeSkillFromLibrary(installed)
    }

    func isInstallingDiscoverSkill(_ skill: DiscoverSkill) -> Bool {
        discoverInstallActivities.contains { $0.skillID == skill.id && $0.status == .running }
    }

    func discoverInstallActivity(for skillID: String) -> DiscoverInstallActivity? {
        discoverInstallActivities.first { $0.skillID == skillID }
    }

    func orderedDiscoverInstallActivities(prioritizing skillID: String?) -> [DiscoverInstallActivity] {
        discoverInstallActivities.sorted { lhs, rhs in
            let lhsPriority = lhs.skillID == skillID ? 0 : 1
            let rhsPriority = rhs.skillID == skillID ? 0 : 1
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.startedAt > rhs.startedAt
        }
    }

    // MARK: - Skill-level install/uninstall

    /// Marks a skill as installed (trial → keep, or re-install state).
    func installSkill(_ skill: Skill) async {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index].installState = .installed
        }
    }

    /// Deletes a skill from the Library through its detected lifecycle provider.
    /// Removing collection mounts is intentionally handled by ActivationService.
    func removeSkillFromLibrary(_ skill: Skill) async {
        do {
            try await lifecycleService.removeFromLibrary(skill, appendLog: { _ in })
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSkill(_ skill: Skill, confirmedOverwrite: Bool = false) async {
        if !confirmedOverwrite && lifecycleService.hasLocalDrift(skill) {
            pendingUpdateOverwrite = skill
            return
        }
        let agentIDs = skill.compatibleAgents.compactMap { displayName in
            AgentRegistry.all.first { $0.displayName == displayName }?.id
        }
        do {
            try await lifecycleService.update(skill, agentIDs: agentIDs, appendLog: { _ in })
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Explicitly removes an unmanaged local skill using the recoverable macOS Trash.
    func moveSkillToTrash(
        _ skill: Skill,
        trashItem: (URL) throws -> Void = { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    ) async {
        guard skill.canMoveToTrash else {
            errorMessage = "This skill is managed by Skills Manager and should be uninstalled instead."
            return
        }

        let target = skill.trashTargetURL
        guard FileManager.default.fileExists(atPath: target.path) else {
            errorMessage = "The skill no longer exists at \(target.path)."
            return
        }

        do {
            try trashItem(target)
            removeSkillFromState(skill)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeSkillFromState(_ skill: Skill) {
        skills.removeAll { $0.id == skill.id }

        // Keep the conflict list consistent with the removal.
        let removedPath = skill.directoryPath.resolvingSymlinksInPath().standardizedFileURL.path
        conflicts = conflicts.compactMap { conflict in
            let remaining = conflict.instances.filter { $0.path != removedPath }
            guard remaining.count != conflict.instances.count else { return conflict }
            return remaining.count > 1 ? SkillConflict(name: conflict.name, instances: remaining) : nil
        }
    }

    func installSkills(_ batch: [Skill]) async {
        for skill in batch { await installSkill(skill) }
    }

    // MARK: - Install to agents via SymlinkInstaller

    func installSkillToAgents(_ skill: Skill, agentIDs: [String]) async {
        do {
            try await lifecycleService.install(
                skill,
                agentIDs: agentIDs,
                appendLog: { _ in }
            )
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Project skills

    func openProject(url: URL) async {
        currentProjectURL = url
        async let skills: Void = loadProjectSkills()
        async let docs: Void = loadAgentDocs()
        _ = await (skills, docs)
    }

    func loadProjectSkills() async {
        guard let projectURL = currentProjectURL else {
            projectSkills = []
            return
        }
        isLoadingProject = true
        defer { isLoadingProject = false }
        // Run filesystem scan on a background thread to avoid blocking the MainActor.
        // Skill is Sendable so the result crosses the actor boundary safely.
        let results = await Task.detached(priority: .userInitiated) {
            ProjectScanner().scan(projectURL: projectURL)
        }.value
        projectSkills = await localizeSkills(results)
        if hasRequestedDescriptionTranslation {
            _ = await translateMissingProjectDescriptions()
        }
    }

    func loadAgentDocs() async {
        guard let projectURL = currentProjectURL else {
            agentDocs = []
            agentDocsManifest = AgentDocsManifest()
            agentDocsStatus = []
            return
        }

        isLoadingAgentDocs = true
        defer { isLoadingAgentDocs = false }

        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try AgentDocsService().load(projectURL: projectURL)
            }.value
            applyAgentDocsSnapshot(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createAgentDoc(fileName: String, content: String) async {
        guard let projectURL = currentProjectURL else { return }
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try AgentDocsService().createDoc(projectURL: projectURL, fileName: fileName, content: content)
            }.value
            applyAgentDocsSnapshot(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAgentDocTargets(_ targets: [AgentDocsManifest.Target]) async {
        guard let projectURL = currentProjectURL else { return }
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try AgentDocsService().updateTargets(projectURL: projectURL, targets: targets)
            }.value
            applyAgentDocsSnapshot(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncAgentDocs() async {
        guard let projectURL = currentProjectURL else { return }
        isSyncingAgentDocs = true
        defer { isSyncingAgentDocs = false }

        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try AgentDocsService().sync(projectURL: projectURL)
            }.value
            applyAgentDocsSnapshot(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openDocInEditor(_ doc: AgentDoc) {
        NSWorkspace.shared.open(doc.url)
    }

    private func applyAgentDocsSnapshot(_ snapshot: AgentDocsSnapshot) {
        agentDocs = snapshot.docs
        agentDocsManifest = snapshot.manifest
        agentDocsStatus = snapshot.statuses
    }

    /// Copies a project-local skill to ~/.claude/skills/.
    /// Converts .mdc → SKILL.md format if needed.
    func promoteSkill(_ skill: Skill) async {
        let destDirName = Self.promotedDirectoryName(
            displayName: skill.displayName, directoryName: skill.name)
        let skillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills/\(destDirName)")
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: skillsDir.path) {
                try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            }
            let destFile = skillsDir.appendingPathComponent("SKILL.md")
            let content: String
            if skill.filePath.pathExtension == "mdc" {
                content = SkillFormatConverter.toSKILLMD(
                    name: skill.name,
                    mdcContent: skill.markdownContent
                )
            } else {
                content = try String(contentsOf: skill.filePath, encoding: .utf8)
            }
            try content.write(to: destFile, atomically: true, encoding: .utf8)
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Directory name used under ~/.claude/skills/ when promoting a skill.
    /// Prefers displayName (frontmatter name: field) over the raw directory name.
    /// Frontmatter is third-party content that becomes a path component, so it
    /// goes through the same sanitizer as every other install path.
    nonisolated static func promotedDirectoryName(displayName: String, directoryName: String) -> String {
        SymlinkInstaller.sanitize(displayName.isEmpty ? directoryName : displayName)
    }

    private func upsertDiscoverInstallActivity(_ activity: DiscoverInstallActivity) {
        discoverInstallActivities.removeAll { $0.id == activity.id }
        discoverInstallActivities.insert(activity, at: 0)
        if discoverInstallActivities.count > 20 {
            discoverInstallActivities = Array(discoverInstallActivities.prefix(20))
        }
    }

    private func appendDiscoverInstallLog(_ line: String, activityID: String) {
        guard let index = discoverInstallActivities.firstIndex(where: { $0.id == activityID }) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        discoverInstallActivities[index].log.append(trimmed)
    }

    private func finishDiscoverInstallActivity(activityID: String, status: DiscoverInstallStatus, finalMessage: String) {
        guard let index = discoverInstallActivities.firstIndex(where: { $0.id == activityID }) else { return }
        let trimmed = finalMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            discoverInstallActivities[index].log.append(trimmed)
        }
        discoverInstallActivities[index].status = status
        discoverInstallActivities[index].finishedAt = Date()
    }

    func refreshLocalizedDescriptions(using locale: Locale = .autoupdatingCurrent) async {
        skills = await localizeSkills(skills, locale: locale)
        projectSkills = await localizeSkills(projectSkills, locale: locale)
        discoverableSkills = await localizeDiscoverSkills(discoverableSkills, locale: locale)
        discoverSearchResults = await localizeDiscoverSkills(discoverSearchResults, locale: locale)

        var detailsToLocalize: [String: DiscoverSkill] = [:]
        for detail in await discoverCache.allDetails() {
            detailsToLocalize[detail.id] = detail
        }
        for (key, value) in discoverableSkillDetails {
            detailsToLocalize[key] = value
        }

        var localizedDetails: [String: DiscoverSkill] = [:]
        for (key, value) in detailsToLocalize {
            localizedDetails[key] = await localizeDiscoverSkill(value, locale: locale)
        }
        discoverableSkillDetails = localizedDetails
    }

    func translateDescriptions(
        using locale: Locale = .autoupdatingCurrent,
        scope: DescriptionTranslationScope = .all
    ) async {
        guard !isTranslatingDescriptions else { return }

        hasRequestedDescriptionTranslation = true
        isTranslatingDescriptions = true
        defer { isTranslatingDescriptions = false }

        let config = AppSettings.currentLLMConfig()
        logTranslationRunStart(locale: locale, config: config)
        await refreshLocalizedDescriptions(using: locale)
        var summary = DescriptionTranslationSummary()
        switch scope {
        case .all:
            summary.formUnion(await translateMissingSkillDescriptions(locale: locale))
            guard summary.failed == 0 else {
                lastTranslationSummary = summary
                logTranslationRunSummary(summary)
                return
            }
            summary.formUnion(await translateMissingProjectDescriptions(locale: locale))
            guard summary.failed == 0 else {
                lastTranslationSummary = summary
                logTranslationRunSummary(summary)
                return
            }
            summary.formUnion(await translateMissingDiscoverDescriptions(locale: locale))
        case .skill(let id):
            summary.formUnion(await translateMissingSkillDescription(id: id, locale: locale))
        case .projectSkill(let id):
            summary.formUnion(await translateMissingProjectDescription(id: id, locale: locale))
        case .discoverSkill(let id):
            summary.formUnion(await translateMissingDiscoverDescription(id: id, locale: locale))
        case .loadedDiscoverDetails:
            summary.formUnion(await translateLoadedDiscoverDescriptions(locale: locale))
        }
        lastTranslationSummary = summary
        logTranslationRunSummary(summary)
    }

    func storeLoadedDiscoverDetail(
        _ detail: DiscoverSkill,
        locale: Locale = .autoupdatingCurrent,
        persist: Bool = false
    ) async {
        if persist {
            await discoverCache.storeDetail(detail)
        }
        discoverableSkillDetails[detail.id] = await localizeDiscoverSkill(detail, locale: locale)
        guard hasRequestedDescriptionTranslation else { return }
        await translateLoadedDiscoverDetail(detail.id, locale: locale)
    }

    private func applyDiscoverDirectorySnapshot(
        _ snapshot: DiscoverDirectoryCache.Snapshot,
        translateIfRequested: Bool
    ) async {
        discoverableSkills = await localizeDiscoverSkills(snapshot.skills)
        discoverableSkillTotal = snapshot.total
        await mergeCachedDiscoverDetails()
        if translateIfRequested, hasRequestedDescriptionTranslation {
            _ = await translateMissingDiscoverDescriptions()
        }
    }

    private func mergeCachedDiscoverDetails(locale: Locale = .autoupdatingCurrent) async {
        for detail in await discoverCache.allDetails() {
            discoverableSkillDetails[detail.id] = await localizeDiscoverSkill(detail, locale: locale)
        }
    }

    private func localizeSkills(_ input: [Skill], locale: Locale = .autoupdatingCurrent) async -> [Skill] {
        var output: [Skill] = []
        output.reserveCapacity(input.count)
        for var skill in input {
            skill = await localizeSkill(skill, locale: locale)
            output.append(skill)
        }
        return output
    }

    private func localizeSkill(_ skill: Skill, locale: Locale = .autoupdatingCurrent) async -> Skill {
        guard !skill.baseDescription.isEmpty else { return skill }
        var localized = skill
        localized.localizedDescription = await descriptionLocalizer.cachedTranslation(
            skillID: skill.id,
            baseDescription: skill.baseDescription,
            baseDescriptionLocale: skill.baseDescriptionLocale,
            locale: locale
        )
        return localized
    }

    private func localizeDiscoverSkills(_ input: [DiscoverSkill], locale: Locale = .autoupdatingCurrent) async -> [DiscoverSkill] {
        var output: [DiscoverSkill] = []
        output.reserveCapacity(input.count)
        for var skill in input {
            skill = await localizeDiscoverSkill(skill, locale: locale)
            output.append(skill)
        }
        return output
    }

    private func localizeDiscoverSkill(_ skill: DiscoverSkill, locale: Locale = .autoupdatingCurrent) async -> DiscoverSkill {
        guard let baseDescription = skill.baseDescription, !baseDescription.isEmpty else { return skill }
        var localized = skill
        localized.localizedDescription = await descriptionLocalizer.cachedTranslation(
            skillID: skill.id,
            baseDescription: baseDescription,
            baseDescriptionLocale: skill.baseDescriptionLocale,
            locale: locale
        )
        return localized
    }

    private func translateMissingSkillDescriptions(locale: Locale = .autoupdatingCurrent) async -> DescriptionTranslationSummary {
        let config = AppSettings.currentLLMConfig()
        var summary = DescriptionTranslationSummary()
        for index in skills.indices {
            guard skills[index].localizedDescription == nil else {
                summary.recordSkip(.alreadyTranslated)
                continue
            }
            guard !skills[index].baseDescription.isEmpty else {
                summary.recordSkip(.missingBaseDescription)
                continue
            }
            let attempt = await descriptionLocalizer.translationAttempt(
                skillID: skills[index].id,
                baseDescription: skills[index].baseDescription,
                baseDescriptionLocale: skills[index].baseDescriptionLocale,
                locale: locale,
                config: config
            )
            switch attempt {
            case .translated(let translated):
                skills[index].localizedDescription = translated == skills[index].baseDescription ? nil : translated
                if skills[index].localizedDescription == nil {
                    summary.recordSkip(.unchanged)
                } else {
                    summary.recordTranslation()
                }
            case .skipped(let reason):
                summary.recordSkip(reason)
            case .failed(let reason):
                summary.recordFailure(reason)
                logTranslationFailure(kind: "skill", skillID: skills[index].id, reason: reason)
                return summary
            }
        }
        return summary
    }

    private func translateMissingSkillDescription(id: String, locale: Locale = .autoupdatingCurrent) async -> DescriptionTranslationSummary {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return DescriptionTranslationSummary() }
        let config = AppSettings.currentLLMConfig()
        var summary = DescriptionTranslationSummary()
        await translateSkillDescription(at: index, locale: locale, config: config, summary: &summary)
        return summary
    }

    private func translateSkillDescription(
        at index: Array<Skill>.Index,
        locale: Locale,
        config: LLMConfig,
        summary: inout DescriptionTranslationSummary
    ) async {
        guard skills[index].localizedDescription == nil else {
            summary.recordSkip(.alreadyTranslated)
            return
        }
        guard !skills[index].baseDescription.isEmpty else {
            summary.recordSkip(.missingBaseDescription)
            return
        }
        let attempt = await descriptionLocalizer.translationAttempt(
            skillID: skills[index].id,
            baseDescription: skills[index].baseDescription,
            baseDescriptionLocale: skills[index].baseDescriptionLocale,
            locale: locale,
            config: config
        )
        switch attempt {
        case .translated(let translated):
            skills[index].localizedDescription = translated == skills[index].baseDescription ? nil : translated
            if skills[index].localizedDescription == nil {
                summary.recordSkip(.unchanged)
            } else {
                summary.recordTranslation()
            }
        case .skipped(let reason):
            summary.recordSkip(reason)
        case .failed(let reason):
            summary.recordFailure(reason)
            logTranslationFailure(kind: "skill", skillID: skills[index].id, reason: reason)
        }
    }

    private func translateMissingProjectDescriptions(locale: Locale = .autoupdatingCurrent) async -> DescriptionTranslationSummary {
        let config = AppSettings.currentLLMConfig()
        var summary = DescriptionTranslationSummary()
        for index in projectSkills.indices {
            guard projectSkills[index].localizedDescription == nil else {
                summary.recordSkip(.alreadyTranslated)
                continue
            }
            guard !projectSkills[index].baseDescription.isEmpty else {
                summary.recordSkip(.missingBaseDescription)
                continue
            }
            let attempt = await descriptionLocalizer.translationAttempt(
                skillID: projectSkills[index].id,
                baseDescription: projectSkills[index].baseDescription,
                baseDescriptionLocale: projectSkills[index].baseDescriptionLocale,
                locale: locale,
                config: config
            )
            switch attempt {
            case .translated(let translated):
                projectSkills[index].localizedDescription = translated == projectSkills[index].baseDescription ? nil : translated
                if projectSkills[index].localizedDescription == nil {
                    summary.recordSkip(.unchanged)
                } else {
                    summary.recordTranslation()
                }
            case .skipped(let reason):
                summary.recordSkip(reason)
            case .failed(let reason):
                summary.recordFailure(reason)
                logTranslationFailure(kind: "project", skillID: projectSkills[index].id, reason: reason)
                return summary
            }
        }
        return summary
    }

    private func translateMissingProjectDescription(id: String, locale: Locale = .autoupdatingCurrent) async -> DescriptionTranslationSummary {
        guard let index = projectSkills.firstIndex(where: { $0.id == id }) else { return DescriptionTranslationSummary() }
        let config = AppSettings.currentLLMConfig()
        var summary = DescriptionTranslationSummary()
        await translateProjectDescription(at: index, locale: locale, config: config, summary: &summary)
        return summary
    }

    private func translateProjectDescription(
        at index: Array<Skill>.Index,
        locale: Locale,
        config: LLMConfig,
        summary: inout DescriptionTranslationSummary
    ) async {
        guard projectSkills[index].localizedDescription == nil else {
            summary.recordSkip(.alreadyTranslated)
            return
        }
        guard !projectSkills[index].baseDescription.isEmpty else {
            summary.recordSkip(.missingBaseDescription)
            return
        }
        let attempt = await descriptionLocalizer.translationAttempt(
            skillID: projectSkills[index].id,
            baseDescription: projectSkills[index].baseDescription,
            baseDescriptionLocale: projectSkills[index].baseDescriptionLocale,
            locale: locale,
            config: config
        )
        switch attempt {
        case .translated(let translated):
            projectSkills[index].localizedDescription = translated == projectSkills[index].baseDescription ? nil : translated
            if projectSkills[index].localizedDescription == nil {
                summary.recordSkip(.unchanged)
            } else {
                summary.recordTranslation()
            }
        case .skipped(let reason):
            summary.recordSkip(reason)
        case .failed(let reason):
            summary.recordFailure(reason)
            logTranslationFailure(kind: "project", skillID: projectSkills[index].id, reason: reason)
        }
    }

    private func translateMissingDiscoverDescriptions(locale: Locale = .autoupdatingCurrent) async -> DescriptionTranslationSummary {
        let config = AppSettings.currentLLMConfig()
        var summary = DescriptionTranslationSummary()

        for index in discoverableSkills.indices {
            guard discoverableSkills[index].localizedDescription == nil else {
                summary.recordSkip(.alreadyTranslated)
                continue
            }
            guard let baseDescription = discoverableSkills[index].baseDescription, !baseDescription.isEmpty else {
                if discoverableSkillDetails[discoverableSkills[index].id] == nil {
                    summary.recordDeferred(.summaryNotLoaded)
                }
                continue
            }
            let attempt = await descriptionLocalizer.translationAttempt(
                skillID: discoverableSkills[index].id,
                baseDescription: baseDescription,
                baseDescriptionLocale: discoverableSkills[index].baseDescriptionLocale,
                locale: locale,
                config: config
            )
            switch attempt {
            case .translated(let translated):
                discoverableSkills[index].localizedDescription = translated == baseDescription ? nil : translated
                if discoverableSkills[index].localizedDescription == nil {
                    summary.recordSkip(.unchanged)
                } else {
                    summary.recordTranslation()
                }
            case .skipped(let reason):
                summary.recordSkip(reason)
            case .failed(let reason):
                summary.recordFailure(reason)
                logTranslationFailure(kind: "discover", skillID: discoverableSkills[index].id, reason: reason)
                return summary
            }
        }

        for key in discoverableSkillDetails.keys.sorted() {
            guard var detail = discoverableSkillDetails[key] else { continue }
            guard detail.localizedDescription == nil else {
                summary.recordSkip(.alreadyTranslated)
                continue
            }
            guard let baseDescription = detail.baseDescription, !baseDescription.isEmpty else {
                summary.recordSkip(.missingBaseDescription)
                continue
            }
            let attempt = await descriptionLocalizer.translationAttempt(
                skillID: detail.id,
                baseDescription: baseDescription,
                baseDescriptionLocale: detail.baseDescriptionLocale,
                locale: locale,
                config: config
            )
            switch attempt {
            case .translated(let translated):
                detail.localizedDescription = translated == baseDescription ? nil : translated
                discoverableSkillDetails[key] = detail
                if detail.localizedDescription == nil {
                    summary.recordSkip(.unchanged)
                } else {
                    summary.recordTranslation()
                }
            case .skipped(let reason):
                summary.recordSkip(reason)
            case .failed(let reason):
                summary.recordFailure(reason)
                logTranslationFailure(kind: "discover-detail", skillID: detail.id, reason: reason)
                return summary
            }
        }
        return summary
    }

    private func translateDiscoverListDescription(
        at index: Array<DiscoverSkill>.Index,
        locale: Locale,
        config: LLMConfig,
        summary: inout DescriptionTranslationSummary
    ) async {
        guard discoverableSkills[index].localizedDescription == nil else {
            summary.recordSkip(.alreadyTranslated)
            return
        }
        guard let baseDescription = discoverableSkills[index].baseDescription, !baseDescription.isEmpty else {
            if discoverableSkillDetails[discoverableSkills[index].id] == nil {
                summary.recordDeferred(.summaryNotLoaded)
            }
            return
        }
        let attempt = await descriptionLocalizer.translationAttempt(
            skillID: discoverableSkills[index].id,
            baseDescription: baseDescription,
            baseDescriptionLocale: discoverableSkills[index].baseDescriptionLocale,
            locale: locale,
            config: config
        )
        switch attempt {
        case .translated(let translated):
            discoverableSkills[index].localizedDescription = translated == baseDescription ? nil : translated
            if discoverableSkills[index].localizedDescription == nil {
                summary.recordSkip(.unchanged)
            } else {
                summary.recordTranslation()
            }
        case .skipped(let reason):
            summary.recordSkip(reason)
        case .failed(let reason):
            summary.recordFailure(reason)
            logTranslationFailure(kind: "discover", skillID: discoverableSkills[index].id, reason: reason)
        }
    }

    private func translateMissingDiscoverDescription(id: String, locale: Locale = .autoupdatingCurrent) async -> DescriptionTranslationSummary {
        let config = AppSettings.currentLLMConfig()
        var summary = DescriptionTranslationSummary()

        if let key = discoverableSkillDetails.keys.first(where: { $0 == id }) {
            await translateDiscoverDetailDescription(key: key, locale: locale, config: config, summary: &summary)
            return summary
        }

        if let index = discoverableSkills.firstIndex(where: { $0.id == id }) {
            await translateDiscoverListDescription(at: index, locale: locale, config: config, summary: &summary)
        }
        return summary
    }

    private func translateDiscoverDetailDescription(
        key: String,
        locale: Locale,
        config: LLMConfig,
        summary: inout DescriptionTranslationSummary
    ) async {
        guard var detail = discoverableSkillDetails[key] else { return }
        guard detail.localizedDescription == nil else {
            summary.recordSkip(.alreadyTranslated)
            return
        }
        guard let baseDescription = detail.baseDescription, !baseDescription.isEmpty else {
            summary.recordSkip(.missingBaseDescription)
            return
        }
        let attempt = await descriptionLocalizer.translationAttempt(
            skillID: detail.id,
            baseDescription: baseDescription,
            baseDescriptionLocale: detail.baseDescriptionLocale,
            locale: locale,
            config: config
        )
        switch attempt {
        case .translated(let translated):
            detail.localizedDescription = translated == baseDescription ? nil : translated
            discoverableSkillDetails[key] = detail
            if detail.localizedDescription == nil {
                summary.recordSkip(.unchanged)
            } else {
                summary.recordTranslation()
            }
        case .skipped(let reason):
            summary.recordSkip(reason)
        case .failed(let reason):
            summary.recordFailure(reason)
            logTranslationFailure(kind: "discover-detail", skillID: detail.id, reason: reason)
        }
    }

    private func translateLoadedDiscoverDescriptions(locale: Locale = .autoupdatingCurrent) async -> DescriptionTranslationSummary {
        let config = AppSettings.currentLLMConfig()
        var summary = DescriptionTranslationSummary()
        for key in discoverableSkillDetails.keys.sorted() {
            await translateDiscoverDetailDescription(key: key, locale: locale, config: config, summary: &summary)
            if summary.failed > 0 { return summary }
        }
        return summary
    }

    private func translateLoadedDiscoverDetail(_ skillID: String, locale: Locale = .autoupdatingCurrent) async {
        guard var detail = discoverableSkillDetails[skillID] else { return }
        guard detail.localizedDescription == nil else { return }
        guard let baseDescription = detail.baseDescription, !baseDescription.isEmpty else { return }

        let config = AppSettings.currentLLMConfig()
        let attempt = await descriptionLocalizer.translationAttempt(
            skillID: detail.id,
            baseDescription: baseDescription,
            baseDescriptionLocale: detail.baseDescriptionLocale,
            locale: locale,
            config: config
        )
        if case .failed(let reason) = attempt {
            logTranslationFailure(kind: "discover-detail", skillID: detail.id, reason: reason)
        }
        guard case .translated(let translated) = attempt else { return }
        detail.localizedDescription = translated == baseDescription ? nil : translated
        discoverableSkillDetails[skillID] = detail
    }

    private func logTranslationRunStart(locale: Locale, config: LLMConfig) {
        translationDebugLogger(
            "[DescriptionTranslation] start locale=\(locale.identifier) provider=\(config.provider.rawValue) model=\(config.model)"
        )
    }

    private func logTranslationRunSummary(_ summary: DescriptionTranslationSummary) {
        translationDebugLogger("[DescriptionTranslation] summary \(summary.toolbarText)")
    }

    private func logTranslationFailure(kind: String, skillID: String, reason: DescriptionTranslationFailureReason) {
        translationDebugLogger(
            "[DescriptionTranslation] failed kind=\(kind) id=\(skillID) reason=\(reason.summaryLabel)"
        )
    }

    // MARK: - Collection mount status

    func mountStatus(collectionID: UUID, agentID: String) -> MountStatus {
        mountStatuses["\(collectionID.uuidString):\(agentID)"] ?? .unmounted
    }

    func mountReport(collectionID: UUID, agentID: String) -> MountReport? {
        mountReports["\(collectionID.uuidString):\(agentID)"]
    }

    func recordMountReport(_ report: MountReport, collectionID: UUID, agentID: String) {
        mountReports["\(collectionID.uuidString):\(agentID)"] = report
    }

    /// 以磁盘为准重建所有「组 × agent」的状态灯数据。skills 刷新或分组变更后调用。
    func refreshMountStatuses(collections: [CollectionRecord]) {
        var map: [String: MountStatus] = [:]
        var reports = mountReports.filter { key, _ in
            !collections.contains { collection in
                collection.mountedAgentIDs.contains { key == "\(collection.id.uuidString):\($0)" }
            }
        }
        for collection in collections {
            let resolution = CollectionSupport.resolveMemberIDs(collection.memberSkillIDs, skills: skills)
            for agentID in Set(collection.mountedAgentIDs) {
                guard let definition = AgentRegistry.agent(id: agentID) else { continue }
                let probe = ActivationService.probeMount(
                    memberSkills: resolution.members,
                    missingMemberIDs: resolution.missingIDs,
                    agentSkillsDir: AgentRegistry.resolvedSkillsDir(for: definition)
                )
                let key = "\(collection.id.uuidString):\(agentID)"
                map[key] = ActivationService.status(
                    intentMounted: true,
                    linkedCount: probe.linkedCount,
                    memberCount: collection.memberSkillIDs.count
                )
                reports[key] = probe.report.skipped.isEmpty ? nil : probe.report
            }
        }
        mountStatuses = map
        mountReports = reports
    }
}

protocol DescriptionLocalizing: Actor {
    func cachedTranslation(
        skillID: String,
        baseDescription: String,
        baseDescriptionLocale: String,
        locale: Locale
    ) async -> String?

    func translationAttempt(
        skillID: String,
        baseDescription: String,
        baseDescriptionLocale: String,
        locale: Locale,
        config: LLMConfig
    ) async -> DescriptionTranslationAttempt
}

actor DescriptionLocalizationService: DescriptionLocalizing {
    private struct ProviderCooldownState {
        let retryAfter: Date
    }

    private let llmService: LLMService
    private let cache: DescriptionTranslationCache
    private var inflight: [String: Task<DescriptionTranslationAttempt, Never>] = [:]
    private var providerCooldowns: [String: ProviderCooldownState] = [:]

    init(
        llmService: LLMService = LLMService(),
        cache: DescriptionTranslationCache = DescriptionTranslationCache()
    ) {
        self.llmService = llmService
        self.cache = cache
    }

    func cachedTranslation(
        skillID: String,
        baseDescription: String,
        baseDescriptionLocale: String,
        locale: Locale = .autoupdatingCurrent
    ) async -> String? {
        let targetLocale = AppSettings.currentDescriptionLocale(locale: locale)
        guard shouldTranslate(baseDescriptionLocale: baseDescriptionLocale, targetLocale: targetLocale) else {
            return nil
        }
        return await cache.translation(
            skillID: skillID,
            sourceText: baseDescription,
            sourceLocale: baseDescriptionLocale,
            targetLocale: targetLocale
        )
    }

    func translationAttempt(
        skillID: String,
        baseDescription: String,
        baseDescriptionLocale: String,
        locale: Locale = .autoupdatingCurrent,
        config: LLMConfig
    ) async -> DescriptionTranslationAttempt {
        let targetLocale = AppSettings.currentDescriptionLocale(locale: locale)
        guard shouldTranslate(baseDescriptionLocale: baseDescriptionLocale, targetLocale: targetLocale) else {
            return .skipped(.samePrimaryLanguage)
        }
        if let failure = await preflightFailureReason(for: config) {
            return .failed(failure)
        }

        let key = DescriptionTranslationCache.cacheKey(
            skillID: skillID,
            sourceText: baseDescription,
            sourceLocale: baseDescriptionLocale,
            targetLocale: targetLocale
        )
        if let cached = await cache.translation(
            skillID: skillID,
            sourceText: baseDescription,
            sourceLocale: baseDescriptionLocale,
            targetLocale: targetLocale
        ) {
            return .translated(cached)
        }
        if let task = inflight[key] {
            return await task.value
        }

        let task = Task<DescriptionTranslationAttempt, Never> {
            do {
                let translated = try await llmService.translateDescription(
                    baseDescription,
                    from: baseDescriptionLocale,
                    to: targetLocale,
                    config: config
                )
                let finalText = translated.isEmpty ? baseDescription : translated
                await cache.store(
                    skillID: skillID,
                    sourceText: baseDescription,
                    sourceLocale: baseDescriptionLocale,
                    targetLocale: targetLocale,
                    translatedText: finalText
                )
                clearCooldown(for: config)
                return .translated(finalText)
            } catch {
                registerFailure(for: config)
                return .failed(Self.failureReason(for: error))
            }
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }

    private func shouldTranslate(baseDescriptionLocale: String, targetLocale: String) -> Bool {
        DescriptionLocale.shouldTranslate(sourceLocale: baseDescriptionLocale, targetLocale: targetLocale)
    }

    private func preflightFailureReason(for config: LLMConfig) async -> DescriptionTranslationFailureReason? {
        guard config.provider == .ollama || config.provider == .lmStudio else {
            return nil
        }

        let cooldownKey = providerCooldownKey(for: config)
        let now = Date()
        if let cooldown = providerCooldowns[cooldownKey], cooldown.retryAfter > now {
            return .providerCooldown
        }

        let reachable = await llmService.isServiceReachable(config: config)
        guard reachable else {
            providerCooldowns[cooldownKey] = ProviderCooldownState(
                retryAfter: now.addingTimeInterval(45)
            )
            return .serviceUnavailable
        }

        let modelAvailable = await llmService.isLocalModelAvailable(config: config)
        if modelAvailable {
            providerCooldowns[cooldownKey] = nil
            return nil
        }

        providerCooldowns[cooldownKey] = ProviderCooldownState(
            retryAfter: now.addingTimeInterval(45)
        )
        return .modelUnavailable
    }

    private static func failureReason(for error: Error) -> DescriptionTranslationFailureReason {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .requestTimedOut
        }
        return .requestFailed
    }

    private func registerFailure(for config: LLMConfig) {
        guard config.provider == .ollama || config.provider == .lmStudio else { return }
        providerCooldowns[providerCooldownKey(for: config)] = ProviderCooldownState(
            retryAfter: Date().addingTimeInterval(45)
        )
    }

    private func clearCooldown(for config: LLMConfig) {
        providerCooldowns[providerCooldownKey(for: config)] = nil
    }

    private func providerCooldownKey(for config: LLMConfig) -> String {
        "\(config.provider.rawValue)|\(config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

actor DescriptionTranslationCache {
    static let translatorVersion = "description-v2"

    struct Catalog: Sendable {
        let entries: [String: String]

        struct File: Decodable {
            var version: String?
            var generatedAt: String?
            var locales: [String]?
            var entries: [String: String]
        }

        static let bundled = Catalog.loadBundled()

        func translation(for key: String) -> String? {
            entries[key]
        }

        static func load(from url: URL) -> Catalog {
            guard let data = try? Data(contentsOf: url) else {
                return Catalog(entries: [:])
            }

            let decoder = JSONDecoder()
            if let file = try? decoder.decode(File.self, from: data),
               file.version == nil || file.version == DescriptionTranslationCache.translatorVersion {
                return Catalog(entries: file.entries)
            }

            if let entries = try? decoder.decode([String: String].self, from: data) {
                return Catalog(entries: entries)
            }

            return Catalog(entries: [:])
        }

        private static func loadBundled() -> Catalog {
            let candidateURLs = resourceBundles.compactMap {
                $0.url(forResource: "description-translations", withExtension: "json")
            }
            for url in candidateURLs {
                let catalog = load(from: url)
                if !catalog.entries.isEmpty {
                    return catalog
                }
            }
            return Catalog(entries: [:])
        }

        private static var resourceBundles: [Bundle] {
            return [Bundle.main]
        }
    }

    struct CacheFile: Codable {
        var entries: [String: Entry]
    }

    struct Entry: Codable {
        var skillID: String
        var sourceTextHash: String
        var sourceLocale: String?
        var targetLocale: String
        var translatedText: String
        var translatorVersion: String
        var createdAt: Date
        var lastAccessedAt: Date
    }

    private let fileURL: URL
    private let catalog: Catalog
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedFile: CacheFile?

    init(fileURL: URL? = nil, catalog: Catalog = .bundled) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.fileURL = fileURL ?? home
            .appendingPathComponent(".skills-manager/cache/description-translations.json")
        self.catalog = catalog
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func translation(skillID: String, sourceText: String, sourceLocale: String, targetLocale: String) async -> String? {
        let key = Self.cacheKey(
            skillID: skillID,
            sourceText: sourceText,
            sourceLocale: sourceLocale,
            targetLocale: targetLocale
        )
        if let bundled = catalog.translation(for: key) {
            return bundled
        }
        var file = loadCacheFile()
        guard var entry = file.entries[key] else { return nil }
        guard entry.translatorVersion == Self.translatorVersion else { return nil }
        entry.lastAccessedAt = Date()
        file.entries[key] = entry
        cachedFile = file
        persist(file)
        return entry.translatedText
    }

    func store(skillID: String, sourceText: String, sourceLocale: String, targetLocale: String, translatedText: String) async {
        var file = loadCacheFile()
        let key = Self.cacheKey(
            skillID: skillID,
            sourceText: sourceText,
            sourceLocale: sourceLocale,
            targetLocale: targetLocale
        )
        let now = Date()
        file.entries[key] = Entry(
            skillID: skillID,
            sourceTextHash: Self.sourceTextHash(sourceText),
            sourceLocale: Self.normalizedLocale(sourceLocale),
            targetLocale: Self.normalizedLocale(targetLocale),
            translatedText: translatedText,
            translatorVersion: Self.translatorVersion,
            createdAt: file.entries[key]?.createdAt ?? now,
            lastAccessedAt: now
        )
        cachedFile = file
        persist(file)
    }

    private func loadCacheFile() -> CacheFile {
        if let cachedFile {
            return cachedFile
        }
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? decoder.decode(CacheFile.self, from: data)
        else {
            let empty = CacheFile(entries: [:])
            cachedFile = empty
            return empty
        }
        cachedFile = decoded
        return decoded
    }

    private func persist(_ file: CacheFile) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Best-effort cache writes only.
        }
    }

    static func cacheKey(skillID: String, sourceText: String, sourceLocale: String, targetLocale: String) -> String {
        "\(sourceTextHash(sourceText))|\(normalizedLocale(sourceLocale))|\(normalizedLocale(targetLocale))|\(translatorVersion)"
    }

    static func sourceTextHash(_ sourceText: String) -> String {
        let digest = SHA256.hash(data: Data(sourceText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedLocale(_ locale: String) -> String {
        DescriptionLocale.normalizedIdentifier(locale).lowercased()
    }
}

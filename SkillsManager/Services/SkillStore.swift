import Foundation
import Observation

@Observable
@MainActor
final class SkillStore {

    // MARK: - State

    var skills: [Skill] = []
    var discoverablePlugins: [MarketplacePlugin] = []
    var projectSkills: [Skill] = []
    var currentProjectURL: URL?
    var isLoading = false
    var isLoadingPlugins = false
    var isLoadingProject = false
    var isSyncing = false
    var errorMessage: String?

    // MARK: - Services

    private let claudeAdapter: ClaudeCodeAdapter
    private let universalAdapter: UniversalAdapter
    private let openClawAdapter: OpenClawAdapter
    private let marketplaceService: MarketplaceService
    private let installService: InstallService

    init() {
        let ms = MarketplaceService()
        self.claudeAdapter = ClaudeCodeAdapter()
        self.universalAdapter = UniversalAdapter()
        self.openClawAdapter = OpenClawAdapter()
        self.marketplaceService = ms
        self.installService = InstallService(marketplaceService: ms)
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
            var seen = Set<String>()
            var merged: [Skill] = []
            for skill in claude + universal + openclaw {
                if seen.insert(skill.id).inserted { merged.append(skill) }
            }
            skills = merged
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func merge(records: [SkillRecord]) {
        let lookup = Dictionary(uniqueKeysWithValues: records.map { ($0.skillID, $0) })
        for index in skills.indices {
            let id = skills[index].id
            if let record = lookup[id] {
                skills[index].isStarred = record.isStarred
                skills[index].installState = InstallState(rawValue: record.installState) ?? .notInstalled
            }
        }
    }

    // MARK: - Marketplace plugins

    func reloadDiscoverablePlugins() async {
        isLoadingPlugins = true
        defer { isLoadingPlugins = false }
        let plugins = await marketplaceService.loadAllCachedPlugins()
        guard let installed = try? await marketplaceService.loadInstalledPlugins() else {
            discoverablePlugins = plugins
            return
        }
        discoverablePlugins = await marketplaceService.mergeInstallState(
            plugins: plugins,
            installed: installed
        )
    }

    func syncAndReloadPlugins() async {
        isSyncing = true
        defer { isSyncing = false }
        await marketplaceService.syncAllMarketplaces()
        await reloadDiscoverablePlugins()
    }

    func install(plugin: MarketplacePlugin) async {
        do {
            try await installService.install(plugin: plugin)
            await reloadDiscoverablePlugins()
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uninstall(plugin: MarketplacePlugin) async {
        do {
            try await installService.uninstall(plugin: plugin)
            await reloadDiscoverablePlugins()
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch plugin skills into memory for sandbox preview without installing.
    func previewPluginSkills(_ plugin: MarketplacePlugin) async -> [Skill] {
        do {
            return try await installService.previewSkills(plugin: plugin)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Skill-level install/uninstall

    /// Marks a skill as installed (trial → keep, or re-install state).
    func installSkill(_ skill: Skill) async {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index].installState = .installed
        }
    }

    /// Deletes the skill from disk and removes it from the list immediately.
    func uninstallSkill(_ skill: Skill) async {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        switch skill.source {
        case .local:
            let skillsBase = home.appendingPathComponent(".claude/skills").standardized
            let target = skill.directoryPath.standardized
            if target.path.hasPrefix(skillsBase.path + "/") {
                do { try fm.removeItem(at: target) } catch { errorMessage = error.localizedDescription }
            } else if skill.canonicalPath != nil {
                do { try SymlinkInstaller.uninstall(skillName: skill.name) } catch { errorMessage = error.localizedDescription }
            }
        case .plugin(let marketplace, let pluginName):
            // Delete the skill's own subdirectory inside the plugin cache.
            // skill.directoryPath is e.g. ~/.claude/plugins/cache/{marketplace}/{plugin}/{version}/skills/{skillName}
            // We only remove that leaf directory — the plugin itself remains usable.
            let cacheBase = home.appendingPathComponent(".claude/plugins/cache").standardized
            let target = skill.directoryPath.standardized
            if target.path.hasPrefix(cacheBase.path + "/\(marketplace)/\(pluginName)/") {
                do { try fm.removeItem(at: target) } catch { errorMessage = error.localizedDescription }
            }
        case .symlinked:
            // Remove the symlink in ~/.claude/skills/ but leave the target intact
            let skillsBase = home.appendingPathComponent(".claude/skills").standardized
            let target = skill.directoryPath.standardized
            if target.path.hasPrefix(skillsBase.path + "/") {
                do { try fm.removeItem(at: target) } catch { errorMessage = error.localizedDescription }
            }
        case .projectLocal:
            // Project-local skills are not managed here; use Promote instead
            return
        }

        // Remove from memory immediately — row disappears without a reload
        skills.removeAll { $0.id == skill.id }
    }

    /// Convenience batch variant used by multi-select.
    func uninstallSkills(_ batch: [Skill]) async {
        for skill in batch { await uninstallSkill(skill) }
    }

    func installSkills(_ batch: [Skill]) async {
        for skill in batch { await installSkill(skill) }
    }

    // MARK: - Install to agents via SymlinkInstaller

    func installSkillToAgents(_ skill: Skill, agentIDs: [String]) async {
        do {
            try SymlinkInstaller.install(
                content: skill.markdownContent,
                skillName: skill.name,
                agentIDs: agentIDs
            )
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Project skills

    func openProject(url: URL) async {
        currentProjectURL = url
        await loadProjectSkills()
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
        projectSkills = results
    }

    /// Copies a project-local skill to ~/.claude/skills/.
    /// Converts .mdc → SKILL.md format if needed.
    func promoteSkill(_ skill: Skill) async {
        // Use displayName (from frontmatter name: field) for a more meaningful directory name.
        // Falls back to skill.name if displayName equals the raw directory name.
        let destDirName = skill.displayName.isEmpty ? skill.name : skill.displayName
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
}

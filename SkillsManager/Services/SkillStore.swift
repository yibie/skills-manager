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

    private let adapter: ClaudeCodeAdapter
    private let cursorAdapter: CursorAdapter
    private let marketplaceService: MarketplaceService
    private let installService: InstallService

    init() {
        let ms = MarketplaceService()
        self.adapter = ClaudeCodeAdapter()
        self.cursorAdapter = CursorAdapter()
        self.marketplaceService = ms
        self.installService = InstallService(marketplaceService: ms)
    }

    // MARK: - Local skills

    func reloadSkills() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let claudeSkills = adapter.scanSkills()
            async let cursorSkills = cursorAdapter.scanSkills()
            let (claude, cursor) = try await (claudeSkills, cursorSkills)
            skills = claude + cursor
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

    // MARK: - Skill-level install/uninstall (state only)

    func installSkill(_ skill: Skill) async {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index].installState = .installed
        }
    }

    func uninstallSkill(_ skill: Skill) async {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index].installState = .notInstalled
        }
    }

    // MARK: - Install to Cursor

    /// Converts the skill to .mdc format and writes it to ~/.cursor/rules/.
    func installToCursor(skill: Skill) async {
        do {
            try cursorAdapter.installSkill(skill)
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

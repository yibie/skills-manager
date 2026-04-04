import Foundation
import Observation

@Observable
@MainActor
final class SkillStore {

    // MARK: - State

    var skills: [Skill] = []
    var discoverablePlugins: [MarketplacePlugin] = []
    var isLoading = false
    var isLoadingPlugins = false
    var errorMessage: String?

    // MARK: - Services

    private let adapter: ClaudeCodeAdapter
    private let marketplaceService: MarketplaceService
    let installService: InstallService

    init() {
        let ms = MarketplaceService()
        self.adapter = ClaudeCodeAdapter()
        self.marketplaceService = ms
        self.installService = InstallService(marketplaceService: ms)
    }

    // MARK: - Local skills

    func reloadSkills() async {
        isLoading = true
        defer { isLoading = false }
        do {
            skills = try await adapter.scanSkills()
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

    // MARK: - Skill-level install/uninstall (state only for Phase 2)

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
}

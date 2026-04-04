import Foundation

actor MarketplaceService {

    private let pluginsBase: URL

    init() {
        pluginsBase = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/plugins")
    }

    private struct KnownMarketplace: Decodable {
        struct Source: Decodable {
            var source: String
            var repo: String?
        }
        var source: Source
        var installLocation: String
    }

    /// Fetches marketplace.json from GitHub for one marketplace and writes it to local cache.
    func syncMarketplace(name: String) async throws {
        // Load known_marketplaces.json to get the repo
        let url = pluginsBase.appending(path: "known_marketplaces.json")
        let data = try Data(contentsOf: url)
        let dict = try JSONDecoder().decode([String: KnownMarketplace].self, from: data)
        guard let marketplace = dict[name], let repo = marketplace.source.repo else {
            throw MarketplaceError.unknownMarketplace(name)
        }

        // Fetch from GitHub Contents API
        let apiURL = URL(string: "https://api.github.com/repos/\(repo)/contents/.claude-plugin/marketplace.json")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        let (apiData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MarketplaceError.fetchFailed(name)
        }

        // GitHub returns base64-encoded content
        let json = try JSONSerialization.jsonObject(with: apiData) as? [String: Any]
        guard let encoded = json?["content"] as? String else {
            throw MarketplaceError.fetchFailed(name)
        }
        let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
        guard let marketplaceData = Data(base64Encoded: cleaned) else {
            throw MarketplaceError.fetchFailed(name)
        }

        // Write to local cache
        let cacheDir = URL(fileURLWithPath: marketplace.installLocation)
            .appending(path: ".claude-plugin")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cachePath = cacheDir.appending(path: "marketplace.json")
        try marketplaceData.write(to: cachePath)
    }

    /// Syncs all known marketplaces that have a github source.
    func syncAllMarketplaces() async {
        guard let names = try? knownMarketplaceNames() else { return }
        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask { try? await self.syncMarketplace(name: name) }
            }
        }
    }

    func knownMarketplaceNames() throws -> [String] {
        let url = pluginsBase.appending(path: "known_marketplaces.json")
        let data = try Data(contentsOf: url)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return Array(dict.keys).sorted()
    }

    func loadCachedPlugins(marketplace: String) throws -> [MarketplacePlugin] {
        let marketplaceDir = pluginsBase
            .appending(path: "marketplaces/\(marketplace)/.claude-plugin/marketplace.json")
        let data = try Data(contentsOf: marketplaceDir)
        return try parseMarketplaceJSON(data: data, marketplace: marketplace)
    }

    func loadAllCachedPlugins() -> [MarketplacePlugin] {
        guard let names = try? knownMarketplaceNames() else { return [] }
        return names.flatMap { name in
            (try? loadCachedPlugins(marketplace: name)) ?? []
        }
    }

    func loadInstalledPlugins() throws -> InstalledPluginsFile {
        let url = pluginsBase.appending(path: "installed_plugins.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(InstalledPluginsFile.self, from: data)
    }

    func mergeInstallState(
        plugins: [MarketplacePlugin],
        installed: InstalledPluginsFile
    ) -> [MarketplacePlugin] {
        return plugins.map { plugin in
            var p = plugin
            let key = "\(plugin.name)@\(plugin.marketplace)"
            if let records = installed.plugins[key], let record = records.first {
                p.isInstalled = true
                p.installedVersion = record.version
            }
            return p
        }
    }

    private func parseMarketplaceJSON(data: Data, marketplace: String) throws -> [MarketplacePlugin] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pluginsArray = root["plugins"] as? [[String: Any]] else { return [] }

        return pluginsArray.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let description = dict["description"] as? String ?? ""
            let category = dict["category"] as? String
            let homepage = (dict["homepage"] as? String).flatMap { URL(string: $0) }
            let sourceType = parseSource(dict["source"])
            return MarketplacePlugin(
                id: "\(marketplace):\(name)",
                name: name,
                description: description,
                marketplace: marketplace,
                category: category,
                homepage: homepage,
                sourceType: sourceType,
                skills: []
            )
        }
    }

    nonisolated private func parseSource(_ raw: Any?) -> PluginSourceType {
        guard let dict = raw as? [String: Any],
              let sourceType = dict["source"] as? String else {
            if let str = raw as? String { return .localPath(str) }
            return .localPath("./")
        }
        switch sourceType {
        case "git-subdir":
            return .gitSubdir(
                url: dict["url"] as? String ?? "",
                path: dict["path"] as? String ?? "",
                ref: dict["ref"] as? String ?? "main",
                sha: dict["sha"] as? String
            )
        case "url":
            return .remoteURL(url: dict["url"] as? String ?? "", sha: dict["sha"] as? String)
        default:
            return .gitURL(url: dict["url"] as? String ?? "", sha: dict["sha"] as? String)
        }
    }
}

enum MarketplaceError: LocalizedError {
    case unknownMarketplace(String)
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownMarketplace(let name): "Unknown marketplace: \(name)"
        case .fetchFailed(let name): "Failed to fetch marketplace: \(name)"
        }
    }
}

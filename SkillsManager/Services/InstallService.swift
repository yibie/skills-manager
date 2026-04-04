import Foundation

actor InstallService {

    private let pluginsBase: URL
    private let marketplaceService: MarketplaceService

    init(marketplaceService: MarketplaceService) {
        self.pluginsBase = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/plugins")
        self.marketplaceService = marketplaceService
    }

    func install(plugin: MarketplacePlugin) async throws {
        switch plugin.sourceType {
        case .localPath(let relativePath):
            try installFromLocalCache(plugin: plugin, relativePath: relativePath)
        case .gitURL(let url, _), .remoteURL(let url, _):
            try await installFromGit(plugin: plugin, repoURL: url, subpath: nil)
        case .gitSubdir(let url, let path, let ref, _):
            try await installFromGit(plugin: plugin, repoURL: url, subpath: path, ref: ref)
        }
        try updateInstalledRecord(plugin: plugin, action: .install)
    }

    func uninstall(plugin: MarketplacePlugin) throws {
        let cacheDir = pluginsBase.appending(path: "cache/\(plugin.marketplace)/\(plugin.name)")
        if FileManager.default.fileExists(atPath: cacheDir.path()) {
            try FileManager.default.removeItem(at: cacheDir)
        }
        try updateInstalledRecord(plugin: plugin, action: .uninstall)
    }

    private func installFromLocalCache(plugin: MarketplacePlugin, relativePath: String) throws {
        let sourceBase = pluginsBase.appending(path: "marketplaces/\(plugin.marketplace)")
        let sourcePath = relativePath.hasPrefix("./")
            ? sourceBase.appending(path: String(relativePath.dropFirst(2)))
            : sourceBase.appending(path: relativePath)
        let version = plugin.installedVersion ?? "local"
        let destDir = pluginsBase.appending(path: "cache/\(plugin.marketplace)/\(plugin.name)/\(version)")
        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(at: sourcePath, includingPropertiesForKeys: nil)
        for item in contents {
            let dest = destDir.appending(path: item.lastPathComponent)
            if fm.fileExists(atPath: dest.path()) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: item, to: dest)
        }
    }

    private func installFromGit(
        plugin: MarketplacePlugin, repoURL: String, subpath: String?, ref: String = "main"
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "skills-manager-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try await runProcess("/usr/bin/git",
            args: ["clone", "--depth=1", "--branch", ref, repoURL, tempDir.path()],
            at: FileManager.default.temporaryDirectory)
        let sourceDir = subpath.map { tempDir.appending(path: $0) } ?? tempDir
        let version = plugin.installedVersion ?? ref
        let destDir = pluginsBase.appending(path: "cache/\(plugin.marketplace)/\(plugin.name)/\(version)")
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let contents = try FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        for item in contents {
            let dest = destDir.appending(path: item.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path()) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: item, to: dest)
        }
    }

    private enum RecordAction { case install, uninstall }

    private func updateInstalledRecord(plugin: MarketplacePlugin, action: RecordAction) throws {
        let url = pluginsBase.appending(path: "installed_plugins.json")
        var file: InstalledPluginsFile
        if let data = try? Data(contentsOf: url) {
            file = (try? JSONDecoder().decode(InstalledPluginsFile.self, from: data))
                ?? InstalledPluginsFile(version: 2, plugins: [:])
        } else {
            file = InstalledPluginsFile(version: 2, plugins: [:])
        }
        let key = "\(plugin.name)@\(plugin.marketplace)"
        switch action {
        case .install:
            let version = plugin.installedVersion ?? "local"
            let installPath = pluginsBase
                .appending(path: "cache/\(plugin.marketplace)/\(plugin.name)/\(version)").path()
            let now = ISO8601DateFormatter().string(from: Date())
            file.plugins[key] = [InstalledPluginRecord(
                scope: "user", installPath: installPath, version: version,
                installedAt: now, lastUpdated: now, gitCommitSha: nil)]
        case .uninstall:
            file.plugins.removeValue(forKey: key)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url)
    }

    private func runProcess(_ exec: String, args: [String], at dir: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: exec)
            process.arguments = args
            process.currentDirectoryURL = dir
            process.standardError = errPipe
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let msg = String(
                        data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8
                    ) ?? ""
                    continuation.resume(throwing: InstallError.processFailed(exec, msg))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum InstallError: LocalizedError {
    case processFailed(String, String)
    case sourceNotSupported(String)
    var errorDescription: String? {
        switch self {
        case .processFailed(let cmd, let msg): "Process failed: \(cmd)\n\(msg)"
        case .sourceNotSupported(let type): "Install source not supported: \(type)"
        }
    }
}

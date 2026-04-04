import Foundation

/// 从 marketplace.json 解析的可安装 plugin
struct MarketplacePlugin: Identifiable, Sendable {
    let id: String               // "{marketplace}:{name}"
    var name: String
    var description: String
    var marketplace: String      // marketplace 名称，如 "claude-plugins-official"
    var category: String?
    var homepage: URL?
    var sourceType: PluginSourceType
    var skills: [String]         // 安装后包含的 skill 名称（从 plugin 目录扫描）
    var isInstalled: Bool = false
    var installedVersion: String?
}

enum PluginSourceType: Sendable {
    case localPath(String)       // source = "./" 相对路径
    case gitURL(url: String, sha: String?)
    case gitSubdir(url: String, path: String, ref: String, sha: String?)
    case remoteURL(url: String, sha: String?)
}

/// installed_plugins.json 中的一条安装记录
struct InstalledPluginRecord: Codable, Sendable {
    var scope: String
    var installPath: String
    var version: String
    var installedAt: String
    var lastUpdated: String
    var gitCommitSha: String?
}

/// installed_plugins.json 整体结构
struct InstalledPluginsFile: Codable, Sendable {
    var version: Int
    var plugins: [String: [InstalledPluginRecord]]
}

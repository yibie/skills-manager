import Foundation

// MARK: - Adapter Spec 目录发现(M3)
// 供 UI 枚举"可用平台列表":给定一个 specs 目录,列出其中的 *.yaml spec 并
// 读出平台元信息。解析失败的文件不隐藏——以 loadError 形式如实上报,由 UI 呈现。
// 只读:不创建、不修改任何文件。

/// specs 目录中发现的一个 spec 文件条目。
public struct SpecCatalogEntry: Identifiable, Sendable, Hashable {
    /// spec 文件绝对路径(即 id)
    public let url: URL
    /// 平台 id(解析失败时为 nil)
    public let platformID: String?
    /// 平台显示名(解析失败时为 nil)
    public let platformName: String?
    /// 无法解析为 AdapterSpec 时的错误描述(诚实上报,不静默跳过)
    public let loadError: String?

    public var id: String { url.path }

    /// UI 展示名:平台名优先,坏文件退回文件名。
    public var displayName: String { platformName ?? url.lastPathComponent }

    public init(url: URL, platformID: String?, platformName: String?, loadError: String?) {
        self.url = url
        self.platformID = platformID
        self.platformName = platformName
        self.loadError = loadError
    }
}

public enum SpecCatalog {
    /// 随库打包的 specs 目录(platform-specs/ 的资源副本,脱离仓库亦可用)。
    /// 与仓库源文件的同步由 BundledSpecsTests 看护。
    public static var bundledSpecsDirectory: URL? {
        Bundle.module.url(forResource: "platform-specs", withExtension: nil)
    }

    /// 枚举目录内的 *.yaml / *.yml spec,按文件名排序。
    /// 目录不可读时返回空列表(存在性判断交给调用方)。
    public static func discover(in directory: URL) -> [SpecCatalogEntry] {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return children.sorted().filter { name in
            name.hasSuffix(".yaml") || name.hasSuffix(".yml")
        }.map { name in
            let url = directory.appendingPathComponent(name).standardizedFileURL
            do {
                let spec = try SpecLoader.loadTyped(fileURL: url)
                return SpecCatalogEntry(
                    url: url,
                    platformID: spec.platform.id,
                    platformName: spec.platform.name,
                    loadError: nil
                )
            } catch {
                return SpecCatalogEntry(
                    url: url,
                    platformID: nil,
                    platformName: nil,
                    loadError: String(describing: error)
                )
            }
        }
    }

    /// 解析某 specs 目录应使用的 schema.json:优先同目录,缺席时退回内置副本。
    public static func schemaURL(for directory: URL) -> URL? {
        let sibling = directory.appendingPathComponent("schema.json")
        if FileManager.default.fileExists(atPath: sibling.path) {
            return sibling
        }
        return bundledSpecsDirectory?.appendingPathComponent("schema.json")
    }
}

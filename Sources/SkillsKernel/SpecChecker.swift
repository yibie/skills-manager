import Foundation

// MARK: - 检查报告模型

/// runtime-config 浅计数结果。
public struct CountResult: Equatable, Sendable {
    public let value: Int
    public let unit: String
}

/// 单条 resource 规则的核对结果。
public struct ResourceCheckResult: Sendable {
    public enum Status: Equatable, Sendable {
        /// 路径存在;glob 时 matches 为匹配到的路径列表
        case present(matches: [String])
        case missing
    }

    public let resource: SpecResource
    /// 展开后的绝对路径(glob 为字面前缀基准目录)
    public let resolvedPath: String
    public let status: Status
    public let count: CountResult?

    public var isPresent: Bool {
        if case .present = status { return true }
        return false
    }
}

/// spec 未建模的可疑条目。
public struct UnmodeledEntry: Sendable {
    public let path: String
    public let root: String
}

/// `skm check` 的完整结果:spec(先验)对照文件系统(后验)。
public struct CheckReport: Sendable {
    public let platformID: String
    public let platformName: String
    public let projectPath: String
    public let resources: [ResourceCheckResult]
    public let unmodeled: [UnmodeledEntry]

    public var presentCount: Int { resources.filter(\.isPresent).count }
    public var missingCount: Int { resources.count - presentCount }
    public var requiredMissing: [ResourceCheckResult] {
        resources.filter { !$0.isPresent && $0.resource.isRequired }
    }
}

// MARK: - 检查器

/// 按 adapter spec 扫描文件系统,报告 present/missing 与 [unmodeled]。
/// 只读:不创建、不修改任何文件。home 可注入,便于用 fixture 目录树测试。
public struct SpecChecker {
    private let spec: AdapterSpec
    private let projectRoot: URL
    private let home: URL
    private let fileManager: FileManager

    public init(
        spec: AdapterSpec,
        projectRoot: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.spec = spec
        self.projectRoot = projectRoot.standardizedFileURL
        self.home = home.standardizedFileURL
        self.fileManager = fileManager
    }

    public func run() -> CheckReport {
        let results = spec.resources.map(check(resource:))
        let unmodeled = scanUnmodeled(resourceResults: results)
        return CheckReport(
            platformID: spec.platform.id,
            platformName: spec.platform.name,
            projectPath: projectRoot.path,
            resources: results,
            unmodeled: unmodeled
        )
    }

    // MARK: 路径展开

    /// 把 spec 中的路径(~ / 绝对 / 项目相对)展开为绝对 URL。
    private func resolve(_ path: String) -> URL {
        if path == "~" {
            return home
        }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2)))
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return projectRoot.appendingPathComponent(path)
    }

    // MARK: 单条 resource 核对

    private func check(resource: SpecResource) -> ResourceCheckResult {
        switch resource.pathKind {
        case .file, .directory:
            let url = resolve(resource.path)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let kindMatches = resource.pathKind == .directory
                ? isDirectory.boolValue
                : !isDirectory.boolValue
            let present = exists && kindMatches
            return ResourceCheckResult(
                resource: resource,
                resolvedPath: url.path,
                status: present ? .present(matches: [url.path]) : .missing,
                count: present ? computeCount(for: resource, at: url) : nil
            )
        case .glob:
            let (prefix, rest) = Glob.splitLiteralPrefix(pattern: resource.path)
            let baseURL: URL
            if let first = prefix.first, first.hasPrefix("~") || resource.path.hasPrefix("/") {
                baseURL = resolve(prefix.joined(separator: "/"))
            } else if prefix.isEmpty {
                baseURL = projectRoot
            } else {
                baseURL = resolve(prefix.joined(separator: "/"))
            }
            var matches = Glob.expand(
                baseDir: baseURL,
                patternParts: rest,
                fileManager: fileManager
            )
            // directory scope 表示"项目内子目录":排除项目根本身的命中,
            // 避免与单独建模的项目根规则(如 project-claude-md)重复报告。
            if resource.scope == .directory {
                matches = matches.filter { $0.contains("/") }
            }
            let absolute = matches.map { baseURL.appendingPathComponent($0).path }
            return ResourceCheckResult(
                resource: resource,
                resolvedPath: baseURL.path + "/" + rest.joined(separator: "/"),
                status: absolute.isEmpty ? .missing : .present(matches: absolute),
                count: nil
            )
        }
    }

    // MARK: 浅计数

    private func computeCount(for resource: SpecResource, at url: URL) -> CountResult? {
        guard let countSpec = resource.count else { return nil }
        switch countSpec.method {
        case .jsonKeys:
            guard let pointer = countSpec.pointer,
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONValue.fromJSON(data)
            else { return CountResult(value: 0, unit: countSpec.unit) }
            let target = json.value(atPointer: pointer)
            let value: Int
            switch target {
            case .object(let dict): value = dict.count
            case .array(let items): value = items.count
            default: value = 0
            }
            return CountResult(value: value, unit: countSpec.unit)
        case .entries:
            let children = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
            let visible = children.filter { !$0.hasPrefix(".") }
            return CountResult(value: visible.count, unit: countSpec.unit)
        case .files:
            guard let pattern = countSpec.filePattern else { return nil }
            let parts = pattern.split(separator: "/").map(String.init)
            let matches = Glob.expand(baseDir: url, patternParts: parts, fileManager: fileManager)
            return CountResult(value: matches.count, unit: countSpec.unit)
        }
    }

    // MARK: unmodeled 扫描

    /// 只看每个 root 的直接子项:既不被任何 resource 覆盖、也不在 ignore
    /// 列表内的条目报告为 unmodeled。刻意不做深度扫描,避免制造噪音。
    private func scanUnmodeled(resourceResults: [ResourceCheckResult]) -> [UnmodeledEntry] {
        guard let config = spec.unmodeled else { return [] }

        // 每条 resource 的"锚点"绝对路径:file/directory 用展开路径,
        // glob 用字面前缀目录(前缀为空则无法作为锚点,跳过)。
        var anchors: [String] = []
        for resource in spec.resources {
            switch resource.pathKind {
            case .file, .directory:
                anchors.append(resolve(resource.path).path)
            case .glob:
                let (prefix, _) = Glob.splitLiteralPrefix(pattern: resource.path)
                guard !prefix.isEmpty else { continue }
                anchors.append(resolve(prefix.joined(separator: "/")).path)
            }
        }

        let ignorePatterns = (config.ignore ?? []).map { resolveIgnorePattern($0) }

        var entries: [UnmodeledEntry] = []
        for root in config.roots {
            let rootURL = resolve(root.path)
            guard let children = try? fileManager.contentsOfDirectory(atPath: rootURL.path) else {
                continue
            }
            for child in children.sorted() {
                let childPath = rootURL.appendingPathComponent(child).path
                if isModeled(childPath, anchors: anchors) { continue }
                if ignorePatterns.contains(where: { matchesIgnore(childPath, pattern: $0) }) {
                    continue
                }
                entries.append(UnmodeledEntry(path: childPath, root: rootURL.path))
            }
        }
        return entries
    }

    private func isModeled(_ path: String, anchors: [String]) -> Bool {
        anchors.contains { anchor in
            anchor == path
                || anchor.hasPrefix(path + "/")
                || path.hasPrefix(anchor + "/")
        }
    }

    /// ignore 模式展开为绝对路径模式(段内可含 *)。
    private func resolveIgnorePattern(_ pattern: String) -> String {
        if pattern.hasPrefix("~/") {
            return home.path + "/" + String(pattern.dropFirst(2))
        }
        if pattern.hasPrefix("/") { return pattern }
        return projectRoot.path + "/" + pattern
    }

    private func matchesIgnore(_ path: String, pattern: String) -> Bool {
        let pathParts = path.split(separator: "/").map(String.init)
        let patternParts = pattern.split(separator: "/").map(String.init)
        guard pathParts.count == patternParts.count else { return false }
        for (segment, segmentPattern) in zip(pathParts, patternParts) {
            if !Glob.matchComponent(segment, pattern: segmentPattern) { return false }
        }
        return true
    }
}

// MARK: - 文本渲染

extension CheckReport {
    /// 渲染为 CLI 文本输出。homePath 用于把绝对路径缩写回 ~。
    public func renderText(homePath: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        func abbreviate(_ path: String) -> String {
            if path == homePath { return "~" }
            if path.hasPrefix(homePath + "/") {
                return "~" + path.dropFirst(homePath.count)
            }
            return path
        }

        var lines: [String] = []
        lines.append("platform: \(platformID) (\(platformName))")
        lines.append("project:  \(projectPath)")
        lines.append("")
        lines.append("resources:")
        for result in resources {
            let tag = result.isPresent ? "[present]  " : "[missing]  "
            var line = "  \(tag)\(result.resource.id)  \(abbreviate(result.resolvedPath))"
            if let count = result.count {
                line += "  (\(count.value) \(count.unit))"
            }
            if case .present(let matches) = result.status,
               result.resource.pathKind == .glob {
                line += "  (\(matches.count) matched)"
            }
            if !result.isPresent && result.resource.isRequired {
                line += "  <- required!"
            }
            if result.resource.confidence == .low {
                line += "  [confidence: low]"
            }
            lines.append(line)
            if case .present(let matches) = result.status,
               result.resource.pathKind == .glob {
                for match in matches.prefix(5) {
                    lines.append("             - \(abbreviate(match))")
                }
                if matches.count > 5 {
                    lines.append("             … 另有 \(matches.count - 5) 项")
                }
            }
        }
        lines.append("")
        if unmodeled.isEmpty {
            lines.append("unmodeled: (none)")
        } else {
            lines.append("unmodeled:")
            for entry in unmodeled {
                lines.append("  [unmodeled] \(abbreviate(entry.path))")
            }
        }
        lines.append("")
        lines.append(
            "summary: \(presentCount) present, \(missingCount) missing"
                + (requiredMissing.isEmpty ? "" : " (\(requiredMissing.count) required missing!)")
                + ", \(unmodeled.count) unmodeled"
        )
        return lines.joined(separator: "\n")
    }
}

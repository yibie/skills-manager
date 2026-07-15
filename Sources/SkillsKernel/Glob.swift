import Foundation

/// 极简 glob 支持:`*` 匹配单个路径段内任意字符(不含 /),`**` 匹配任意多层目录。
/// 只服务于 adapter spec 的路径规则,不追求 shell glob 的完整语义。
public enum Glob {
    /// 相对路径(以 / 分段)是否匹配 glob 模式。`**` 匹配零个或多个路径段。
    public static func matches(path: String, pattern: String) -> Bool {
        let pathParts = path.split(separator: "/").map(String.init)
        let patternParts = pattern.split(separator: "/").map(String.init)
        return matchSegments(pattern: patternParts[...], path: pathParts[...])
    }

    private static func matchSegments(
        pattern: ArraySlice<String>,
        path: ArraySlice<String>
    ) -> Bool {
        guard let first = pattern.first else { return path.isEmpty }
        if first == "**" {
            // ** 匹配零段或吞掉一段后继续
            if matchSegments(pattern: pattern.dropFirst(), path: path) { return true }
            guard !path.isEmpty else { return false }
            return matchSegments(pattern: pattern, path: path.dropFirst())
        }
        guard let head = path.first, matchComponent(head, pattern: first) else { return false }
        return matchSegments(pattern: pattern.dropFirst(), path: path.dropFirst())
    }

    /// 单个路径段的通配匹配(只支持 *)。
    public static func matchComponent(_ component: String, pattern: String) -> Bool {
        let chars = Array(component)
        let patternChars = Array(pattern)

        // 经典迭代式通配匹配
        var ci = 0, pi = 0
        var starPi = -1, starCi = 0
        while ci < chars.count {
            if pi < patternChars.count && (patternChars[pi] == chars[ci]) {
                ci += 1; pi += 1
            } else if pi < patternChars.count && patternChars[pi] == "*" {
                starPi = pi; starCi = ci
                pi += 1
            } else if starPi >= 0 {
                pi = starPi + 1
                starCi += 1
                ci = starCi
            } else {
                return false
            }
        }
        while pi < patternChars.count && patternChars[pi] == "*" { pi += 1 }
        return pi == patternChars.count
    }

    /// 取 glob 模式中第一个通配段之前的字面前缀(供确定文件系统扫描基准目录)。
    /// 返回 (字面前缀段, 剩余模式段)。
    public static func splitLiteralPrefix(pattern: String) -> (prefix: [String], rest: [String]) {
        let parts = pattern.split(separator: "/").map(String.init)
        var prefix: [String] = []
        var index = 0
        while index < parts.count, !parts[index].contains("*") {
            prefix.append(parts[index])
            index += 1
        }
        return (prefix, Array(parts[index...]))
    }

    /// 在 baseDir 下展开剩余模式段,返回匹配的相对路径(以 / 连接)。
    /// 为避免大树扫描:限制递归深度,跳过点目录与常见依赖目录。
    public static func expand(
        baseDir: URL,
        patternParts: [String],
        fileManager: FileManager = .default,
        maxDepth: Int = 8
    ) -> [String] {
        var results: [String] = []
        walk(
            dir: baseDir,
            relative: [],
            patternParts: patternParts,
            fileManager: fileManager,
            remainingDepth: maxDepth,
            results: &results
        )
        return results.sorted()
    }

    private static let skippedDirectories: Set<String> = [
        "node_modules", ".git", ".build", ".svn", ".hg", "DerivedData",
    ]

    private static func walk(
        dir: URL,
        relative: [String],
        patternParts: [String],
        fileManager: FileManager,
        remainingDepth: Int,
        results: inout [String]
    ) {
        guard remainingDepth > 0 else { return }
        guard let children = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return }
        for child in children.sorted() {
            if skippedDirectories.contains(child) { continue }
            let childRelative = relative + [child]
            let childPath = childRelative.joined(separator: "/")
            if matchSegments(pattern: patternParts[...], path: childRelative[...]) {
                results.append(childPath)
            }
            var isDirectory: ObjCBool = false
            let childURL = dir.appendingPathComponent(child)
            if fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               couldDescend(pattern: patternParts, into: childRelative) {
                walk(
                    dir: childURL,
                    relative: childRelative,
                    patternParts: patternParts,
                    fileManager: fileManager,
                    remainingDepth: remainingDepth - 1,
                    results: &results
                )
            }
        }
    }

    /// 剪枝:该目录前缀是否还有可能匹配模式(避免无意义的整树遍历)。
    private static func couldDescend(pattern: [String], into prefix: [String]) -> Bool {
        // 含 ** 的模式无法便宜地剪枝,直接允许下钻(深度上限兜底)
        if pattern.contains("**") { return true }
        guard prefix.count < pattern.count else { return false }
        for (index, segment) in prefix.enumerated() {
            if !matchComponent(segment, pattern: pattern[index]) { return false }
        }
        return true
    }
}

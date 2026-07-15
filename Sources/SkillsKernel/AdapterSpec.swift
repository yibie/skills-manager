import Foundation
import Yams

// MARK: - Adapter Spec 类型模型
// 结构与 platform-specs/schema.json 一一对应,撰写规则见 platform-specs/SCHEMA.md。

/// Agent Resource 的资源类型。
public enum ResourceType: String, Codable, Sendable {
    case identity
    case guidance
    case skill
    case runtimeConfig = "runtime-config"
}

/// 路径的作用域,决定解析基准。
public enum ResourceScope: String, Codable, Sendable {
    /// 用户级:路径以 ~ 开头或为绝对路径
    case global
    /// 项目级:相对项目根
    case project
    /// 项目内任意子目录:相对项目根的 glob
    case directory
}

/// 路径的解释方式。
public enum PathKind: String, Codable, Sendable {
    case file
    case directory
    case glob
}

public enum Confidence: String, Codable, Sendable {
    case high, medium, low
}

/// runtime-config 的浅计数配置。
public struct CountSpec: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable {
        /// 解析 JSON 文件,按 pointer 定位对象后数键数量
        case jsonKeys = "json-keys"
        /// 数目录直接子项数量
        case entries
        /// 按 file_pattern 数目录内匹配文件数量
        case files
    }

    public let method: Method
    public let pointer: String?
    public let filePattern: String?
    public let unit: String

    enum CodingKeys: String, CodingKey {
        case method, pointer, unit
        case filePattern = "file_pattern"
    }
}

/// 一条加载路径规则。
public struct SpecResource: Codable, Sendable {
    public let id: String
    public let type: ResourceType
    public let scope: ResourceScope
    public let path: String
    public let pathKind: PathKind
    public let required: Bool?
    public let description: String?
    public let source: String
    public let confidence: Confidence
    public let count: CountSpec?

    enum CodingKeys: String, CodingKey {
        case id, type, scope, path, required, description, source, confidence, count
        case pathKind = "path_kind"
    }

    public var isRequired: Bool { required ?? false }
}

/// 优先级/遮蔽规则。
public struct ShadowRule: Codable, Sendable {
    public enum Strategy: String, Codable, Sendable {
        case override, merge
    }

    public let id: String
    public let description: String?
    public let strategy: Strategy
    public let winner: String
    public let loser: String
    public let key: String?
    public let source: String
    public let confidence: Confidence
}

/// unmodeled 扫描配置。
public struct UnmodeledConfig: Codable, Sendable {
    public struct Root: Codable, Sendable {
        public let path: String
        public let scope: ResourceScope
    }

    public let roots: [Root]
    public let ignore: [String]?
}

public struct PlatformInfo: Codable, Sendable {
    public let id: String
    public let name: String
    public let versionRange: String?
    public let docsUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case versionRange = "version_range"
        case docsUrl = "docs_url"
    }
}

public struct SpecMetadata: Codable, Sendable {
    public let generatedBy: String
    public let lastVerified: String
    public let verifiedOn: String?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case generatedBy = "generated_by"
        case lastVerified = "last_verified"
        case verifiedOn = "verified_on"
        case notes
    }
}

/// Adapter Spec:某平台加载语义的声明式描述。
public struct AdapterSpec: Codable, Sendable {
    public let schemaVersion: Int
    public let platform: PlatformInfo
    public let metadata: SpecMetadata
    public let resources: [SpecResource]
    public let shadowing: [ShadowRule]?
    public let unmodeled: UnmodeledConfig?

    enum CodingKeys: String, CodingKey {
        case platform, metadata, resources, shadowing, unmodeled
        case schemaVersion = "schema_version"
    }
}

// MARK: - 加载与语义校验

public enum SpecError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case parseFailure(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "文件不存在: \(path)"
        case .parseFailure(let detail): return "spec 解析失败: \(detail)"
        }
    }
}

public enum SpecLoader {
    /// 读取 YAML spec 文本,返回归一化 JSONValue(供 schema 校验)。
    public static func loadRaw(fileURL: URL) throws -> JSONValue {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SpecError.fileNotFound(fileURL.path)
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        do {
            return try JSONValue.fromYAML(text)
        } catch {
            throw SpecError.parseFailure(String(describing: error))
        }
    }

    /// 解析为类型化的 AdapterSpec(通常在 schema 校验通过后调用)。
    public static func loadTyped(fileURL: URL) throws -> AdapterSpec {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SpecError.fileNotFound(fileURL.path)
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        do {
            return try YAMLDecoder().decode(AdapterSpec.self, from: text)
        } catch {
            throw SpecError.parseFailure(String(describing: error))
        }
    }

    /// schema 之外的语义校验:id 唯一、shadowing 引用存在、count 只用于
    /// runtime-config、scope 与路径写法一致。
    public static func semanticIssues(in spec: AdapterSpec) -> [SchemaIssue] {
        var issues: [SchemaIssue] = []

        var seenIDs: Set<String> = []
        for (index, resource) in spec.resources.enumerated() {
            let path = "/resources/\(index)"
            if !seenIDs.insert(resource.id).inserted {
                issues.append(SchemaIssue(path: path, message: "resource id 重复: \(resource.id)"))
            }
            if resource.count != nil && resource.type != .runtimeConfig {
                issues.append(SchemaIssue(path: path, message: "count 只允许用于 runtime-config 资源"))
            }
            switch resource.scope {
            case .global:
                if !resource.path.hasPrefix("~") && !resource.path.hasPrefix("/") {
                    issues.append(SchemaIssue(
                        path: path,
                        message: "global scope 的路径应以 ~ 开头或为绝对路径: \(resource.path)"
                    ))
                }
            case .project, .directory:
                if resource.path.hasPrefix("~") || resource.path.hasPrefix("/") {
                    issues.append(SchemaIssue(
                        path: path,
                        message: "\(resource.scope.rawValue) scope 的路径应为项目相对路径: \(resource.path)"
                    ))
                }
            }
            let hasWildcard = resource.path.contains("*")
            if resource.pathKind == .glob && !hasWildcard {
                issues.append(SchemaIssue(path: path, message: "path_kind 为 glob 但路径不含通配符"))
            }
            if resource.pathKind != .glob && hasWildcard {
                issues.append(SchemaIssue(path: path, message: "路径含通配符时 path_kind 必须为 glob"))
            }
            if let count = resource.count {
                if count.method == .jsonKeys && count.pointer == nil {
                    issues.append(SchemaIssue(path: path, message: "count.method 为 json-keys 时必须提供 pointer"))
                }
                if count.method == .files && count.filePattern == nil {
                    issues.append(SchemaIssue(path: path, message: "count.method 为 files 时必须提供 file_pattern"))
                }
            }
        }

        var seenRuleIDs: Set<String> = []
        for (index, rule) in (spec.shadowing ?? []).enumerated() {
            let path = "/shadowing/\(index)"
            if !seenRuleIDs.insert(rule.id).inserted {
                issues.append(SchemaIssue(path: path, message: "shadowing id 重复: \(rule.id)"))
            }
            if !seenIDs.contains(rule.winner) {
                issues.append(SchemaIssue(path: path, message: "winner 引用了不存在的 resource id: \(rule.winner)"))
            }
            if !seenIDs.contains(rule.loser) {
                issues.append(SchemaIssue(path: path, message: "loser 引用了不存在的 resource id: \(rule.loser)"))
            }
            if rule.winner == rule.loser {
                issues.append(SchemaIssue(path: path, message: "winner 与 loser 不能相同"))
            }
        }

        return issues
    }
}

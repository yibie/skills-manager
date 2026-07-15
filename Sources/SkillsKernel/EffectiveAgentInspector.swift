import Foundation

// MARK: - Effective-Agent 报告模型
// 与 docs/goals/effective-agent-schema.json 一一对应,是 UI/TUI 消费的公共数据契约。
// 字段语义见 docs/goals/effective-agent-schema.md;改动格式必须升 schemaVersion。

/// 资源实例的生效状态。
public enum InstanceStatus: String, Codable, Sendable {
    /// 实际会被 Agent 加载
    case active
    /// 被同 key 的更高优先级实例遮蔽(仅 override 策略产生)
    case shadowed
    /// spec 声明(先验)但文件系统不存在(后验)
    case missing
}

/// 被遮蔽时的归因:被哪个实例遮蔽、依据哪条 shadowing 规则。
public struct ShadowedBy: Codable, Sendable, Equatable {
    /// 依据的 spec shadowing 规则 id
    public let shadowRuleId: String
    /// 遮蔽方实例所属的 resource 规则 id
    public let winnerRuleId: String
    /// 遮蔽方实例的绝对路径
    public let winnerPath: String

    enum CodingKeys: String, CodingKey {
        case shadowRuleId = "shadow_rule_id"
        case winnerRuleId = "winner_rule_id"
        case winnerPath = "winner_path"
    }
}

/// runtime-config 的浅计数(沿用 SpecChecker 的计数机制)。
public struct InstanceCount: Codable, Sendable, Equatable {
    public let value: Int
    public let unit: String
}

/// 一个被枚举出的资源实例:一个 skill、一个 guidance 文件、一个 runtime-config 文件……
public struct ResourceInstance: Codable, Sendable {
    /// 遮蔽比较用标识(skill 目录名 / agent 名 / 文件名);missing 时无实例可标识,为 nil
    public let key: String?
    /// 产生该实例的 spec resource 规则 id
    public let ruleId: String
    /// 来源文件绝对路径;missing 时为 spec 期望的展开路径
    public let path: String
    public let scope: ResourceScope
    public let status: InstanceStatus
    /// spec 是否声明该规则为必需(显式透传,不用缺省值隐藏)
    public let required: Bool
    /// 来源规则的 confidence 透传:low 表示该规则本身可能说谎
    public let confidence: Confidence
    /// 仅 status 为 shadowed 时存在
    public let shadowedBy: ShadowedBy?
    /// 仅 runtime-config 且规则配置了计数时存在
    public let count: InstanceCount?

    enum CodingKeys: String, CodingKey {
        case key, path, scope, status, required, confidence, count
        case ruleId = "rule_id"
        case shadowedBy = "shadowed_by"
    }
}

/// 按资源类型分组的实例列表;四个键始终存在,无实例时为空数组。
public struct ResourceGroups: Codable, Sendable {
    public let identity: [ResourceInstance]
    public let guidance: [ResourceInstance]
    public let skill: [ResourceInstance]
    public let runtimeConfig: [ResourceInstance]

    enum CodingKeys: String, CodingKey {
        case identity, guidance, skill
        case runtimeConfig = "runtime-config"
    }

    public var all: [ResourceInstance] { identity + guidance + skill + runtimeConfig }
}

public struct ReportSummary: Codable, Sendable, Equatable {
    /// 资源实例总数(active + shadowed + missing)
    public let resources: Int
    public let active: Int
    public let shadowed: Int
    public let missing: Int
    public let unmodeled: Int
}

/// spec 未建模但邻域内存在的可疑条目(诚实的不确定性,不许隐藏)。
public struct UnmodeledItem: Codable, Sendable {
    public let path: String
    public let root: String
    public let scope: ResourceScope
}

public struct ReportPlatform: Codable, Sendable {
    public let id: String
    public let name: String
    public let versionRange: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case versionRange = "version_range"
    }
}

public struct ReportProject: Codable, Sendable {
    public let path: String
}

/// 报告依据的 adapter spec 元数据(spec 是先验,文件系统是后验)。
public struct ReportSpec: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedBy: String
    /// spec 最后一次人工/AI 校验日期;越久远越可能说谎
    public let lastVerified: String
    /// spec 文件路径(CLI 提供;进程内调用时可为 nil)
    public let path: String?

    enum CodingKeys: String, CodingKey {
        case path
        case schemaVersion = "schema_version"
        case generatedBy = "generated_by"
        case lastVerified = "last_verified"
    }
}

/// `skm inspect` 的完整输出:某平台 × 某项目下实际生效的 Resource 集合。
public struct EffectiveAgentReport: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let platform: ReportPlatform
    public let project: ReportProject
    public let spec: ReportSpec
    public let summary: ReportSummary
    public let resources: ResourceGroups
    public let unmodeled: [UnmodeledItem]

    enum CodingKeys: String, CodingKey {
        case platform, project, spec, summary, resources, unmodeled
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
    }
}

extension EffectiveAgentReport {
    /// 序列化为 JSON 文本(键排序,保证输出稳定;pretty 为缩进格式)。
    public func renderJSON(pretty: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { formatting.insert(.prettyPrinted) }
        encoder.outputFormatting = formatting
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - 检视器

/// 消费 AdapterSpec + 文件系统扫描,组装 Effective-Agent 报告。
/// 复用 SpecChecker 完成路径展开/存在性/glob/计数/unmodeled,在其结果之上
/// 做语义实例化(枚举每条规则命中的实际资源实例)与遮蔽计算。
/// 只读:不创建、不修改任何文件。home 可注入,便于用 fixture 目录树测试。
public struct EffectiveAgentInspector {
    private let spec: AdapterSpec
    private let specPath: String?
    private let projectRoot: URL
    private let home: URL
    private let fileManager: FileManager
    private let now: Date

    public init(
        spec: AdapterSpec,
        projectRoot: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        specPath: String? = nil,
        now: Date = Date()
    ) {
        self.spec = spec
        self.specPath = specPath
        self.projectRoot = projectRoot.standardizedFileURL
        self.home = home.standardizedFileURL
        self.fileManager = fileManager
        self.now = now
    }

    public func run() -> EffectiveAgentReport {
        let check = SpecChecker(
            spec: spec,
            projectRoot: projectRoot,
            home: home,
            fileManager: fileManager
        ).run()

        var workings = check.resources.flatMap(instantiate(result:))
        applyShadowing(to: &workings)

        let instances = workings.map(\.instance)
        // 按类型分组,保持 spec 规则顺序 + 容器内文件名顺序(instantiate 的产出顺序)
        func group(_ type: ResourceType) -> [ResourceInstance] {
            zip(workings, instances).filter { $0.0.resource.type == type }.map(\.1)
        }
        let groups = ResourceGroups(
            identity: group(.identity),
            guidance: group(.guidance),
            skill: group(.skill),
            runtimeConfig: group(.runtimeConfig)
        )

        let summary = ReportSummary(
            resources: instances.count,
            active: instances.filter { $0.status == .active }.count,
            shadowed: instances.filter { $0.status == .shadowed }.count,
            missing: instances.filter { $0.status == .missing }.count,
            unmodeled: check.unmodeled.count
        )

        let formatter = ISO8601DateFormatter()
        return EffectiveAgentReport(
            schemaVersion: 1,
            generatedAt: formatter.string(from: now),
            platform: ReportPlatform(
                id: spec.platform.id,
                name: spec.platform.name,
                versionRange: spec.platform.versionRange
            ),
            project: ReportProject(path: projectRoot.path),
            spec: ReportSpec(
                schemaVersion: spec.schemaVersion,
                generatedBy: spec.metadata.generatedBy,
                lastVerified: spec.metadata.lastVerified,
                path: specPath
            ),
            summary: summary,
            resources: groups,
            unmodeled: check.unmodeled.map {
                UnmodeledItem(path: $0.path, root: $0.root, scope: $0.scope)
            }
        )
    }

    // MARK: 语义实例化

    /// 中间表示:实例 + 所属规则(遮蔽计算需要按规则 id 定位实例)。
    private struct Working {
        let resource: SpecResource
        let key: String?
        let path: String
        var status: InstanceStatus
        var shadowedBy: ShadowedBy?
        let count: InstanceCount?

        var instance: ResourceInstance {
            ResourceInstance(
                key: key,
                ruleId: resource.id,
                path: path,
                scope: resource.scope,
                status: status,
                required: resource.isRequired,
                confidence: resource.confidence,
                shadowedBy: shadowedBy,
                count: count
            )
        }
    }

    /// 把单条规则的核对结果实例化为零或多个资源实例。
    private func instantiate(result: ResourceCheckResult) -> [Working] {
        let resource = result.resource
        guard case .present(let matches) = result.status else {
            // spec 声明但不存在:产出一个 missing 实例,path 为期望路径
            return [Working(
                resource: resource, key: nil, path: result.resolvedPath,
                status: .missing, shadowedBy: nil, count: nil
            )]
        }

        // runtime-config 浅覆盖:文件本身即实例,透传计数,不做内容枚举
        if resource.type == .runtimeConfig {
            return matches.map { match in
                Working(
                    resource: resource,
                    key: lastComponent(of: match),
                    path: match,
                    status: .active,
                    shadowedBy: nil,
                    count: result.count.map { InstanceCount(value: $0.value, unit: $0.unit) }
                )
            }
        }

        switch resource.pathKind {
        case .file:
            return matches.map { fileInstance(resource: resource, path: $0) }
        case .directory:
            return matches.flatMap { containerInstances(resource: resource, directory: $0) }
        case .glob:
            // glob 命中目录(如 plugin 携带的 skills 根)按容器枚举,命中文件按文件实例
            return matches.flatMap { match -> [Working] in
                if isDirectory(match) {
                    return containerInstances(resource: resource, directory: match)
                }
                return [fileInstance(resource: resource, path: match)]
            }
        }
    }

    /// 单文件实例。key:guidance 保留文件名(如 CLAUDE.md);identity/skill
    /// 去掉 .md 扩展名(即 agent 名 / command 名)。
    private func fileInstance(resource: SpecResource, path: String) -> Working {
        let name = lastComponent(of: path)
        let key = resource.type == .guidance ? name : stripMarkdownExtension(name)
        return Working(
            resource: resource, key: key, path: path,
            status: .active, shadowedBy: nil, count: nil
        )
    }

    /// 容器目录的浅枚举:
    /// - skill:含 SKILL.md 的子目录是一个 skill 实例(key = 目录名);
    ///   裸 *.md(slash command 形态)也各是一个实例
    /// - identity/guidance:一层 *.md 文件各是一个实例,不下钻子目录
    private func containerInstances(resource: SpecResource, directory: String) -> [Working] {
        guard let children = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return []
        }
        var result: [Working] = []
        for child in children.sorted() {
            if child.hasPrefix(".") { continue }
            let childPath = directory + "/" + child
            if isDirectory(childPath) {
                guard resource.type == .skill else { continue }
                let skillManifest = childPath + "/SKILL.md"
                if fileManager.fileExists(atPath: skillManifest) {
                    result.append(Working(
                        resource: resource, key: child, path: skillManifest,
                        status: .active, shadowedBy: nil, count: nil
                    ))
                }
            } else if child.hasSuffix(".md") {
                result.append(fileInstance(resource: resource, path: childPath))
            }
        }
        return result
    }

    // MARK: 遮蔽计算

    /// 按 spec 中 shadowing 规则的书写顺序单趟处理。只有 override 策略产生
    /// shadowed(merge 双方都生效);只有当时仍为 active 的 winner 实例才能
    /// 遮蔽别人(遮蔽不传染)。
    private func applyShadowing(to workings: inout [Working]) {
        for rule in spec.shadowing ?? [] where rule.strategy == .override {
            var winnersByKey: [String: Working] = [:]
            for working in workings
            where working.resource.id == rule.winner && working.status == .active {
                if let key = working.key, winnersByKey[key] == nil {
                    winnersByKey[key] = working
                }
            }
            guard !winnersByKey.isEmpty else { continue }
            for index in workings.indices
            where workings[index].resource.id == rule.loser
                && workings[index].status == .active {
                guard let key = workings[index].key, let winner = winnersByKey[key] else {
                    continue
                }
                workings[index].status = .shadowed
                workings[index].shadowedBy = ShadowedBy(
                    shadowRuleId: rule.id,
                    winnerRuleId: rule.winner,
                    winnerPath: winner.path
                )
            }
        }
    }

    // MARK: 工具

    private func lastComponent(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func stripMarkdownExtension(_ name: String) -> String {
        name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

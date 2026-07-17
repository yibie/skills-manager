import Foundation
import Observation
import SkillsKernel

// MARK: - 检视器视图模型(M3)
// 进程内直接调用 SkillsKernel(不走 skm CLI 子进程)。检视器只读:除
// UserDefaults 的最近项目列表外,不写入用户目录的任何文件。
// 不依赖 AppKit,便于单元测试(NSOpenPanel/NSWorkspace 交互在 View 层)。

/// 扫描失败的可读错误(spec 无效、项目不存在等,不许以崩溃收场)。
enum InspectorScanError: Error, Equatable {
    case projectNotFound(String)
    case schemaUnavailable
    case specInvalid([String])
    case specUnreadable(String)

    var message: String {
        switch self {
        case .projectNotFound(let path):
            return "项目目录不存在:\(path)"
        case .schemaUnavailable:
            return "找不到 schema.json,无法校验 spec(内置资源缺失?)"
        case .specInvalid(let issues):
            return "spec 未通过校验:\n" + issues.joined(separator: "\n")
        case .specUnreadable(let detail):
            return "spec 无法读取:\(detail)"
        }
    }
}

/// 扫描执行器:校验 spec → 运行 EffectiveAgentInspector。
/// nonisolated async,整个流程跑在后台协作线程池,不阻塞主线程。
enum InspectorScanner {
    static func scan(
        specURL: URL,
        schemaURL: URL?,
        projectURL: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> Result<EffectiveAgentReport, InspectorScanError> {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .failure(.projectNotFound(projectURL.path))
        }
        guard let schemaURL else {
            return .failure(.schemaUnavailable)
        }

        // 坏 spec 的检视结果没有意义:先结构校验再语义校验,问题原样透传给 UI
        let raw: JSONValue
        let validator: SchemaValidator
        do {
            raw = try SpecLoader.loadRaw(fileURL: specURL)
            validator = try SchemaValidator(schemaFileURL: schemaURL)
        } catch {
            return .failure(.specUnreadable(String(describing: error)))
        }
        let structuralIssues = validator.validate(raw)
        guard structuralIssues.isEmpty else {
            return .failure(.specInvalid(structuralIssues.map { "[schema] \($0)" }))
        }

        let spec: AdapterSpec
        do {
            spec = try SpecLoader.loadTyped(fileURL: specURL)
        } catch {
            return .failure(.specUnreadable(String(describing: error)))
        }
        let semanticIssues = SpecLoader.semanticIssues(in: spec)
        guard semanticIssues.isEmpty else {
            return .failure(.specInvalid(semanticIssues.map { "[semantic] \($0)" }))
        }

        let inspector = EffectiveAgentInspector(
            spec: spec,
            projectRoot: projectURL,
            home: home,
            specPath: specURL.path
        )
        return .success(inspector.run())
    }
}

@Observable
@MainActor
final class InspectorViewModel {
    /// 一次扫描的生命周期状态。
    enum Phase {
        case idle
        case scanning
        case loaded(InspectorPresentation)
        case failed(String)
    }

    // MARK: 状态

    private(set) var phase: Phase = .idle
    /// 可用 spec 列表(v1 只有 claude-code,UI 按可扩展列表实现)
    private(set) var specs: [SpecCatalogEntry] = []
    var selectedSpecID: SpecCatalogEntry.ID?
    /// 当前 specs 目录覆盖;nil = 使用内置资源副本。仅会话内有效,不持久化
    /// (硬性约束:UserDefaults 只允许写最近项目列表)
    private(set) var specsDirectoryOverride: URL?
    /// 当前选中的项目路径
    private(set) var projectPath: String?
    /// 最近使用的项目路径,新→旧
    private(set) var recentProjects: [String] = []
    /// 列表中选中的资源实例行
    var selectedRowID: InspectorInstanceRow.ID?

    // MARK: 依赖

    private let defaults: UserDefaults
    private let home: URL
    private var scanTask: Task<Void, Never>?

    static let recentProjectsKey = "inspector.recentProjects"
    static let recentProjectsLimit = 8

    init(
        defaults: UserDefaults = .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.defaults = defaults
        self.home = home
        self.recentProjects = defaults.stringArray(forKey: Self.recentProjectsKey) ?? []
        reloadSpecs()
    }

    // MARK: 派生

    var selectedSpec: SpecCatalogEntry? {
        specs.first { $0.id == selectedSpecID }
    }

    var presentation: InspectorPresentation? {
        if case .loaded(let presentation) = phase { return presentation }
        return nil
    }

    var selectedRow: InspectorInstanceRow? {
        presentation?.row(withID: selectedRowID)
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    /// 当前生效的 specs 目录(覆盖目录优先,缺省为内置副本)。
    var effectiveSpecsDirectory: URL? {
        specsDirectoryOverride ?? SpecCatalog.bundledSpecsDirectory
    }

    // MARK: 动作

    /// 重新发现可用 spec;保持已选平台,失效时回退到第一个可解析的 spec。
    func reloadSpecs() {
        guard let directory = effectiveSpecsDirectory else {
            specs = []
            selectedSpecID = nil
            return
        }
        specs = SpecCatalog.discover(in: directory)
        if specs.first(where: { $0.id == selectedSpecID }) == nil {
            selectedSpecID = specs.first { $0.loadError == nil }?.id ?? specs.first?.id
        }
    }

    /// 切换 specs 目录(nil 表示回到内置);切换后重新发现并重扫。
    func setSpecsDirectory(_ url: URL?) {
        specsDirectoryOverride = url?.standardizedFileURL
        reloadSpecs()
        rescan()
    }

    /// 选择项目目录:记入最近列表(去重、限长)并触发扫描。
    func selectProject(_ url: URL) {
        let path = url.standardizedFileURL.path
        projectPath = path
        var recents = recentProjects.filter { $0 != path }
        recents.insert(path, at: 0)
        if recents.count > Self.recentProjectsLimit {
            recents = Array(recents.prefix(Self.recentProjectsLimit))
        }
        recentProjects = recents
        defaults.set(recents, forKey: Self.recentProjectsKey)
        rescan()
    }

    /// 重新扫描当前 平台 × 项目;选择不全时回到 idle。
    func rescan() {
        scanTask?.cancel()
        selectedRowID = nil
        guard let spec = selectedSpec, let projectPath else {
            phase = .idle
            return
        }
        if let loadError = spec.loadError {
            phase = .failed("spec 无法解析:\(loadError)")
            return
        }
        let specURL = spec.url
        let schemaURL = effectiveSpecsDirectory.flatMap { SpecCatalog.schemaURL(for: $0) }
        let projectURL = URL(fileURLWithPath: projectPath)
        let home = home

        phase = .scanning
        scanTask = Task { [weak self] in
            // InspectorScanner.scan 为 nonisolated async,在后台线程池执行
            let result = await InspectorScanner.scan(
                specURL: specURL,
                schemaURL: schemaURL,
                projectURL: projectURL,
                home: home
            )
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let report):
                self.phase = .loaded(InspectorPresentation(report: report))
            case .failure(let error):
                self.phase = .failed(error.message)
            }
        }
    }
}

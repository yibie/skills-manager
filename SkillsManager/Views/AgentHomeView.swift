import SwiftUI
import AppKit
import SkillsKernel

// MARK: - Agent 主页(IA 重组 v1)
// 侧边栏 Agents 从过滤器升级为目的地:每个 agent 一个主页——看懂它(检视器
// 深链),打理它(skills 列表 + 冲突)。无 adapter spec 的平台诚实降级,不假装
// 能检视。Skills 区完整复用 SkillListView(搜索/星标/右键/批量)。

/// AgentHomeView 的纯逻辑,抽出来便于单元测试。
enum AgentHomeSupport {
    /// 按平台 id 匹配可用 spec(解析失败的条目不参与匹配)。
    static func specEntry(forAgentID agentID: String?, in specs: [SpecCatalogEntry]) -> SpecCatalogEntry? {
        guard let agentID else { return nil }
        return specs.first { $0.platformID == agentID && $0.loadError == nil }
    }

    /// 涉及某 agent 的冲突(该 agent 的目录里有分叉副本)。
    static func conflicts(involving agentName: String, from conflicts: [SkillConflict]) -> [SkillConflict] {
        conflicts.filter { conflict in
            conflict.instances.contains { $0.agents.contains(agentName) }
        }
    }
}

struct AgentHomeView: View {
    let agentName: String
    let skills: [Skill]
    let conflicts: [SkillConflict]
    /// 该平台匹配到的 spec;nil = 暂无 adapter spec。
    let specEntry: SpecCatalogEntry?
    @Binding var selectedSkill: Skill?
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    let onToggleStar: (Skill) -> Void
    let onOpenInspector: () -> Void
    let onShowConflicts: () -> Void

    private var definition: AgentDefinition? {
        AgentRegistry.all.first { $0.displayName == agentName }
    }

    private var isDetected: Bool {
        AgentRegistry.installedAgents().contains { $0.displayName == agentName }
    }

    private var agentConflicts: [SkillConflict] {
        AgentHomeSupport.conflicts(involving: agentName, from: conflicts)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                headerCard
                inspectorCard
                if !agentConflicts.isEmpty {
                    conflictsCard
                }
            }
            .padding(12)

            Divider()

            SkillListView(
                skills: skills,
                filter: .agent(agentName),
                selectedSkill: $selectedSkill,
                onInstall: onInstall,
                onUninstall: onUninstall,
                onToggleStar: onToggleStar
            )
        }
        .navigationTitle(agentName)
    }

    // MARK: 头部卡片

    private var headerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: definition?.icon ?? "cpu")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(agentName)
                    .font(.headline)
                if let dir = definition.map({ AgentRegistry.resolvedSkillsDir(for: $0) }) {
                    Text(abbreviate(dir.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            SkillMetaBadge(
                text: isDetected ? "已检测" : "未检测到安装",
                tint: isDetected ? .green : .secondary
            )
            if let dir = definition.map({ AgentRegistry.resolvedSkillsDir(for: $0) }) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Show skills directory in Finder")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dir.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy skills directory path")
            }
        }
        .cardStyle()
    }

    // MARK: "实际加载"卡片

    @ViewBuilder
    private var inspectorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
            if specEntry != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text("实际加载")
                        .font(.callout)
                        .fontWeight(.medium)
                    Text("该平台有 adapter spec,可在检视器中渲染它实际加载的资源树。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("在检视器中打开", action: onOpenInspector)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("实际加载")
                        .font(.callout)
                        .fontWeight(.medium)
                    Text("该平台暂无 adapter spec——资源树检视将随 M4 逐步覆盖(Codex、OpenClaw、Hermes、Pi 优先)。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
        .cardStyle()
    }

    // MARK: 冲突卡片

    private var conflictsCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(agentConflicts.count) 个技能冲突")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(agentConflicts.map(\.name).joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("查看", action: onShowConflicts)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .cardStyle()
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 8))
    }
}

import SwiftUI
import AppKit

// MARK: - Agent 主页(IA 重组 v1)
// 侧边栏 Agents 从过滤器升级为目的地:每个 agent 一个主页——看懂它(检测状态、
// skills 目录),打理它(skills 列表 + 冲突)。Skills 区完整复用 SkillListView
// (搜索/星标/右键/批量)。

/// AgentHomeView 的纯逻辑,抽出来便于单元测试。
enum AgentHomeSupport {
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
    @Binding var selectedSkill: Skill?
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    var onMoveToTrash: (Skill) async -> Void = { _ in }
    let onToggleStar: (Skill) -> Void
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
                onMoveToTrash: onMoveToTrash,
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
                text: isDetected ? String(localized: "Detected") : String(localized: "Not Detected"),
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
        .paperCard()
    }

    // MARK: 冲突卡片

    private var conflictsCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(agentConflicts.count) skill conflicts")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(agentConflicts.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("View", action: onShowConflicts)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .paperCard()
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

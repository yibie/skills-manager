import SwiftUI
import AppKit

// MARK: - 跨 agent 冲突检测
// 同名 skill 被独立安装到多个 agent(npx 逐 agent 复制)后,各副本可能各自漂移。
// 本页列出内容已经分叉的副本,只读展示;收敛方式是重新安装以覆盖同步。

struct ConflictsView: View {
    let conflicts: [SkillConflict]
    @Binding var selectedConflict: SkillConflict?

    var body: some View {
        Group {
            if conflicts.isEmpty {
                ContentUnavailableView(
                    "No Conflicts",
                    systemImage: "checkmark.shield",
                    description: Text("Same-name skills installed across agents all have identical content.")
                )
            } else {
                List(conflicts, selection: $selectedConflict) { conflict in
                    ConflictRow(conflict: conflict)
                        .listRowSeparator(.hidden)
                        .tag(conflict)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Conflicts")
        .frame(minWidth: 260)
    }
}

private struct ConflictRow: View {
    let conflict: SkillConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(conflict.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text("\(conflict.instances.count) copies differ")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(conflict.instances) { instance in
                    SkillMetaBadge(text: instance.contentHash, tint: .orange)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
    }
}

// MARK: - Detail

struct ConflictsDetailView: View {
    let conflict: SkillConflict?

    var body: some View {
        if let conflict {
            detail(conflict)
        } else {
            ContentUnavailableView(
                "Select a Conflict",
                systemImage: "exclamationmark.triangle",
                description: Text("Choose a skill from the list to compare its diverged copies.")
            )
        }
    }

    private func detail(_ conflict: SkillConflict) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("This skill exists as \(conflict.instances.count) copies with different content. Agents load the copy in their own directory, so behavior differs per agent. Reinstall the skill to all agents to converge the copies.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(conflict.instances) { instance in
                    InstanceCard(instance: instance)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InstanceCard: View {
    let instance: SkillConflictInstance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(abbreviate(instance.path))
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                SkillMetaBadge(text: instance.contentHash, tint: .orange)
            }

            if !instance.agents.isEmpty {
                HStack(spacing: 6) {
                    ForEach(instance.agents, id: \.self) { agent in
                        SkillMetaBadge(text: agent)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: instance.path)])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: instance.path).appendingPathComponent("SKILL.md"))
                } label: {
                    Label("Open SKILL.md", systemImage: "square.and.pencil")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 8))
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

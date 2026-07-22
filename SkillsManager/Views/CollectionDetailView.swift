import SwiftUI

// MARK: - 组详情
// 头部:组名 + 成员数 + 各已检测 agent 的挂载开关(开 = symlink 进 agent,
// 关 = 仅移除链接,技能留库)。成员列表复用 SkillListView。

struct CollectionDetailView: View {
    let collection: CollectionRecord
    let skills: [Skill]
    let detectedAgents: [AgentDefinition]
    let statusFor: (String) -> MountStatus
    @Binding var selectedSkill: Skill?
    let onToggleAgent: (String, Bool) -> Void
    let onReapply: (String) -> Void
    let onAddMembers: ([String]) -> Void
    let onRemoveMember: (Skill) -> Void
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    let onToggleStar: (Skill) -> Void

    @State private var isPickerPresented = false

    private var memberIDs: Set<String> { Set(collection.memberSkillIDs) }

    /// 只显示已挂载的胶囊;其余 30+ 个 agent 收进「挂载到…」菜单,避免开关墙。
    private var mountedAgents: [AgentDefinition] {
        detectedAgents.filter { collection.mountedAgentIDs.contains($0.id) }
    }

    private var unmountedAgents: [AgentDefinition] {
        detectedAgents.filter { !collection.mountedAgentIDs.contains($0.id) }
    }

    private var missingCount: Int {
        let known = Set(skills.map(\.id))
        return collection.memberSkillIDs.filter { !known.contains($0) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(collection.name).font(.headline)
                    Text("\(collection.memberSkillIDs.count) 个技能" + (missingCount > 0 ? " · \(missingCount) 个缺失" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("＋ 添加技能") { isPickerPresented = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                FlowLayout(hSpacing: 8, vSpacing: 8) {
                    ForEach(mountedAgents, id: \.id) { agent in
                        agentCapsule(agent)
                    }
                    if !unmountedAgents.isEmpty {
                        Menu {
                            ForEach(unmountedAgents, id: \.id) { agent in
                                Button(agent.displayName) { onToggleAgent(agent.id, true) }
                            }
                        } label: {
                            Label("挂载到…", systemImage: "plus")
                                .font(.callout)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                Text("打开开关 = 组内技能 symlink 进该 agent;关闭 = 仅移除链接,技能保留在库中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            SkillListView(
                skills: skills,
                filter: .collection(collection.id, name: collection.name),
                memberIDs: memberIDs,
                selectedSkill: $selectedSkill,
                onInstall: onInstall,
                onUninstall: onUninstall,
                onToggleStar: onToggleStar,
                onRemoveFromCollection: onRemoveMember
            )
        }
        .navigationTitle(collection.name)
        .sheet(isPresented: $isPickerPresented) {
            MemberPicker(
                candidates: skills.filter { !memberIDs.contains($0.id) },
                onAdd: { ids in
                    onAddMembers(ids)
                    isPickerPresented = false
                }
            )
        }
    }

    private func agentCapsule(_ agent: AgentDefinition) -> some View {
        let mounted = collection.mountedAgentIDs.contains(agent.id)
        let status = statusFor(agent.id)
        return HStack(spacing: 8) {
            Circle()
                .fill(status == .mounted ? ConsoleTheme.statusOk : status == .diverged ? ConsoleTheme.statusWarn : ConsoleTheme.statusOff)
                .frame(width: 8, height: 8)
            Text(agent.displayName).font(.callout)
            if status == .diverged {
                Button("重新应用") { onReapply(agent.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Toggle("", isOn: Binding(
                get: { mounted },
                set: { onToggleAgent(agent.id, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(ConsoleTheme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ConsoleTheme.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - 成员 picker

private struct MemberPicker: View {
    let candidates: [Skill]
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selected: Set<Skill> = []

    private var filtered: [Skill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.id, selection: $selected) { skill in
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.displayName)
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(skill)
            }
            .searchable(text: $searchText, prompt: "搜索技能")
            .navigationTitle("添加技能")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加 \(selected.count) 个") {
                        onAdd(selected.map(\.id))
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .frame(width: 440, height: 500)
    }
}

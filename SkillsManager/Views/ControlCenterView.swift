import SwiftUI

// MARK: - 控制台(默认落地页)
// 一进来只看到分组和当前挂载状态;大库退到侧栏 Library。卡片只列出
// 「装载意图」内的 agent 行(组 × agent 才可能几十个,列全量 45 个 agent
// 不现实),其余经「＋ 挂载到」菜单添加。

struct ControlCenterView: View {
    let collections: [CollectionRecord]
    let skills: [Skill]
    let detectedAgents: [AgentDefinition]
    let statusFor: (CollectionRecord, String) -> MountStatus
    let onOpen: (CollectionRecord) -> Void
    let onCreate: (String) -> Void
    let onToggleAgent: (CollectionRecord, String, Bool) -> Void
    let onReapply: (CollectionRecord, String) -> Void
    let onRename: (CollectionRecord, String) -> Void
    let onDelete: (CollectionRecord) -> Void

    @State private var isNamingPresented = false
    @State private var newName = ""

    private var summaryText: String {
        var skillMounts = 0
        var agents = Set<String>()
        for collection in collections {
            for agentID in collection.mountedAgentIDs where statusFor(collection, agentID) == .mounted {
                skillMounts += collection.memberSkillIDs.count
                agents.insert(agentID)
            }
        }
        return "\(collections.count) 个分组 · \(skillMounts) 个技能正挂载在 \(agents.count) 个 agent"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("控制台").font(.title2).fontWeight(.semibold)
                    Spacer()
                    Button("＋ 新建分组") { isNamingPresented = true }
                }
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(collections, id: \.id) { collection in
                        CollectionCard(
                            collection: collection,
                            detectedAgents: detectedAgents,
                            statusFor: { statusFor(collection, $0) },
                            onOpen: { onOpen(collection) },
                            onToggleAgent: { onToggleAgent(collection, $0, $1) },
                            onReapply: { onReapply(collection, $0) },
                            onRename: { onRename(collection, $0) },
                            onDelete: { onDelete(collection) }
                        )
                    }
                    // 虚线「新建分组」卡收尾(草图 §5.2)
                    Button { isNamingPresented = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.title2)
                            Text("新建分组").font(.callout)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .navigationTitle("控制台")
        .alert("新建分组", isPresented: $isNamingPresented) {
            TextField("组名", text: $newName)
            Button("创建") {
                onCreate(newName)
                newName = ""
            }
            Button("取消", role: .cancel) { newName = "" }
        }
    }
}

// MARK: - 分组卡片

private struct CollectionCard: View {
    let collection: CollectionRecord
    let detectedAgents: [AgentDefinition]
    let statusFor: (String) -> MountStatus
    let onOpen: () -> Void
    let onToggleAgent: (String, Bool) -> Void
    let onReapply: (String) -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isRenamePresented = false
    @State private var renameText = ""

    private var unmountedAgents: [AgentDefinition] {
        detectedAgents.filter { !collection.mountedAgentIDs.contains($0.id) }
    }

    private var statusText: (text: String, isWarning: Bool) {
        guard !collection.mountedAgentIDs.isEmpty else { return ("未挂载", false) }
        let diverged = collection.mountedAgentIDs.filter { statusFor($0) == .diverged }
        if diverged.isEmpty {
            let names = collection.mountedAgentIDs.compactMap { id in
                detectedAgents.first { $0.id == id }?.displayName
            }
            return ("挂载于 \(names.joined(separator: "、")) · 状态正常", false)
        }
        let names = diverged.compactMap { id in detectedAgents.first { $0.id == id }?.displayName }
        return ("\(names.joined(separator: "、")):与磁盘不一致", true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(collection.name).font(.headline)
                Spacer()
                Menu {
                    Button("重命名…") {
                        renameText = collection.name
                        isRenamePresented = true
                    }
                    Divider()
                    Button("删除分组", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            Text("\(collection.memberSkillIDs.count) 个技能")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(collection.mountedAgentIDs, id: \.self) { agentID in
                HStack(spacing: 7) {
                    statusDot(statusFor(agentID))
                    Text(detectedAgents.first { $0.id == agentID }?.displayName ?? agentID)
                        .font(.callout)
                    Spacer()
                    if statusFor(agentID) == .diverged {
                        Button("重新应用") { onReapply(agentID) }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                    Toggle("", isOn: Binding(
                        get: { true },
                        set: { _ in onToggleAgent(agentID, false) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
            }

            if !unmountedAgents.isEmpty {
                Menu {
                    ForEach(unmountedAgents, id: \.id) { agent in
                        Button(agent.displayName) { onToggleAgent(agent.id, true) }
                    }
                } label: {
                    Label("挂载到…", systemImage: "plus")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
            }

            Text(statusText.text)
                .font(.caption2)
                .foregroundStyle(statusText.isWarning ? Color.orange : Color.secondary)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .alert("重命名分组", isPresented: $isRenamePresented) {
            TextField("组名", text: $renameText)
            Button("确定") { onRename(renameText) }
            Button("取消", role: .cancel) {}
        }
    }

    private func statusDot(_ status: MountStatus) -> some View {
        Circle()
            .fill(status == .mounted ? Color.green : status == .diverged ? Color.orange : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
    }
}

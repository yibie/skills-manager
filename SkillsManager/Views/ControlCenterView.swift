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
    var mountReportFor: (CollectionRecord, String) -> MountReport? = { _, _ in nil }
    let onOpen: (CollectionRecord) -> Void
    let onCreate: (String) -> Void
    let onToggleAgent: (CollectionRecord, String, Bool) -> Void
    let onReapply: (CollectionRecord, String) -> Void
    let onRename: (CollectionRecord, String) -> Void
    let onDelete: (CollectionRecord, _ unmountFirst: Bool) -> Void

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
                        .buttonStyle(.borderedProminent)
                        .tint(ConsoleTheme.accent)
                }
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: ConsoleTheme.gridSpacing)], spacing: ConsoleTheme.gridSpacing) {
                    ForEach(collections, id: \.id) { collection in
                        CollectionCard(
                            collection: collection,
                            detectedAgents: detectedAgents,
                            statusFor: { statusFor(collection, $0) },
                            reportFor: { mountReportFor(collection, $0) },
                            onOpen: { onOpen(collection) },
                            onToggleAgent: { onToggleAgent(collection, $0, $1) },
                            onReapply: { onReapply(collection, $0) },
                            onRename: { onRename(collection, $0) },
                            onDelete: { onDelete(collection, $0) }
                        )
                    }
                    // 虚线「新建分组」卡收尾(草图 §5.2)
                    Button { isNamingPresented = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.title2)
                            Text("新建分组").font(.callout)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 170)
                        .background(
                            RoundedRectangle(cornerRadius: ConsoleTheme.cardRadius)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(ConsoleTheme.pageBackground)
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
    var reportFor: (String) -> MountReport? = { _ in nil }
    let onOpen: () -> Void
    let onToggleAgent: (String, Bool) -> Void
    let onReapply: (String) -> Void
    let onRename: (String) -> Void
    let onDelete: (_ unmountFirst: Bool) -> Void

    @State private var isRenamePresented = false
    @State private var renameText = ""
    @State private var isDeleteConfirmPresented = false

    private var unmountedAgents: [AgentDefinition] {
        detectedAgents.filter { !collection.mountedAgentIDs.contains($0.id) }
    }

    private var mountedAgentNames: [String] {
        collection.mountedAgentIDs.map { id in
            detectedAgents.first { $0.id == id }?.displayName ?? id
        }
    }

    private var deleteDialogMessage: String {
        if collection.mountedAgentIDs.isEmpty {
            return "技能本体保留在 Library,仅删除这个分组。"
        }
        return "该分组已挂载到:\(mountedAgentNames.joined(separator: "、"))。“卸载链接并删除”会先移除这些 agent 目录中的 symlink;“仅删除”会把链接留在磁盘上且不再受本应用管理。技能本体始终保留在 Library。"
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
        return ("\(names.joined(separator: "、"))：与磁盘不一致", true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button(collection.name, action: onOpen)
                    .buttonStyle(.plain)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("重命名…") {
                        renameText = collection.name
                        isRenamePresented = true
                    }
                    Divider()
                    Button("删除分组…", role: .destructive) { isDeleteConfirmPresented = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
            }
            Text("\(collection.memberSkillIDs.count) 个技能")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(collection.mountedAgentIDs, id: \.self) { agentID in
                HStack(spacing: 8) {
                    statusDot(statusFor(agentID))
                    Text(detectedAgents.first { $0.id == agentID }?.displayName ?? agentID)
                        .font(.callout)
                    if let report = reportFor(agentID), !report.skipped.isEmpty {
                        Text("成功 \(report.changed.count) · 跳过 \(report.skipped.count)")
                            .font(.caption2)
                            .foregroundStyle(ConsoleTheme.statusWarn)
                            .help(report.skipped.map { "\($0.skillID):\($0.reason)" }.joined(separator: "\n"))
                    }
                    Spacer()
                    if statusFor(agentID) == .diverged {
                        Button("重新应用") { onReapply(agentID) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Toggle("", isOn: Binding(
                        get: { true },
                        set: { _ in onToggleAgent(agentID, false) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(ConsoleTheme.accent)
                }
                .frame(height: ConsoleTheme.mountRowHeight)
            }

            if !unmountedAgents.isEmpty {
                if collection.memberSkillIDs.isEmpty {
                    Label("先添加技能再挂载", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .help("空分组没有可挂载内容")
                } else {
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
            }

            Spacer(minLength: 0)

            Text(statusText.text)
                .font(.caption2)
                .foregroundStyle(statusText.isWarning ? ConsoleTheme.statusWarn : Color.secondary)
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .paperCard()
        .frame(minHeight: 170)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .confirmationDialog(
            "删除分组“\(collection.name)”?",
            isPresented: $isDeleteConfirmPresented,
            titleVisibility: .visible
        ) {
            if collection.mountedAgentIDs.isEmpty {
                Button("删除分组", role: .destructive) { onDelete(false) }
            } else {
                Button("卸载链接并删除分组", role: .destructive) { onDelete(true) }
                Button("仅删除分组(保留磁盘链接)", role: .destructive) { onDelete(false) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteDialogMessage)
        }
        .alert("重命名分组", isPresented: $isRenamePresented) {
            TextField("组名", text: $renameText)
            Button("确定") { onRename(renameText) }
            Button("取消", role: .cancel) {}
        }
    }

    private func statusDot(_ status: MountStatus) -> some View {
        Circle()
            .fill(status == .mounted ? ConsoleTheme.statusOk : status == .diverged ? ConsoleTheme.statusWarn : ConsoleTheme.statusOff)
            .frame(width: 8, height: 8)
    }
}

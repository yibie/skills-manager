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
                skillMounts += CollectionSupport.resolveMemberIDs(collection.memberSkillIDs, skills: skills).members.count
                agents.insert(agentID)
            }
        }
        return String.localizedStringWithFormat(
            String(localized: "Collections: %lld · Mounted skills: %lld · Agents: %lld"),
            Int64(collections.count),
            Int64(skillMounts),
            Int64(agents.count)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Control Center").font(.title2).fontWeight(.semibold)
                    Spacer()
                    Button("＋ Create Collection") { isNamingPresented = true }
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
                            resolvedMemberCount: CollectionSupport.resolveMemberIDs(collection.memberSkillIDs, skills: skills).members.count,
                            missingCount: CollectionSupport.resolveMemberIDs(collection.memberSkillIDs, skills: skills).missingIDs.count,
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
                            Text("Create Collection").font(.callout)
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
        .navigationTitle("Control Center")
        .alert("Create Collection", isPresented: $isNamingPresented) {
            TextField("Collection Name", text: $newName)
            Button("Create") {
                onCreate(newName)
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
    }
}

// MARK: - 分组卡片

private struct CollectionCard: View {
    let collection: CollectionRecord
    let resolvedMemberCount: Int
    let missingCount: Int
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
            return String(localized: "Skills remain in the Library; only this Collection will be deleted.")
        }
        return String.localizedStringWithFormat(
            String(localized: "This Collection is mounted to: %@. “Unmount Links and Delete” removes those symlinks first; “Delete Only” leaves them on disk and unmanaged. Skills always remain in the Library."),
            mountedAgentNames.joined(separator: ", ")
        )
    }

    private var statusText: (text: String, isWarning: Bool) {
        guard !collection.mountedAgentIDs.isEmpty else { return (String(localized: "Not Mounted"), false) }
        guard resolvedMemberCount > 0 else {
            return (String(localized: "No Mountable Skills: mount intent cannot be applied"), true)
        }
        let notMounted = collection.mountedAgentIDs.filter { statusFor($0) != .mounted }
        if notMounted.isEmpty {
            let names = collection.mountedAgentIDs.compactMap { id in
                detectedAgents.first { $0.id == id }?.displayName
            }
            return (String.localizedStringWithFormat(String(localized: "Mounted to %@ · Healthy"), names.joined(separator: ", ")), false)
        }
        let names = notMounted.compactMap { id in detectedAgents.first { $0.id == id }?.displayName }
        return (String.localizedStringWithFormat(String(localized: "%@: Differs from Disk"), names.joined(separator: ", ")), true)
    }

    private var memberSummary: String {
        let members = String.localizedStringWithFormat(String(localized: "%lld skills"), Int64(collection.memberSkillIDs.count))
        guard missingCount > 0 else { return members }
        let missing = String.localizedStringWithFormat(String(localized: "%lld missing"), Int64(missingCount))
        return "\(members) · \(missing)"
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
                    Button("Rename…") {
                        renameText = collection.name
                        isRenamePresented = true
                    }
                    Divider()
                    Button("Delete Collection…", role: .destructive) { isDeleteConfirmPresented = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
            }
            Text(memberSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(collection.mountedAgentIDs, id: \.self) { agentID in
                HStack(spacing: 8) {
                    statusDot(statusFor(agentID))
                    Text(detectedAgents.first { $0.id == agentID }?.displayName ?? agentID)
                        .font(.callout)
                    if let report = reportFor(agentID), !report.skipped.isEmpty {
                        Text("Succeeded \(report.changed.count) · Skipped \(report.skipped.count)")
                            .font(.caption2)
                            .foregroundStyle(ConsoleTheme.statusWarn)
                            .help(report.skipped.map { "\($0.skillID):\($0.reason)" }.joined(separator: "\n"))
                    }
                    Spacer()
                    if statusFor(agentID) == .diverged {
                        Button("Reapply") { onReapply(agentID) }
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
                    .accessibilityLabel(Text("\(detectedAgents.first { $0.id == agentID }?.displayName ?? agentID) mount"))
                    .tint(ConsoleTheme.accent)
                }
                .frame(height: ConsoleTheme.mountRowHeight)
            }

            if !unmountedAgents.isEmpty {
                if resolvedMemberCount == 0 {
                    Label("Add Skills Before Mounting", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .help(missingCount > 0
                            ? String(localized: "Cannot mount while Collection members are missing.")
                            : String(localized: "An empty Collection has no mountable content."))
                } else {
                    Menu {
                        ForEach(unmountedAgents, id: \.id) { agent in
                            Button(agent.displayName) { onToggleAgent(agent.id, true) }
                        }
                    } label: {
                        Label("Mount To…", systemImage: "plus")
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
            "Delete “\(collection.name)”?",
            isPresented: $isDeleteConfirmPresented,
            titleVisibility: .visible
        ) {
            if collection.mountedAgentIDs.isEmpty {
                Button("Delete Collection", role: .destructive) { onDelete(false) }
            } else {
                Button("Unmount Links and Delete Collection", role: .destructive) { onDelete(true) }
                Button("Delete Collection Only (Keep Disk Links)", role: .destructive) { onDelete(false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteDialogMessage)
        }
        .alert("Rename Collection", isPresented: $isRenamePresented) {
            TextField("Collection Name", text: $renameText)
            Button("Rename") { onRename(renameText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func statusDot(_ status: MountStatus) -> some View {
        Circle()
            .fill(status == .mounted ? ConsoleTheme.statusOk : status == .diverged ? ConsoleTheme.statusWarn : ConsoleTheme.statusOff)
            .frame(width: 8, height: 8)
    }
}

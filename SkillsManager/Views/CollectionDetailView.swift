import SwiftUI

// MARK: - 组详情
// 头部:组名 + 成员数 + 各已检测 agent 的挂载开关(开 = symlink 进 agent,
// 关 = 仅移除链接,技能留库)。成员列表复用 SkillListView。

struct CollectionDetailView: View {
    let collection: CollectionRecord
    let skills: [Skill]
    let detectedAgents: [AgentDefinition]
    let statusFor: (String) -> MountStatus
    var reportFor: (String) -> MountReport? = { _ in nil }
    @Binding var selectedSkill: Skill?
    let onToggleAgent: (String, Bool) -> Void
    let onReapply: (String) -> Void
    let onAddMembers: ([String]) -> Void
    let onRemoveMember: (Skill) -> Void
    let onInstall: (Skill) async -> Void
    let onUninstall: (Skill) async -> Void
    var onMoveToTrash: (Skill) async -> Void = { _ in }
    let onToggleStar: (Skill) -> Void

    @State private var isPickerPresented = false

    private var resolution: CollectionSupport.Resolution {
        CollectionSupport.resolveMemberIDs(collection.memberSkillIDs, skills: skills)
    }

    private var memberIDs: Set<String> { Set(resolution.members.map(\.id)) }

    private var hasResolvedMembers: Bool { !resolution.members.isEmpty }

    /// 只显示已挂载的胶囊;其余 30+ 个 agent 收进「挂载到…」菜单,避免开关墙。
    private var mountedAgents: [AgentDefinition] {
        detectedAgents.filter { collection.mountedAgentIDs.contains($0.id) }
    }

    private var unmountedAgents: [AgentDefinition] {
        detectedAgents.filter { !collection.mountedAgentIDs.contains($0.id) }
    }

    private var missingCount: Int {
        resolution.missingIDs.count
    }

    private var memberSummary: String {
        let members = String.localizedStringWithFormat(String(localized: "%lld skills"), Int64(collection.memberSkillIDs.count))
        guard missingCount > 0 else { return members }
        let missing = String.localizedStringWithFormat(String(localized: "%lld missing"), Int64(missingCount))
        return "\(members) · \(missing)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(collection.name).font(.headline)
                    Text(memberSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("＋ Add Skills") { isPickerPresented = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                FlowLayout(hSpacing: 8, vSpacing: 8) {
                    ForEach(mountedAgents, id: \.id) { agent in
                        agentCapsule(agent)
                    }
                    if !unmountedAgents.isEmpty {
                        if !hasResolvedMembers {
                            Label("Add Skills Before Mounting", systemImage: "plus")
                                .font(.callout)
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
                                    .font(.callout)
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                }
                Text("Turning a switch on symlinks this Collection's skills into the agent; turning it off removes only the links and keeps the skills in the Library.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            if !hasResolvedMembers {
                ContentUnavailableView {
                    Label(missingCount > 0
                        ? String(localized: "Missing Collection Members")
                        : String(localized: "No Skills in This Collection"), systemImage: "tray")
                } description: {
                    Text(missingCount > 0
                        ? String(localized: "Add or restore skills before mounting this Collection to an agent.")
                        : String(localized: "Add skills before mounting this Collection to an agent."))
                } actions: {
                    Button("Add Skills") { isPickerPresented = true }
                }
            } else {
                SkillListView(
                    skills: skills,
                    filter: .collection(collection.id, name: collection.name),
                    memberIDs: memberIDs,
                    selectedSkill: $selectedSkill,
                    onInstall: onInstall,
                    onUninstall: onUninstall,
                    onMoveToTrash: onMoveToTrash,
                    onToggleStar: onToggleStar,
                    onRemoveFromCollection: onRemoveMember
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(collection.name)
        .onChange(of: memberIDs) {
            if let selectedSkill, !memberIDs.contains(selectedSkill.id) {
                self.selectedSkill = nil
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            MemberPicker(
                candidates: skills.filter { skill in
                    !collection.memberSkillIDs.contains {
                        CollectionSupport.memberID($0, matches: skill, skills: skills)
                    }
                },
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
            if mounted && status == .unmounted {
                Text("No Mountable Skills")
                    .font(.caption2)
                    .foregroundStyle(ConsoleTheme.statusWarn)
            }
            if let report = reportFor(agent.id), !report.skipped.isEmpty {
                Text("Succeeded \(report.changed.count) · Skipped \(report.skipped.count)")
                    .font(.caption2)
                    .foregroundStyle(ConsoleTheme.statusWarn)
                    .help(report.skipped.map { "\($0.skillID):\($0.reason)" }.joined(separator: "\n"))
            }
            if status == .diverged {
                Button("Reapply") { onReapply(agent.id) }
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
            .accessibilityLabel(Text("\(agent.displayName) mount"))
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
            .searchable(text: $searchText, prompt: "Search Skills")
            .navigationTitle("Add Skills")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") {
                        onAdd(selected.map(\.persistenceID))
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 440, height: 500)
    }
}

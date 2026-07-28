import SwiftUI

struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    let skills: [Skill]
    var discoverableCount: Int = 0
    var projectSkillCount: Int = 0
    var agentDocCount: Int = 0
    var conflictCount: Int = 0
    var currentProjectURL: URL? = nil
    var showsOnlyControlCenter = false

    @State private var isAgentsExpanded = false

    // Precomputed counts to avoid inline filtering in the view body
    private var allCount: Int { skills.count }
    private var starredCount: Int { skills.filter { $0.isStarred }.count }

    /// Union of: agents detected from registry + agents appearing in skill metadata.
    private var agentNames: [String] {
        guard !showsOnlyControlCenter else { return [] }
        let fromSkills = Set(skills.flatMap { $0.compatibleAgents })
        let fromRegistry = Set(AgentRegistry.installedAgents().map { $0.displayName })
        return fromSkills.union(fromRegistry).sorted()
    }

    private func agentCount(for agent: String) -> Int {
        skills.filter { $0.compatibleAgents.contains(agent) }.count
    }

    var body: some View {
        List(selection: $selectedFilter) {
            Section {
                SidebarRow(filter: .controlCenter, count: 0, selectedFilter: selectedFilter)
            }

            if !showsOnlyControlCenter {
                Section("Library") {
                    SidebarRow(filter: .discover, count: discoverableCount, selectedFilter: selectedFilter)
                    SidebarRow(filter: .all, count: allCount, selectedFilter: selectedFilter)
                    SidebarRow(filter: .starred, count: starredCount, selectedFilter: selectedFilter)
                    if conflictCount > 0 {
                        SidebarRow(filter: .conflicts, count: conflictCount, selectedFilter: selectedFilter)
                    }
                }

                if !agentNames.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $isAgentsExpanded) {
                            ForEach(agentNames, id: \.self) { agent in
                                SidebarRow(
                                    filter: .agent(agent),
                                    count: agentCount(for: agent),
                                    selectedFilter: selectedFilter,
                                    showsIcon: false
                                )
                            }
                        } label: {
                            Label("Agents", systemImage: "cpu")
                                .badge(agentNames.count)
                        }
                    }
                }

                if currentProjectURL != nil {
                    Section("Project") {
                        SidebarRow(filter: .project, count: projectSkillCount, selectedFilter: selectedFilter)
                        SidebarRow(filter: .agentDocs, count: agentDocCount, selectedFilter: selectedFilter)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Skills")
    }
}

// MARK: - Row subview

private struct SidebarRow: View {
    let filter: SidebarFilter
    let count: Int
    let selectedFilter: SidebarFilter
    var titleOverride: String? = nil
    var showsIcon: Bool = true

    var body: some View {
        Group {
            if showsIcon {
                Label(titleOverride ?? filter.title, systemImage: filter.icon)
            } else {
                Text(titleOverride ?? filter.title)
            }
        }
        .badge(count)
        .tag(filter)
    }
}

#if DEBUG
#Preview {
    @Previewable @State var filter: SidebarFilter = .all
    SidebarView(
        selectedFilter: $filter,
        skills: Skill.mockSkills,
        discoverableCount: 3,
        projectSkillCount: 2,
        agentDocCount: 5,
        currentProjectURL: URL(fileURLWithPath: "/Users/user/my-project")
    )
    .frame(width: 220, height: 600)
}
#endif

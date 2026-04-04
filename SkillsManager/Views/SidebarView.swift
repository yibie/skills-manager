import SwiftUI

struct SidebarView: View {
    @Binding var selectedFilter: SidebarFilter
    let skills: [Skill]

    // Precomputed counts to avoid inline filtering in the view body
    private var allCount: Int { skills.count }
    private var installedCount: Int { skills.filter { $0.installState == .installed }.count }
    private var starredCount: Int { skills.filter { $0.isStarred }.count }
    private var trialCount: Int { skills.filter { $0.installState == .trial }.count }

    private var agentNames: [String] {
        Array(Set(skills.flatMap { $0.compatibleAgents })).sorted()
    }

    private var pluginSources: [String] {
        var sources = Set<String>()
        for skill in skills {
            switch skill.source {
            case .plugin(let marketplace, _): sources.insert(marketplace)
            default: break
            }
        }
        return sources.sorted()
    }

    private func pluginCount(for marketplace: String) -> Int {
        skills.filter {
            if case .plugin(let m, _) = $0.source { return m == marketplace }
            return false
        }.count
    }

    private func agentCount(for agent: String) -> Int {
        skills.filter { $0.compatibleAgents.contains(agent) }.count
    }

    var body: some View {
        List(selection: $selectedFilter) {
            Section("Library") {
                SidebarRow(filter: .all, count: allCount, selectedFilter: selectedFilter)
                SidebarRow(filter: .installed, count: installedCount, selectedFilter: selectedFilter)
                SidebarRow(filter: .starred, count: starredCount, selectedFilter: selectedFilter)
                SidebarRow(filter: .trial, count: trialCount, selectedFilter: selectedFilter)
            }

            Section("Agents") {
                ForEach(agentNames, id: \.self) { agent in
                    SidebarRow(
                        filter: .agent(agent),
                        count: agentCount(for: agent),
                        selectedFilter: selectedFilter
                    )
                }
                if agentNames.isEmpty {
                    SidebarRow(filter: .agent("Claude Code"), count: 0, selectedFilter: selectedFilter)
                }
            }

            Section("Sources") {
                SidebarRow(filter: .source("Local"), count: skills.filter { $0.source == .local }.count, selectedFilter: selectedFilter)
                ForEach(pluginSources, id: \.self) { marketplace in
                    SidebarRow(
                        filter: .source(marketplace.capitalized),
                        count: pluginCount(for: marketplace),
                        selectedFilter: selectedFilter
                    )
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

    var body: some View {
        Label(filter.title, systemImage: filter.icon)
            .badge(count)
            .tag(filter)
    }
}

#Preview {
    @Previewable @State var filter: SidebarFilter = .all
    SidebarView(selectedFilter: $filter, skills: Skill.mockSkills)
        .frame(width: 220, height: 500)
}

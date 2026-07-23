import SwiftUI

struct DiscoverView: View {
    let category: DiscoverDirectoryCategory
    let skills: [DiscoverSkill]
    let totalCount: Int
    let installedSkills: [Skill]
    let isLoading: Bool
    let isSyncing: Bool
    let installingSkillIDs: Set<String>
    @Binding var selectedSkillID: String?
    let onSelectCategory: (DiscoverDirectoryCategory) async -> Void
    let onSearch: (String) async throws -> (skills: [DiscoverSkill], count: Int)
    let onLoadDetail: (DiscoverSkill) async -> Void
    let onTry: (DiscoverSkill) async -> Void
    let onInstall: (DiscoverSkill) async -> Void
    let onUninstall: (DiscoverSkill) async -> Void
    let onRefresh: () async -> Void
    let onTranslateLoaded: () async -> Void

    @State private var searchText = ""
    @State private var searchResults: [DiscoverSkill] = []
    @State private var searchResultCount = 0
    @State private var isSearching = false
    @State private var searchErrorMessage: String?
    @State private var selectedSource: String?
    @State private var isSourceMenuHovered = false

    private var activeSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleSkills: [DiscoverSkill] {
        activeSearchText.isEmpty ? skills : searchResults
    }

    private var visibleCount: Int {
        activeSearchText.isEmpty ? totalCount : searchResultCount
    }

    private var sourceCounts: [(source: String, count: Int)] {
        Dictionary(grouping: visibleSkills, by: \.source)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.source < $1.source }
    }

    private var filtered: [DiscoverSkill] {
        visibleSkills.filter { skill in
            let matchesSource = selectedSource == nil || skill.source == selectedSource
            return matchesSource
        }
    }

    private var emptyStateDescription: String {
        if let searchErrorMessage, !activeSearchText.isEmpty {
            return "Search failed: \(searchErrorMessage)"
        }
        if activeSearchText.isEmpty {
            return "No discoverable skills loaded from skills.sh."
        }
        return "No skills match \"\(searchText)\"."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(DiscoverDirectoryCategory.allCases) { discoverCategory in
                        CategoryChip(
                            label: discoverCategory.title,
                            isSelected: category == discoverCategory
                        ) {
                            Task { await onSelectCategory(discoverCategory) }
                        }
                    }
                }

                Spacer(minLength: 12)

                if !sourceCounts.isEmpty {
                    Menu {
                        Button {
                            selectedSource = nil
                        } label: {
                            if selectedSource == nil {
                                Label("All Sources (\(visibleCount))", systemImage: "checkmark")
                            } else {
                                Text("All Sources (\(visibleCount))")
                            }
                        }
                        Divider()
                        ForEach(sourceCounts, id: \.source) { source, count in
                            Button {
                                selectedSource = source
                            } label: {
                                if selectedSource == source {
                                    Label("\(source) (\(count))", systemImage: "checkmark")
                                } else {
                                    Text("\(source) (\(count))")
                                }
                            }
                        }
                    } label: {
                        Text("Sources")
                            .font(.caption)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isSourceMenuHovered ? Color.primary.opacity(0.05) : Color.secondary.opacity(0.1))
                            )
                            .overlay(alignment: .bottom) {
                                Capsule()
                                    .fill(Color.primary.opacity(isSourceMenuHovered ? 0.10 : 0))
                                    .frame(height: 2)
                            }
                            .foregroundStyle(Color.primary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .onHover { isHovered in
                        isSourceMenuHovered = isHovered
                    }
                    .animation(.easeInOut(duration: 0.12), value: isSourceMenuHovered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            if isLoading || isSearching {
                ProgressView(isSearching ? "Searching skills.sh..." : "Loading skills.sh...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    activeSearchText.isEmpty ? "No Skills" : "No Results",
                    systemImage: "magnifyingglass",
                    description: Text(emptyStateDescription)
                )
            } else {
                List(selection: $selectedSkillID) {
                    ForEach(filtered) { entry in
                        DiscoverSkillRow(
                            entry: entry,
                            isInstalled: installedSkills.contains(where: { $0.name == entry.skillId || $0.name == entry.name }),
                            isInstalling: installingSkillIDs.contains(entry.id),
                            onLoadDetail: { Task { await onLoadDetail(entry) } },
                            onTry: { Task { await onTry(entry) } },
                            onInstall: { Task { await onInstall(entry) } },
                            onUninstall: { Task { await onUninstall(entry) } }
                        )
                        .listRowSeparator(.hidden)
                        .tag(entry.id)
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search all skills.sh...")
        .navigationTitle("Discover")
        .onChange(of: filtered.map(\.id)) {
            if let selectedSkillID, !filtered.contains(where: { $0.id == selectedSkillID }) {
                self.selectedSkillID = nil
            }
        }
        .task(id: searchText) {
            let query = activeSearchText
            guard !query.isEmpty else {
                searchResults = []
                searchResultCount = 0
                searchErrorMessage = nil
                return
            }

            isSearching = true
            defer { isSearching = false }

            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                let result = try await onSearch(query)
                guard !Task.isCancelled else { return }
                searchResults = result.skills
                searchResultCount = result.count
                searchErrorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                searchResults = []
                searchResultCount = 0
                searchErrorMessage = error.localizedDescription
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await onTranslateLoaded() }
                } label: {
                    Label("Fill Missing Translations", systemImage: "globe")
                }
                .disabled(isLoading || skills.isEmpty)
                .help("Fill gaps not covered by the bundled translation catalog")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await onRefresh() }
                } label: {
                    if isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isSyncing)
                .help("Refresh skills.sh directory")
            }
        }
    }
}

private struct DiscoverSkillRow: View {
    let entry: DiscoverSkill
    let isInstalled: Bool
    let isInstalling: Bool
    let onLoadDetail: () -> Void
    let onTry: () -> Void
    let onInstall: () -> Void
    let onUninstall: () -> Void
    @State private var isConfirmingRemoval = false

    var body: some View {
        SkillCard(
            title: entry.name,
            description: entry.summary ?? ""
        ) {
            if entry.isDescriptionTranslated {
                SkillMetaBadge(text: "Translated", tint: .blue)
            }
            if isInstalled {
                SkillMetaBadge(text: "Installed", tint: .green)
            }
            SkillMetaBadge(text: sourceLabel, maxWidth: 96)
            SkillMetaBadge(text: compactInstalls, maxWidth: 84)
        } actions: {
            HStack(spacing: 8) {
                Button(isInstalled ? "Try Again" : "Try", action: onTry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if isInstalled {
                    Button("Remove from Library…") {
                        isConfirmingRemoval = true
                    }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                } else {
                    Button(action: onInstall) {
                        if isInstalling {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Installing")
                            }
                        } else {
                            Text("Install")
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isInstalling)
                }
            }
        }
        .task(id: entry.id) {
            if entry.summary == nil {
                onLoadDetail()
            }
        }
        .alert("Remove “\(entry.name)” from Library?", isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: onUninstall)
        } message: {
            Text("The detected lifecycle provider will remove this skill and its managed agent links.")
        }
    }

    private var sourceLabel: String {
        entry.source.split(separator: "/").last.map(String.init) ?? entry.source
    }

    private var compactInstalls: String {
        switch entry.installs {
        case 1_000_000...:
            let value = Double(entry.installs) / 1_000_000
            return "\(value.formatted(.number.precision(.fractionLength(value >= 10 ? 0 : 1))))M installs"
        case 1_000...:
            let value = Double(entry.installs) / 1_000
            return "\(value.formatted(.number.precision(.fractionLength(value >= 100 ? 0 : 1))))K installs"
        default:
            return "\(entry.installs.formatted()) installs"
        }
    }
}

struct DiscoverDetailView: View {
    let entry: DiscoverSkill?
    let isInstalled: Bool
    let isInstalling: Bool
    let installActivities: [DiscoverInstallActivity]
    let isTranslatingDescriptions: Bool
    let onLoadDetail: (DiscoverSkill) async -> Void
    let onTry: (DiscoverSkill) async -> Void
    let onInstall: (DiscoverSkill) async -> Void
    let onUninstall: (DiscoverSkill) async -> Void
    let onTranslate: (DiscoverSkill) async -> Void

    var body: some View {
        Group {
            if let entry {
                DiscoverDetailContent(
                    entry: entry,
                    isInstalled: isInstalled,
                    isInstalling: isInstalling,
                    installActivities: installActivities,
                    isTranslatingDescriptions: isTranslatingDescriptions,
                    onTry: { Task { await onTry(entry) } },
                    onInstall: { Task { await onInstall(entry) } },
                    onUninstall: { Task { await onUninstall(entry) } },
                    onTranslate: { Task { await onTranslate(entry) } }
                )
                .task(id: entry.id) {
                    if entry.summary == nil || entry.readmeExcerpt == nil {
                        await onLoadDetail(entry)
                    }
                }
            } else {
                if installActivities.isEmpty {
                    ContentUnavailableView(
                        "Select a Skill",
                        systemImage: "safari",
                        description: Text("Choose a skill from Discover to view its details.")
                    )
                } else {
                    DiscoverInstallActivityPanel(activities: installActivities, selectedSkillID: nil)
                        .padding(20)
                }
            }
        }
        .frame(minWidth: 320)
    }
}

private struct DiscoverDetailContent: View {
    let entry: DiscoverSkill
    let isInstalled: Bool
    let isInstalling: Bool
    let installActivities: [DiscoverInstallActivity]
    let isTranslatingDescriptions: Bool
    let onTry: () -> Void
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onTranslate: () -> Void
    @State private var isConfirmingRemoval = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .textSelection(.enabled)
                        Text(entry.source)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button(action: onTranslate) {
                            if isTranslatingDescriptions {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Translating")
                                }
                            } else {
                                Label("Translate Missing", systemImage: "globe")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTranslatingDescriptions || entry.summary == nil)
                        .help("Translate this summary only when the bundled translation catalog does not cover it")

                        Button(isInstalled ? "Try Again" : "Try Skill", action: onTry)
                            .buttonStyle(.bordered)

                        if isInstalled {
                            Button("Remove from Library…") {
                                isConfirmingRemoval = true
                            }
                                .buttonStyle(.bordered)
                                .tint(.red)
                        } else {
                            Button(action: onInstall) {
                                if isInstalling {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("Installing")
                                    }
                                } else {
                                    Text("Install")
                                }
                            }
                                .buttonStyle(.borderedProminent)
                                .disabled(isInstalling)
                        }
                    }
                }

                HStack(spacing: 8) {
                    detailBadge("skills.sh")
                    if entry.isDescriptionTranslated {
                        detailBadge("Translated", tint: .blue)
                    }
                    detailBadge("\(entry.installs.formatted()) installs")
                    detailBadge(entry.skillId)
                }

                HStack(spacing: 10) {
                    Link(destination: entry.detailURL) {
                        Label("Open on skills.sh", systemImage: "safari")
                    }
                    Link(destination: entry.repoURL) {
                        Label("Repository", systemImage: "arrow.up.forward.square")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let summary = entry.summary, !summary.isEmpty {
                    detailSection("Summary") {
                        Text(summary)
                            .textSelection(.enabled)
                    }
                }

                detailSection("Alternative CLI Command") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Skills Manager installs this skill natively. Use this command only when working outside the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.installCommand)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }

                if let excerpt = entry.readmeExcerpt, !excerpt.isEmpty {
                    detailSection("SKILL.md Excerpt") {
                        Text(excerpt)
                            .textSelection(.enabled)
                    }
                } else {
                    detailSection("SKILL.md Excerpt") {
                        Text("Loading detail content…")
                            .foregroundStyle(.secondary)
                    }
                }

                if !installActivities.isEmpty {
                    detailSection("Install Activity") {
                        DiscoverInstallActivityPanel(
                            activities: installActivities,
                            selectedSkillID: entry.id
                        )
                    }
                }
            }
            .padding(20)
        }
        .alert("Remove “\(entry.name)” from Library?", isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: onUninstall)
        } message: {
            Text("The detected lifecycle provider will remove this skill and its managed agent links.")
        }
    }

    private func detailBadge(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DiscoverInstallActivityPanel: View {
    let activities: [DiscoverInstallActivity]
    let selectedSkillID: String?

    private var enumeratedActivities: [(offset: Int, element: DiscoverInstallActivity)] {
        Array(activities.enumerated())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(enumeratedActivities, id: \.element.id) { item in
                DiscoverInstallActivityCard(
                    activity: item.element,
                    isSelected: item.element.skillID == selectedSkillID
                )
            }
        }
    }
}

private struct DiscoverInstallActivityCard: View {
    let activity: DiscoverInstallActivity
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(activity.skillName)
                    .font(.headline)
                statusBadge(for: activity.status)
                if isSelected {
                    Text("Selected")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                Spacer()
            }

            Text(activity.command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !activity.targetAgents.isEmpty {
                Text("Targets: \(activity.targetAgents.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(activity.log.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 88, maxHeight: 140)
            .padding(10)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(.secondary.opacity(isSelected ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusBadge(for status: DiscoverInstallStatus) -> some View {
        let tint: Color = switch status {
        case .queued: .secondary
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        }

        Text(status.rawValue.capitalized)
            .font(.caption2)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct CategoryChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.primary : Color.secondary.opacity(0.1), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DiscoverView(
        category: .allTime,
        skills: [
            DiscoverSkill(
                id: "vercel-labs/agent-skills:vercel-react-best-practices",
                source: "vercel-labs/agent-skills",
                skillId: "vercel-react-best-practices",
                name: "vercel-react-best-practices",
                installs: 261141,
                repoURL: URL(string: "https://github.com/vercel-labs/agent-skills")!,
                installCommand: "npx skills add https://github.com/vercel-labs/agent-skills --skill vercel-react-best-practices",
                baseDescription: nil,
                baseDescriptionLocale: "en",
                localizedDescription: nil,
                readmeExcerpt: nil
            )
        ],
        totalCount: 91573,
        installedSkills: [],
        isLoading: false,
        isSyncing: false,
        installingSkillIDs: [],
        selectedSkillID: .constant(nil),
        onSelectCategory: { _ in },
        onSearch: { _ in (skills: [], count: 0) },
        onLoadDetail: { _ in },
        onTry: { _ in },
        onInstall: { _ in },
        onUninstall: { _ in },
        onRefresh: {},
        onTranslateLoaded: {}
    )
    .frame(width: 700, height: 600)
}

struct DiscoverTryView: View {
    let skill: DiscoverSkill
    let onInstall: () -> Void

    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.llmProviderKey) private var providerRaw = LLMProvider.claude.rawValue
    @AppStorage(AppSettings.sandboxModelKey) private var claudeModel = AppSettings.defaultModel
    @AppStorage(AppSettings.openAIModelKey) private var openAIModel = AppSettings.defaultOpenAIModel
    @AppStorage(AppSettings.openAIBaseURLKey) private var openAIBaseURL = ""
    @AppStorage(AppSettings.openRouterModelKey) private var openRouterModel = AppSettings.defaultOpenRouterModel
    @AppStorage(AppSettings.ollamaBaseURLKey) private var ollamaURL = ""
    @AppStorage(AppSettings.ollamaModelKey) private var ollamaModel = AppSettings.defaultOllamaModel
    @AppStorage(AppSettings.lmStudioBaseURLKey) private var lmStudioURL = ""
    @AppStorage(AppSettings.lmStudioModelKey) private var lmStudioModel = AppSettings.defaultLMStudioModel

    @State private var prompt = ""
    @State private var output: String?
    @State private var errorMessage: String?
    @State private var isRunning = false

    private let llmService = LLMService()

    private var activeProvider: LLMProvider {
        LLMProvider(rawValue: providerRaw) ?? .claude
    }

    private var llmConfig: LLMConfig {
        switch activeProvider {
        case .claude:
            return LLMConfig(provider: .claude, apiKey: KeychainService.string(forKey: AppSettings.claudeApiKeyKey) ?? "", model: claudeModel, baseURL: "")
        case .openAI:
            return LLMConfig(provider: .openAI, apiKey: KeychainService.string(forKey: AppSettings.openAIApiKeyKey) ?? "", model: openAIModel, baseURL: openAIBaseURL)
        case .openRouter:
            return LLMConfig(provider: .openRouter, apiKey: KeychainService.string(forKey: AppSettings.openRouterApiKeyKey) ?? "", model: openRouterModel, baseURL: "")
        case .ollama:
            return LLMConfig(
                provider: .ollama,
                apiKey: "",
                model: ollamaModel,
                baseURL: ollamaURL.isEmpty ? LLMProvider.ollama.defaultBaseURL : ollamaURL
            )
        case .lmStudio:
            return LLMConfig(
                provider: .lmStudio,
                apiKey: "",
                model: lmStudioModel,
                baseURL: lmStudioURL.isEmpty ? LLMProvider.lmStudio.defaultBaseURL : lmStudioURL
            )
        }
    }

    private var needsAPIKey: Bool {
        activeProvider.requiresApiKey && llmConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var systemPrompt: String {
        [
            "You are testing whether the following coding skill would improve an assistant's response for the user's task.",
            "",
            "Repository: \(skill.source)",
            "Skill ID: \(skill.skillId)",
            "",
            "Summary:",
            skill.summary ?? "No summary available.",
            "",
            "Skill Excerpt:",
            skill.readmeExcerpt ?? "No SKILL.md excerpt available.",
            "",
            "Use the material above as the skill context. Respond as if this skill were active."
        ].joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 820, height: 620)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Try Skill")
                    .font(.headline)
                Text(skill.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(skill.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var content: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test Prompt")
                        .font(.headline)
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Describe a task you want this skill to help with...")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $prompt)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                    }
                    .frame(minHeight: 160)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator, lineWidth: 1)
                    )
                }

                if needsAPIKey {
                    Label("No API key configured for the current provider. Add one in Settings (⌘,).", systemImage: "key.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Skill Context")
                        .font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let summary = skill.summary, !summary.isEmpty {
                                contextBlock(title: "Summary", body: summary)
                            }
                            if let excerpt = skill.readmeExcerpt, !excerpt.isEmpty {
                                contextBlock(title: "SKILL.md Excerpt", body: excerpt)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 340)
            .padding(20)

            VStack(alignment: .leading, spacing: 12) {
                Text("Result")
                    .font(.headline)

                Group {
                    if isRunning {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Running test...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage {
                        ScrollView {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if let output, !output.isEmpty {
                        ScrollView {
                            Text(output)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Result Yet",
                            systemImage: "text.bubble",
                            description: Text("Run a test prompt to see how this skill influences the response.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .frame(minWidth: 320)
            .padding(20)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(activeProvider.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Install Instead") {
                dismiss()
                onInstall()
            }
            .buttonStyle(.bordered)

            Button {
                Task { await runTry() }
            } label: {
                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Running")
                    }
                } else {
                    Text(output == nil ? "Run Try" : "Try Again")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                isRunning
                || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || needsAPIKey
            )
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func contextBlock(title: String, body: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(body)
                .font(monospaced ? .system(.caption, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func runTry() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        await MainActor.run {
            isRunning = true
            errorMessage = nil
        }

        do {
            let result = try await llmService.complete(
                prompt: trimmedPrompt,
                systemPrompt: systemPrompt,
                config: llmConfig
            )
            await MainActor.run {
                output = result
                isRunning = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                output = nil
                isRunning = false
            }
        }
    }
}

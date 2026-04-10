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
    let onLoadDetail: (DiscoverSkill) async -> Void
    let onTry: (DiscoverSkill) async -> Void
    let onInstall: (DiscoverSkill) async -> Void
    let onUninstall: (DiscoverSkill) async -> Void
    let onRefresh: () async -> Void

    @State private var searchText = ""
    @State private var selectedSource: String?
    @State private var isSourceMenuHovered = false

    private var sourceCounts: [(source: String, count: Int)] {
        Dictionary(grouping: skills, by: \.source)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.source < $1.source }
    }

    private var filtered: [DiscoverSkill] {
        skills.filter { skill in
            let matchesSearch = searchText.isEmpty
                || skill.name.localizedCaseInsensitiveContains(searchText)
                || skill.skillId.localizedCaseInsensitiveContains(searchText)
                || skill.source.localizedCaseInsensitiveContains(searchText)
                || (skill.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesSource = selectedSource == nil || skill.source == selectedSource
            return matchesSearch && matchesSource
        }
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
                                Label("All Sources (\(totalCount))", systemImage: "checkmark")
                            } else {
                                Text("All Sources (\(totalCount))")
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

            if isLoading {
                ProgressView("Loading skills.sh...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Skills" : "No Results",
                    systemImage: "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "No discoverable skills loaded from skills.sh."
                            : "No skills match \"\(searchText)\"."
                    )
                )
            } else {
                List(selection: $selectedSkillID) {
                    ForEach(filtered) { entry in
                        DiscoverSkillRow(
                            entry: entry,
                            isInstalled: installedSkills.contains(where: { $0.name == entry.skillId || $0.name == entry.name }),
                            isInstalling: installingSkillIDs.contains(entry.id),
                            onTry: { Task { await onTry(entry) } },
                            onInstall: { Task { await onInstall(entry) } },
                            onUninstall: { Task { await onUninstall(entry) } }
                        )
                        .tag(entry.id)
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search skills.sh...")
        .navigationTitle("Discover")
        .onChange(of: filtered.map(\.id)) {
            if let selectedSkillID, !filtered.contains(where: { $0.id == selectedSkillID }) {
                self.selectedSkillID = nil
            }
        }
        .toolbar {
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
    let onTry: () -> Void
    let onInstall: () -> Void
    let onUninstall: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if isInstalled {
                        Text("Installed")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.10), in: Capsule())
                    }
                }
                Text(entry.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(entry.installs.formatted()) installs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(isInstalled ? "Try Again" : "Try", action: onTry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if isInstalled {
                    Button("Uninstall", action: onUninstall)
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
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                .frame(height: 2)
                .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

struct DiscoverDetailView: View {
    let entry: DiscoverSkill?
    let isInstalled: Bool
    let isInstalling: Bool
    let installActivities: [DiscoverInstallActivity]
    let onLoadDetail: (DiscoverSkill) async -> Void
    let onTry: (DiscoverSkill) async -> Void
    let onInstall: (DiscoverSkill) async -> Void
    let onUninstall: (DiscoverSkill) async -> Void

    var body: some View {
        Group {
            if let entry {
                DiscoverDetailContent(
                    entry: entry,
                    isInstalled: isInstalled,
                    isInstalling: isInstalling,
                    installActivities: installActivities,
                    onTry: { Task { await onTry(entry) } },
                    onInstall: { Task { await onInstall(entry) } },
                    onUninstall: { Task { await onUninstall(entry) } }
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
    let onTry: () -> Void
    let onInstall: () -> Void
    let onUninstall: () -> Void

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
                        Button(isInstalled ? "Try Again" : "Try Skill", action: onTry)
                            .buttonStyle(.bordered)

                        if isInstalled {
                            Button("Uninstall", action: onUninstall)
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

                detailSection("Install Command") {
                    Text(entry.installCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
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
    }

    private func detailBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
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
                summary: nil,
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
        onLoadDetail: { _ in },
        onTry: { _ in },
        onInstall: { _ in },
        onUninstall: { _ in },
        onRefresh: {}
    )
    .frame(width: 700, height: 600)
}

struct DiscoverTryView: View {
    let skill: DiscoverSkill
    let onInstall: () -> Void

    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.llmProviderKey) private var providerRaw = LLMProvider.claude.rawValue
    @AppStorage(AppSettings.claudeApiKeyKey) private var claudeKey = ""
    @AppStorage(AppSettings.sandboxModelKey) private var claudeModel = AppSettings.defaultModel
    @AppStorage(AppSettings.openAIApiKeyKey) private var openAIKey = ""
    @AppStorage(AppSettings.openAIModelKey) private var openAIModel = AppSettings.defaultOpenAIModel
    @AppStorage(AppSettings.openAIBaseURLKey) private var openAIBaseURL = ""
    @AppStorage(AppSettings.openRouterApiKeyKey) private var openRouterKey = ""
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
            return LLMConfig(provider: .claude, apiKey: claudeKey, model: claudeModel, baseURL: "")
        case .openAI:
            return LLMConfig(provider: .openAI, apiKey: openAIKey, model: openAIModel, baseURL: openAIBaseURL)
        case .openRouter:
            return LLMConfig(provider: .openRouter, apiKey: openRouterKey, model: openRouterModel, baseURL: "")
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
            "Install Command: \(skill.installCommand)",
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
                            contextBlock(title: "Install Command", body: skill.installCommand, monospaced: true)
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

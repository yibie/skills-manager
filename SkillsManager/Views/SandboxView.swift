import SwiftUI

struct SandboxView: View {
    let availableSkills: [Skill]
    let onKeep: (Skill) async -> Void
    var onDismiss: (() -> Void)? = nil

    @AppStorage(AppSettings.llmProviderKey)      private var providerRaw  = LLMProvider.claude.rawValue
    @AppStorage(AppSettings.claudeApiKeyKey)     private var claudeKey    = ""
    @AppStorage(AppSettings.sandboxModelKey)     private var claudeModel  = AppSettings.defaultModel
    @AppStorage(AppSettings.openAIApiKeyKey)     private var openAIKey    = ""
    @AppStorage(AppSettings.openAIModelKey)      private var openAIModel  = AppSettings.defaultOpenAIModel
    @AppStorage(AppSettings.openAIBaseURLKey)    private var openAIBaseURL = ""
    @AppStorage(AppSettings.openRouterApiKeyKey) private var orKey        = ""
    @AppStorage(AppSettings.openRouterModelKey)  private var orModel      = AppSettings.defaultOpenRouterModel
    @AppStorage(AppSettings.ollamaBaseURLKey)    private var ollamaURL    = ""
    @AppStorage(AppSettings.ollamaModelKey)      private var ollamaModel  = AppSettings.defaultOllamaModel
    @AppStorage(AppSettings.lmStudioBaseURLKey)  private var lmURL        = ""
    @AppStorage(AppSettings.lmStudioModelKey)    private var lmModel      = AppSettings.defaultLMStudioModel

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
            return LLMConfig(provider: .openRouter, apiKey: orKey, model: orModel, baseURL: "")
        case .ollama:
            return LLMConfig(provider: .ollama, apiKey: "", model: ollamaModel,
                             baseURL: ollamaURL.isEmpty ? LLMProvider.ollama.defaultBaseURL : ollamaURL)
        case .lmStudio:
            return LLMConfig(provider: .lmStudio, apiKey: "", model: lmModel,
                             baseURL: lmURL.isEmpty ? LLMProvider.lmStudio.defaultBaseURL : lmURL)
        }
    }

    private var needsApiKey: Bool {
        activeProvider.requiresApiKey && llmConfig.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @State private var slots: [SandboxSlot]
    @State private var prompt: String = ""

    private let llmService = LLMService()
    private let initialSkill: Skill?

    private var isRunning: Bool {
        slots.contains { $0.isLoading }
    }

    private var hasSkillSelected: Bool {
        slots.contains { $0.skill != nil }
    }

    private var isPreview: Bool {
        guard let skill = initialSkill else { return false }
        return skill.id.hasPrefix("preview:")
    }

    /// For preview skills, returns the plugin name (e.g. "document-skills") rather
    /// than the first skill's display name (e.g. "theme-factory").
    private var actionBarLabel: String {
        guard let skill = initialSkill else { return "" }
        if case .plugin(_, let pluginName) = skill.source, isPreview {
            return pluginName
        }
        return skill.displayName
    }

    /// Merged skill list: initialSkill (if not already present) + all installed skills.
    private var effectiveSkills: [Skill] {
        var skills = availableSkills
        if let initial = initialSkill, !skills.contains(where: { $0.id == initial.id }) {
            skills.insert(initial, at: 0)
        }
        return skills
    }

    init(
        initialSkill: Skill?,
        availableSkills: [Skill],
        onKeep: @escaping (Skill) async -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.initialSkill = initialSkill
        self.availableSkills = availableSkills
        self.onKeep = onKeep
        self.onDismiss = onDismiss
        // For multi-skill plugins, don't pre-select — the sub-skill name (e.g. "theme-factory")
        // has no relation to what the user clicked, so let them pick explicitly.
        let pCount = availableSkills.filter { $0.id.hasPrefix("preview:") }.count
        let preselect = pCount <= 1 ? initialSkill : nil
        _slots = State(initialValue: [SandboxSlot(skill: preselect)])
    }

    private var previewCount: Int {
        availableSkills.filter { $0.id.hasPrefix("preview:") }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            promptSection
            Divider()
            if isPreview && previewCount > 1 {
                pluginHeader
                Divider()
            }
            slotSection
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if initialSkill != nil { actionBar }
        }
        .navigationTitle("Sandbox")
    }

    // MARK: - Plugin Header

    private var pluginHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(actionBarLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("The skills below are all part of this collection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.secondary.opacity(0.05))
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Enter a prompt to test your skills...")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $prompt)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .frame(minHeight: 72, maxHeight: 120)
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            )

            HStack(spacing: 12) {
                if needsApiKey {
                    Label("No API key \u{2014} add one in Settings (\u{2318},)", systemImage: "key.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    runAll()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(
                    prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isRunning
                    || !hasSkillSelected
                )
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
    }

    // MARK: - Slot Section

    private var slotSection: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(slots) { slot in
                        SlotCard(
                            slot: slot,
                            availableSkills: effectiveSkills,
                            canRemove: slots.count > 1,
                            onRemove: { slots.removeAll { $0.id == slot.id } }
                        )
                        .frame(
                            width: slots.count == 1
                                ? max(320, geo.size.width - 40)
                                : 340
                        )
                    }

                    addSlotButton
                }
                .padding(20)
                .frame(minHeight: geo.size.height)
            }
        }
    }

    private var addSlotButton: some View {
        Button {
            slots.append(SandboxSlot())
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Add Slot")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(width: 80)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(.separator)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if initialSkill != nil {
                    Label(actionBarLabel, systemImage: "flask")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Close") { onDismiss?() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                if isPreview {
                    Button("Install") {
                        if let skill = initialSkill {
                            Task {
                                await onKeep(skill)
                                onDismiss?()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    // MARK: - Run

    private func runAll() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for slot in slots where slot.skill != nil {
            guard let skill = slot.skill else { continue }
            Task { await run(slot: slot, skill: skill, prompt: trimmed) }
        }
    }

    private func run(slot: SandboxSlot, skill: Skill, prompt: String) async {
        let config = llmConfig
        await MainActor.run {
            slot.isLoading = true
            slot.output = nil
            slot.error = nil
        }
        do {
            let result = try await llmService.complete(
                prompt: prompt,
                systemPrompt: skill.markdownContent,
                config: config
            )
            await MainActor.run {
                slot.output = result
                slot.isLoading = false
            }
        } catch {
            await MainActor.run {
                slot.error = error.localizedDescription
                slot.isLoading = false
            }
        }
    }
}

// MARK: - SlotCard

private struct SlotCard: View {
    let slot: SandboxSlot
    let availableSkills: [Skill]
    let canRemove: Bool
    let onRemove: () -> Void

    /// Ensures the slot's current skill is always in the picker list,
    /// even if it's a preview skill not in the installed set.
    private var pickerSkills: [Skill] {
        var skills = availableSkills
        if let current = slot.skill, !skills.contains(where: { $0.id == current.id }) {
            skills.insert(current, at: 0)
        }
        return skills
    }

    private var previewPickerSkills: [Skill] {
        pickerSkills.filter { $0.id.hasPrefix("preview:") }
    }

    private var installedPickerSkills: [Skill] {
        pickerSkills.filter { !$0.id.hasPrefix("preview:") }
    }

    /// Plugin name derived from the first preview skill's source, used as section header.
    private var previewPluginName: String? {
        guard let first = previewPickerSkills.first,
              case .plugin(_, let pluginName) = first.source else { return nil }
        return pluginName
    }

    private var skillIDBinding: Binding<String> {
        Binding(
            get: { slot.skill?.id ?? "" },
            set: { id in slot.skill = pickerSkills.first { $0.id == id } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Divider()
            cardBody
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Picker("Skill", selection: skillIDBinding) {
                Text("Select a skill...").tag("")
                if !previewPickerSkills.isEmpty {
                    Section(previewPluginName ?? "This Plugin") {
                        ForEach(previewPickerSkills) { skill in
                            Text(skill.displayName).tag(skill.id)
                        }
                    }
                }
                if !installedPickerSkills.isEmpty {
                    Section("Installed") {
                        ForEach(installedPickerSkills) { skill in
                            Text(skill.displayName).tag(skill.id)
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Spacer()

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove slot")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.secondary.opacity(0.05))
    }

    @ViewBuilder
    private var cardBody: some View {
        if slot.isLoading {
            VStack(spacing: 8) {
                ProgressView()
                Text("Running...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else if let error = slot.error {
            VStack(alignment: .leading, spacing: 6) {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let output = slot.output {
            ScrollView {
                Text(output)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
                Text("Run a prompt to see output")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
    }
}

#Preview {
    SandboxView(
        initialSkill: Skill.mockSkills.first,
        availableSkills: Skill.mockSkills,
        onKeep: { _ in }
    )
    .frame(width: 700, height: 600)
}

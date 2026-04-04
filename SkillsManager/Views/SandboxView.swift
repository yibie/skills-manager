import SwiftUI

struct SandboxView: View {
    let availableSkills: [Skill]
    let onKeep: (Skill) async -> Void

    @AppStorage(AppSettings.claudeApiKeyKey) private var apiKey: String = ""
    @AppStorage(AppSettings.sandboxModelKey) private var model: String = AppSettings.defaultModel

    @State private var slots: [SandboxSlot]
    @State private var prompt: String = ""

    private let llmService = LLMService()
    @Environment(\.dismiss) private var dismiss

    private var isRunning: Bool {
        slots.contains { $0.isLoading }
    }

    init(initialSkill: Skill?, availableSkills: [Skill], onKeep: @escaping (Skill) async -> Void) {
        _slots = State(initialValue: [
            SandboxSlot(skill: initialSkill),
            SandboxSlot()
        ])
        self.availableSkills = availableSkills
        self.onKeep = onKeep
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Try Sandbox")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            // Prompt input
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Enter a prompt to test with your skills...")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $prompt)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 60, maxHeight: 100)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    )

                    Button {
                        runAll()
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning
                    )
                    .keyboardShortcut(.return, modifiers: .command)
                }

                if apiKey.isEmpty {
                    Label(
                        "No API key — add one in Settings (⌘,)",
                        systemImage: "key.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Slot grid
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(slots) { slot in
                        SlotCard(
                            slot: slot,
                            availableSkills: availableSkills,
                            canRemove: slots.count > 1,
                            onKeep: {
                                if let skill = slot.skill {
                                    Task { await onKeep(skill) }
                                }
                            },
                            onDiscard: {
                                slot.output = nil
                                slot.error = nil
                            },
                            onRemove: {
                                slots.removeAll { $0.id == slot.id }
                            }
                        )
                        .frame(width: 300, alignment: .top)
                    }

                    // Add slot
                    Button {
                        slots.append(SandboxSlot())
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.title2)
                            Text("Add Slot")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 100)
                        .padding(.vertical, 40)
                        .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
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
        await MainActor.run {
            slot.isLoading = true
            slot.output = nil
            slot.error = nil
        }
        do {
            let result = try await llmService.complete(
                prompt: prompt,
                systemPrompt: skill.markdownContent,
                apiKey: apiKey,
                model: model
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
    let onKeep: () -> Void
    let onDiscard: () -> Void
    let onRemove: () -> Void

    private var skillIDBinding: Binding<String> {
        Binding(
            get: { slot.skill?.id ?? "" },
            set: { id in slot.skill = availableSkills.first { $0.id == id } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: skill picker + remove button
            HStack {
                Picker("Skill", selection: skillIDBinding) {
                    Text("Select a skill...").tag("")
                    ForEach(availableSkills) { skill in
                        Text(skill.displayName).tag(skill.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()

                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove slot")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.secondary.opacity(0.06))

            Divider()

            // Output body
            Group {
                if slot.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                } else if let error = slot.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let output = slot.output {
                    ScrollView {
                        Text(output)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } else {
                    Text("Output will appear here after running.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(20)
                }
            }
            .frame(minHeight: 200)

            // Footer: Keep / Discard — shown only when output is available
            if slot.output != nil {
                Divider()
                HStack {
                    Button("Keep", action: onKeep)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Discard", action: onDiscard)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

#Preview {
    SandboxView(
        initialSkill: Skill.mockSkills.first,
        availableSkills: Skill.mockSkills,
        onKeep: { _ in }
    )
}

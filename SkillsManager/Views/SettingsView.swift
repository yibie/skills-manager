import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.llmProviderKey)      private var providerRaw   = LLMProvider.claude.rawValue
    // Claude
    @AppStorage(AppSettings.claudeApiKeyKey)     private var claudeKey     = ""
    @AppStorage(AppSettings.sandboxModelKey)     private var claudeModel   = AppSettings.defaultModel
    // OpenAI
    @AppStorage(AppSettings.openAIApiKeyKey)     private var openAIKey     = ""
    @AppStorage(AppSettings.openAIModelKey)      private var openAIModel   = AppSettings.defaultOpenAIModel
    @AppStorage(AppSettings.openAIBaseURLKey)    private var openAIBaseURL = ""
    // OpenRouter
    @AppStorage(AppSettings.openRouterApiKeyKey) private var orKey         = ""
    @AppStorage(AppSettings.openRouterModelKey)  private var orModel       = AppSettings.defaultOpenRouterModel
    // Ollama
    @AppStorage(AppSettings.ollamaBaseURLKey)    private var ollamaURL     = ""
    @AppStorage(AppSettings.ollamaModelKey)      private var ollamaModel   = AppSettings.defaultOllamaModel
    // LM Studio
    @AppStorage(AppSettings.lmStudioBaseURLKey)  private var lmURL         = ""
    @AppStorage(AppSettings.lmStudioModelKey)    private var lmModel       = AppSettings.defaultLMStudioModel

    private var provider: LLMProvider {
        LLMProvider(rawValue: providerRaw) ?? .claude
    }

    var body: some View {
        Form {
            Section("LLM Provider") {
                LabeledContent("Provider") {
                    Picker("Provider", selection: $providerRaw) {
                        ForEach(LLMProvider.allCases, id: \.rawValue) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 220)
                }
            }

            switch provider {
            case .claude:
                claudeSection
            case .openAI:
                openAISection
            case .openRouter:
                openRouterSection
            case .ollama:
                ollamaSection
            case .lmStudio:
                lmStudioSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .padding()
        .navigationTitle("Settings")
        .animation(.default, value: providerRaw)
    }

    // MARK: - Provider sections

    private var claudeSection: some View {
        Section("Claude API") {
            LabeledContent("API Key") {
                SecureField("sk-ant-...", text: $claudeKey)
                    .frame(width: 280)
            }
            LabeledContent("Model") {
                Picker("Model", selection: $claudeModel) {
                    Text("claude-haiku-4-5 (Fast)").tag("claude-haiku-4-5")
                    Text("claude-sonnet-4-5 (Balanced)").tag("claude-sonnet-4-5")
                    Text("claude-opus-4-5 (Best)").tag("claude-opus-4-5")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 220)
            }
        }
    }

    private var openAISection: some View {
        Section("OpenAI API") {
            LabeledContent("API Key") {
                SecureField("sk-...", text: $openAIKey)
                    .frame(width: 280)
            }
            LabeledContent("Model") {
                TextField("e.g. gpt-4o-mini", text: $openAIModel)
                    .frame(width: 280)
            }
            LabeledContent("Base URL") {
                TextField("https://api.openai.com/v1 (or compatible)", text: $openAIBaseURL)
                    .frame(width: 280)
            }
            LabeledContent("") {
                Text("Leave Base URL empty to use the official OpenAI endpoint. Set a custom URL for compatible services.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 280, alignment: .leading)
            }
        }
    }

    private var openRouterSection: some View {
        Section("OpenRouter") {
            LabeledContent("API Key") {
                SecureField("sk-or-...", text: $orKey)
                    .frame(width: 280)
            }
            LabeledContent("Model") {
                TextField("e.g. openai/gpt-4o-mini", text: $orModel)
                    .frame(width: 280)
            }
            LabeledContent("") {
                Link("Browse models at openrouter.ai",
                     destination: URL(string: "https://openrouter.ai/models")!)
                    .font(.caption)
            }
        }
    }

    private var ollamaSection: some View {
        Section("Ollama") {
            LabeledContent("Base URL") {
                TextField(LLMProvider.ollama.defaultBaseURL, text: $ollamaURL)
                    .frame(width: 280)
            }
            LabeledContent("Model") {
                TextField("e.g. llama3", text: $ollamaModel)
                    .frame(width: 280)
            }
            LabeledContent("") {
                Text("Make sure Ollama is running locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lmStudioSection: some View {
        Section("LM Studio") {
            LabeledContent("Base URL") {
                TextField(LLMProvider.lmStudio.defaultBaseURL, text: $lmURL)
                    .frame(width: 280)
            }
            LabeledContent("Model") {
                TextField("e.g. local-model", text: $lmModel)
                    .frame(width: 280)
            }
            LabeledContent("") {
                Text("Start a local server in LM Studio first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SettingsView()
}

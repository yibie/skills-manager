import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.claudeApiKeyKey) private var apiKey = ""
    @AppStorage(AppSettings.sandboxModelKey) private var model = AppSettings.defaultModel

    var body: some View {
        Form {
            Section("Claude API") {
                LabeledContent("API Key") {
                    SecureField("sk-ant-...", text: $apiKey)
                        .frame(width: 280)
                }
                LabeledContent("Model") {
                    Picker("Model", selection: $model) {
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
        .formStyle(.grouped)
        .frame(width: 500)
        .padding()
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView()
}

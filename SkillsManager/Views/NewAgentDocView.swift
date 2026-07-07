import SwiftUI

struct NewAgentDocView: View {
    let onCreate: (String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var templates = AgentDocTemplateService().templates()
    @State private var selectedTemplate: AgentDocTemplate?
    @State private var fileName = ""
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            List(selection: $selectedTemplate) {
                ForEach(templates) { template in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.name)
                        Text(template.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(template)
                }
            }
            .listStyle(.inset)
            .onChange(of: selectedTemplate) {
                fileName = selectedTemplate?.fileName ?? fileName
            }

            Divider()
            footer
        }
        .frame(width: 360, height: 460)
        .task {
            if selectedTemplate == nil {
                selectedTemplate = templates.first
                fileName = templates.first?.fileName ?? "SOUL.md"
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Agent Doc")
                    .font(.headline)
                Text("Choose a template")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Templates Folder") {
                AgentDocTemplateService().openUserTemplatesFolder()
                templates = AgentDocTemplateService().templates()
            }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            TextField("File name", text: $fileName)
                .textFieldStyle(.roundedBorder)
            Button("Create") {
                guard let selectedTemplate else { return }
                isCreating = true
                Task {
                    await onCreate(fileName, selectedTemplate.content)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTemplate == nil || fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

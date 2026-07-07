import MarkdownView
import SwiftUI

struct AgentDocsView: View {
    let projectURL: URL?
    let docs: [AgentDoc]
    let statuses: [AgentDocTargetStatus]
    let isLoading: Bool
    let isSyncing: Bool
    @Binding var selectedDoc: AgentDoc?
    let onRefresh: () async -> Void
    let onSync: () async -> Void
    let onNew: () -> Void
    let onTargets: () -> Void
    let onOpen: (AgentDoc) -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if projectURL == nil {
                ContentUnavailableView("No Project Open", systemImage: "folder", description: Text("Open a project to manage agent docs."))
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if docs.isEmpty {
                ContentUnavailableView("No Agent Docs", systemImage: "doc.text", description: Text("Create a document from a template."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedDoc) {
                    ForEach(docs) { doc in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(doc.file)
                            Spacer()
                            Button("Open") { onOpen(doc) }
                                .buttonStyle(.borderless)
                        }
                        .tag(doc)
                    }
                }
                .listStyle(.plain)
            }

            Divider()
            statusBar
        }
        .navigationTitle("Agent Docs")
        .task { await onRefresh() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                onNew()
            } label: {
                Label("New", systemImage: "plus")
            }
            .disabled(projectURL == nil)

            Button {
                onTargets()
            } label: {
                Label("Targets", systemImage: "checklist")
            }
            .disabled(projectURL == nil)

            Button {
                Task { await onSync() }
            } label: {
                if isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(projectURL == nil || isSyncing)

            Spacer()

            Button {
                Task { await onRefresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(projectURL == nil || isLoading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(12)
    }

    private var statusBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if statuses.isEmpty {
                    Text("No targets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(statuses) { status in
                        AgentDocStatusPill(status: status)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

struct AgentDocDetailView: View {
    let doc: AgentDoc?

    var body: some View {
        Group {
            if let doc {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(doc.file)
                            .font(.title2)
                            .bold()
                            .textSelection(.enabled)
                        Divider()
                        MarkdownView(doc.content)
                            .textSelection(.enabled)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a Document", systemImage: "doc.text")
            }
        }
        .frame(minWidth: 320)
    }
}

private struct AgentDocStatusPill: View {
    let status: AgentDocTargetStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.entryFile)
            Text(status.state.label)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .help(status.agentIDs.joined(separator: ", "))
    }

    private var color: Color {
        switch status.state {
        case .inSync: .green
        case .outOfSync: .orange
        case .notSynced: .secondary
        case .missingEntryFile: .red
        }
    }
}

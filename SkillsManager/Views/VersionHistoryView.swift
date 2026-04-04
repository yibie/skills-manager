import SwiftUI

struct VersionHistoryView: View {
    let commits: [GitCommit]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCommit: GitCommit?

    var body: some View {
        NavigationStack {
            Group {
                if commits.isEmpty {
                    emptyState
                } else {
                    commitList
                }
            }
            .navigationTitle("Version History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedCommit) { commit in
                CommitDiffView(commit: commit)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No History",
            systemImage: "clock.arrow.circlepath",
            description: Text("No commits found for this skill.")
        )
    }

    private var commitList: some View {
        List(commits) { commit in
            CommitRow(commit: commit)
                .contentShape(Rectangle())
                .onTapGesture { selectedCommit = commit }
        }
        .listStyle(.plain)
    }
}

// MARK: - Commit row

private struct CommitRow: View {
    let commit: GitCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commit.message)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(commit.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(commit.hash.prefix(7))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Diff placeholder sheet

private struct CommitDiffView: View {
    let commit: GitCommit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Hash") {
                        Text(commit.hash)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Date") {
                        Text(commit.date, style: .date)
                    }
                    LabeledContent("Message") {
                        Text(commit.message)
                            .textSelection(.enabled)
                    }
                    Divider()
                    Text("Diff viewer coming soon.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(String(commit.hash.prefix(7)))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 300)
    }
}

// MARK: - Preview

#Preview {
    VersionHistoryView(commits: [
        GitCommit(hash: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2", message: "feat: add context awareness to commit skill", date: .now.addingTimeInterval(-3600)),
        GitCommit(hash: "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3", message: "fix: handle empty staging area gracefully", date: .now.addingTimeInterval(-86400)),
        GitCommit(hash: "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4", message: "Initial version", date: .now.addingTimeInterval(-172800)),
    ])
}

#Preview("Empty") {
    VersionHistoryView(commits: [])
}

import SwiftUI

struct DiscoverView: View {
    let plugins: [MarketplacePlugin]
    let isLoading: Bool
    let isSyncing: Bool
    let onInstall: (MarketplacePlugin) async -> Void
    let onUninstall: (MarketplacePlugin) async -> Void
    let onRefresh: () async -> Void
    var onTrySandbox: ((MarketplacePlugin) async -> Void)? = nil

    @State private var searchText = ""
    @State private var selectedCategory: String?

    private var filtered: [MarketplacePlugin] {
        plugins.filter { plugin in
            let matchesSearch = searchText.isEmpty
                || plugin.name.localizedCaseInsensitiveContains(searchText)
                || plugin.description.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil
                || plugin.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    private var categories: [String] {
        Array(Set(plugins.compactMap { $0.category })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(label: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(categories, id: \.self) { cat in
                            CategoryChip(label: cat.capitalized, isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                Divider()
            }

            if isLoading {
                ProgressView("Loading marketplace...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Plugins" : "No Results",
                    systemImage: "safari",
                    description: Text(
                        searchText.isEmpty
                            ? "No marketplace plugins found."
                            : "No plugins match \"\(searchText)\"."
                    )
                )
            } else {
                List(filtered) { plugin in
                    PluginRow(
                        plugin: plugin,
                        onInstall: { Task { await onInstall(plugin) } },
                        onUninstall: { Task { await onUninstall(plugin) } },
                        onTrySandbox: onTrySandbox.map { handler in { Task { await handler(plugin) } } }
                    )
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $searchText, prompt: "Search plugins...")
        .navigationTitle("Discover")
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
                .help("Sync marketplace from GitHub")
            }
        }
    }
}

private struct PluginRow: View {
    let plugin: MarketplacePlugin
    let onInstall: () -> Void
    let onUninstall: () -> Void
    var onTrySandbox: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(plugin.marketplace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onTrySandbox {
                    Button("Try", action: onTrySandbox)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if plugin.isInstalled {
                    Button("Uninstall", action: onUninstall)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                } else {
                    Button("Install", action: onInstall)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            Text(plugin.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let cat = plugin.category {
                Text(cat.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 4)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.1),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DiscoverView(
        plugins: [
            MarketplacePlugin(
                id: "claude-plugins-official:superpowers",
                name: "superpowers",
                description: "Core skills library: TDD, debugging, collaboration patterns",
                marketplace: "claude-plugins-official",
                category: "development",
                homepage: URL(string: "https://github.com/obra/superpowers"),
                sourceType: .localPath("./plugins/superpowers"),
                skills: [],
                isInstalled: true,
                installedVersion: "5.0.7"
            ),
            MarketplacePlugin(
                id: "claude-plugins-official:code-review",
                name: "code-review",
                description: "Automated code review with best practice checks",
                marketplace: "claude-plugins-official",
                category: "development",
                homepage: nil,
                sourceType: .localPath("./plugins/code-review"),
                skills: [],
                isInstalled: false,
                installedVersion: nil
            ),
        ],
        isLoading: false,
        isSyncing: false,
        onInstall: { _ in },
        onUninstall: { _ in },
        onRefresh: {}
    )
    .frame(width: 500, height: 600)
}

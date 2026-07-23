import AppKit
import Foundation

struct AgentDocTemplateService {
    private let fileManager: FileManager
    private let userTemplatesURL: URL

    init(
        fileManager: FileManager = .default,
        userTemplatesURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userTemplatesURL = userTemplatesURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".skills-manager/templates")
    }

    func templates() -> [AgentDocTemplate] {
        (bundledTemplates() + userTemplates()).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func openUserTemplatesFolder() {
        try? fileManager.createDirectory(at: userTemplatesURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(userTemplatesURL)
    }

    private func bundledTemplates() -> [AgentDocTemplate] {
        resourceBundles.flatMap { bundle in
            Self.templateSubdirectories.flatMap { subdirectory in
                bundle.urls(forResourcesWithExtension: "txt", subdirectory: subdirectory) ?? []
            }
        }
        .compactMap(template(from:))
    }

    private func userTemplates() -> [AgentDocTemplate] {
        guard let urls = try? fileManager.contentsOfDirectory(at: userTemplatesURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.filter { $0.pathExtension.lowercased() == "md" }.compactMap(template(from:))
    }

    private func template(from url: URL) -> AgentDocTemplate? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fileName = url.pathExtension == "txt"
            ? "\(url.deletingPathExtension().lastPathComponent).md"
            : url.lastPathComponent
        return AgentDocTemplate(
            name: url.deletingPathExtension().lastPathComponent,
            fileName: fileName,
            content: content
        )
    }

    private var resourceBundles: [Bundle] {
        [Bundle.main]
    }

    private static let templateSubdirectories: [String?] = [
        nil,
        "AgentDocTemplates",
        "Resources/AgentDocTemplates",
    ]
}

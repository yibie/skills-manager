import Foundation

/// Star state shared with the terminal UI via `~/.skills-manager/tui-state.json`.
///
/// The TUI owns this file and stars skills by bare name; the app reads and writes the
/// same file so stars stay in sync across both frontends. Unknown keys in the JSON
/// object are preserved on write.
enum SharedStarredState {
    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".skills-manager/tui-state.json")
    }

    static func starredNames(fileURL: URL = defaultFileURL) -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let starred = object["starred"] as? [String] else {
            return []
        }
        return Set(starred)
    }

    static func setStarred(_ isStarred: Bool, skillName: String, fileURL: URL = defaultFileURL) {
        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = existing
        }

        var starred = (object["starred"] as? [String]) ?? []
        if isStarred {
            if !starred.contains(skillName) { starred.append(skillName) }
        } else {
            starred.removeAll { $0 == skillName }
        }
        object["starred"] = starred

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Star sync is best-effort; the in-app state still updates.
            print("SharedStarredState: failed to write \(fileURL.path()): \(error)")
        }
    }
}

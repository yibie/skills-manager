import CryptoKit
import Foundation

struct AgentDocsSnapshot: Sendable {
    var docs: [AgentDoc]
    var manifest: AgentDocsManifest
    var statuses: [AgentDocTargetStatus]
}

enum AgentDocsServiceError: LocalizedError {
    case singleManagedMarker(String)

    var errorDescription: String? {
        switch self {
        case .singleManagedMarker(let file):
            "Managed block in \(file) has only one marker."
        }
    }
}

struct AgentDocsService {
    static let docsDirectoryName = "agent-docs"
    static let manifestFileName = "manifest.json"
    static let beginMarker = "<!-- skills-manager:agent-docs:begin -->"
    static let endMarker = "<!-- skills-manager:agent-docs:end -->"

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(projectURL: URL) throws -> AgentDocsSnapshot {
        guard fileManager.fileExists(atPath: docsURL(projectURL).path) else {
            return AgentDocsSnapshot(docs: [], manifest: AgentDocsManifest(), statuses: [])
        }
        var manifest = try loadManifest(projectURL: projectURL)
        let docs = try scanDocs(projectURL: projectURL)
        manifest.docs = docs.map { AgentDocsManifest.Doc(file: $0.file) }
        if manifest.targets.isEmpty {
            manifest.targets = AgentEntryFileRegistry.detectedTargets(in: projectURL, fileManager: fileManager)
                .map { AgentDocsManifest.Target(agentId: $0.agentId, entryFile: $0.entryFile, mode: .inject) }
        }
        try saveManifest(manifest, projectURL: projectURL)
        return AgentDocsSnapshot(
            docs: docs,
            manifest: manifest,
            statuses: try statuses(projectURL: projectURL, docs: docs, manifest: manifest)
        )
    }

    func createDoc(projectURL: URL, fileName: String, content: String) throws -> AgentDocsSnapshot {
        try fileManager.createDirectory(at: docsURL(projectURL), withIntermediateDirectories: true)
        let safeName = sanitizedMarkdownFileName(fileName)
        try content.write(to: docsURL(projectURL).appendingPathComponent(safeName), atomically: true, encoding: .utf8)
        return try load(projectURL: projectURL)
    }

    func updateTargets(projectURL: URL, targets: [AgentDocsManifest.Target]) throws -> AgentDocsSnapshot {
        try fileManager.createDirectory(at: docsURL(projectURL), withIntermediateDirectories: true)
        var manifest = try loadManifest(projectURL: projectURL)
        manifest.targets = dedupeTargets(targets)
        try saveManifest(manifest, projectURL: projectURL)
        return try load(projectURL: projectURL)
    }

    func sync(projectURL: URL) throws -> AgentDocsSnapshot {
        let docs = try scanDocs(projectURL: projectURL)
        var manifest = try loadManifest(projectURL: projectURL)
        let now = Date()
        let grouped = Dictionary(grouping: manifest.targets, by: { physicalEntryFile(projectURL: projectURL, entryFile: $0.entryFile) })

        for (_, targets) in grouped {
            guard let first = targets.first else { continue }
            let expected = renderManagedBlock(projectURL: projectURL, docs: docs, mode: first.mode)
            try writeManagedBlock(expected, to: projectURL.appendingPathComponent(first.entryFile), entryFile: first.entryFile)
            let hash = Self.sha256(expected)
            for target in targets {
                if let index = manifest.targets.firstIndex(where: { $0.agentId == target.agentId }) {
                    manifest.targets[index].mode = first.mode
                    manifest.targets[index].lastSync = AgentDocsManifest.LastSync(hash: hash, syncedAt: now)
                }
            }
        }

        manifest.docs = docs.map { AgentDocsManifest.Doc(file: $0.file) }
        try saveManifest(manifest, projectURL: projectURL)
        return AgentDocsSnapshot(
            docs: docs,
            manifest: manifest,
            statuses: try statuses(projectURL: projectURL, docs: docs, manifest: manifest)
        )
    }

    func statuses(projectURL: URL, docs: [AgentDoc], manifest: AgentDocsManifest) throws -> [AgentDocTargetStatus] {
        try groupedTargets(manifest.targets, projectURL: projectURL).map { group in
            let expected = renderManagedBlock(projectURL: projectURL, docs: docs, mode: group.mode)
            let entryURL = projectURL.appendingPathComponent(group.entryFile)
            let state: AgentDocTargetState
            if !fileManager.fileExists(atPath: entryURL.path) {
                state = .missingEntryFile
            } else {
                let content = try String(contentsOf: entryURL, encoding: .utf8)
                if let actual = try? extractManagedBlock(from: content, entryFile: group.entryFile) {
                    state = actual == expected ? .inSync : .outOfSync
                } else if group.hasLastSync {
                    state = .outOfSync
                } else {
                    state = .notSynced
                }
            }
            return AgentDocTargetStatus(
                agentIDs: group.agentIDs,
                entryFile: group.entryFile,
                mode: group.mode,
                state: state
            )
        }
        .sorted { $0.entryFile.localizedCaseInsensitiveCompare($1.entryFile) == .orderedAscending }
    }

    func renderManagedBlock(projectURL: URL, docs: [AgentDoc], mode: AgentDocSyncMode) -> String {
        let body: String
        switch mode {
        case .inject:
            body = docs.map { doc in
                "<!-- source: \(Self.docsDirectoryName)/\(doc.file) -->\n\(doc.content.trimmingCharacters(in: .whitespacesAndNewlines))"
            }.joined(separator: "\n\n")
        case .reference:
            let links = docs.map { "- [\($0.file)](\(Self.docsDirectoryName)/\($0.file))" }.joined(separator: "\n")
            body = "Read the following documents before working in this project:\n\n\(links)"
        }
        return "\(Self.beginMarker)\n\(body)\n\(Self.endMarker)"
    }

    func extractManagedBlock(from content: String, entryFile: String) throws -> String? {
        let beginCount = content.components(separatedBy: Self.beginMarker).count - 1
        let endCount = content.components(separatedBy: Self.endMarker).count - 1
        guard beginCount == endCount else { throw AgentDocsServiceError.singleManagedMarker(entryFile) }
        guard beginCount > 0 else { return nil }
        guard let begin = content.range(of: Self.beginMarker),
              let end = content.range(of: Self.endMarker, range: begin.upperBound..<content.endIndex)
        else {
            throw AgentDocsServiceError.singleManagedMarker(entryFile)
        }
        return String(content[begin.lowerBound..<end.upperBound])
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func scanDocs(projectURL: URL) throws -> [AgentDoc] {
        let dir = docsURL(projectURL)
        guard let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return try entries
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                AgentDoc(file: url.lastPathComponent, url: url, content: try String(contentsOf: url, encoding: .utf8))
            }
    }

    private func loadManifest(projectURL: URL) throws -> AgentDocsManifest {
        let url = manifestURL(projectURL)
        guard fileManager.fileExists(atPath: url.path) else { return AgentDocsManifest() }
        return try decoder.decode(AgentDocsManifest.self, from: Data(contentsOf: url))
    }

    private func saveManifest(_ manifest: AgentDocsManifest, projectURL: URL) throws {
        try fileManager.createDirectory(at: docsURL(projectURL), withIntermediateDirectories: true)
        try encoder.encode(manifest).write(to: manifestURL(projectURL), options: [.atomic])
    }

    private func writeManagedBlock(_ block: String, to url: URL, entryFile: String) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try block.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        _ = try extractManagedBlock(from: content, entryFile: entryFile)
        let updated: String
        if let begin = content.range(of: Self.beginMarker),
           let end = content.range(of: Self.endMarker, range: begin.upperBound..<content.endIndex) {
            updated = content.replacingCharacters(in: begin.lowerBound..<end.upperBound, with: block)
        } else {
            updated = content.trimmingCharacters(in: .newlines) + "\n\n" + block + "\n"
        }
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private func groupedTargets(_ targets: [AgentDocsManifest.Target], projectURL: URL) -> [TargetGroup] {
        Dictionary(grouping: targets, by: { physicalEntryFile(projectURL: projectURL, entryFile: $0.entryFile) })
            .values
            .compactMap { targets in
                guard let first = targets.first else { return nil }
                return TargetGroup(
                    agentIDs: targets.map(\.agentId).sorted(),
                    entryFile: first.entryFile,
                    mode: first.mode,
                    hasLastSync: targets.contains { $0.lastSync != nil }
                )
            }
    }

    private func dedupeTargets(_ targets: [AgentDocsManifest.Target]) -> [AgentDocsManifest.Target] {
        var seen = Set<String>()
        return targets.filter { seen.insert($0.agentId).inserted }
    }

    private func physicalEntryFile(projectURL: URL, entryFile: String) -> String {
        projectURL.appendingPathComponent(entryFile).resolvingSymlinksInPath().path
    }

    private func docsURL(_ projectURL: URL) -> URL {
        projectURL.appendingPathComponent(Self.docsDirectoryName)
    }

    private func manifestURL(_ projectURL: URL) -> URL {
        docsURL(projectURL).appendingPathComponent(Self.manifestFileName)
    }

    private func sanitizedMarkdownFileName(_ fileName: String) -> String {
        let base = fileName.split(separator: "/").last.map(String.init) ?? "DOC.md"
        return base.lowercased().hasSuffix(".md") ? base : "\(base).md"
    }
}

private struct TargetGroup {
    var agentIDs: [String]
    var entryFile: String
    var mode: AgentDocSyncMode
    var hasLastSync: Bool
}

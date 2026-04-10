import Foundation
import Observation

@Observable
@MainActor
final class SkillStore {
    typealias DiscoverInstaller = @Sendable (DiscoverSkill, [String], @escaping @Sendable (String) -> Void) async throws -> Void

    // MARK: - State

    var skills: [Skill] = []
    var discoverableSkills: [DiscoverSkill] = []
    var discoverableSkillDetails: [String: DiscoverSkill] = [:]
    var discoverableSkillTotal: Int = 0
    var discoverCategory: DiscoverDirectoryCategory = .allTime
    var discoverInstallActivities: [DiscoverInstallActivity] = []
    var projectSkills: [Skill] = []
    var currentProjectURL: URL?
    var isLoading = false
    var isLoadingDiscover = false
    var isLoadingProject = false
    var isSyncing = false
    var errorMessage: String?

    // MARK: - Services

    private let claudeAdapter: ClaudeCodeAdapter
    private let universalAdapter: UniversalAdapter
    private let directoryService: SkillsDirectoryService
    private let discoverInstaller: DiscoverInstaller
    private var loadingDiscoverSkillDetails = Set<String>()

    init(
        claudeAdapter: ClaudeCodeAdapter = ClaudeCodeAdapter(),
        universalAdapter: UniversalAdapter = UniversalAdapter(),
        directoryService: SkillsDirectoryService = SkillsDirectoryService(),
        discoverInstaller: DiscoverInstaller? = nil
    ) {
        self.claudeAdapter = claudeAdapter
        self.universalAdapter = universalAdapter
        self.directoryService = directoryService
        self.discoverInstaller = discoverInstaller ?? SkillStore.defaultDiscoverInstaller
    }

    // MARK: - Local skills

    func reloadSkills() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let claudeSkills = claudeAdapter.scanSkills()
            async let universalSkills = universalAdapter.scanSkills()
            let (claude, universal) = try await (claudeSkills, universalSkills)
            var seen = Set<String>()
            var merged: [Skill] = []
            for skill in claude + universal {
                if seen.insert(skill.id).inserted { merged.append(skill) }
            }
            skills = merged
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func merge(records: [SkillRecord]) {
        let lookup = Dictionary(uniqueKeysWithValues: records.map { ($0.skillID, $0) })
        for index in skills.indices {
            let id = skills[index].id
            if let record = lookup[id] {
                skills[index].isStarred = record.isStarred
                skills[index].installState = InstallState(rawValue: record.installState) ?? .notInstalled
            }
        }
    }

    // MARK: - Discover (skills.sh)

    func reloadDiscoverableSkillsDirectory() async {
        isLoadingDiscover = true
        defer { isLoadingDiscover = false }
        do {
            let directory = try await directoryService.loadSkillsDirectory(category: discoverCategory)
            discoverableSkills = directory.skills
            discoverableSkillTotal = directory.total
            let validIDs = Set(directory.skills.map(\.id))
            discoverableSkillDetails = discoverableSkillDetails.filter { validIDs.contains($0.key) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDiscoverCategory(_ category: DiscoverDirectoryCategory) async {
        guard discoverCategory != category else { return }
        discoverCategory = category
        discoverableSkills = []
        discoverableSkillDetails = [:]
        discoverableSkillTotal = 0
        await reloadDiscoverableSkillsDirectory()
    }

    func refreshDiscoverableSkillsDirectory() async {
        isSyncing = true
        defer { isSyncing = false }
        await reloadDiscoverableSkillsDirectory()
    }

    func loadDiscoverSkillDetail(_ skill: DiscoverSkill) async {
        if discoverableSkillDetails[skill.id] != nil || loadingDiscoverSkillDetails.contains(skill.id) {
            return
        }

        loadingDiscoverSkillDetails.insert(skill.id)
        defer { loadingDiscoverSkillDetails.remove(skill.id) }

        do {
            discoverableSkillDetails[skill.id] = try await directoryService.loadSkillDetail(skill)
        } catch {
            // Keep discover browsing resilient even if a detail page changes.
        }
    }

    func installDiscoverSkill(_ skill: DiscoverSkill, agentIDs: [String]) async {
        guard !agentIDs.isEmpty else { return }
        guard !isInstallingDiscoverSkill(skill) else { return }

        let activityID = "\(skill.id):\(UUID().uuidString)"
        upsertDiscoverInstallActivity(
            DiscoverInstallActivity(
                id: activityID,
                skillID: skill.id,
                skillName: skill.name,
                targetAgents: agentIDs,
                command: skill.installCommand,
                startedAt: Date(),
                finishedAt: nil,
                status: .running,
                log: ["Queued install for \(skill.name) to \(agentIDs.joined(separator: ", "))"]
            )
        )

        do {
            appendDiscoverInstallLog("Starting install using `\(skill.installCommand)`", activityID: activityID)
            try await discoverInstaller(skill, agentIDs) { [weak self] line in
                guard let self else { return }
                Task { @MainActor in
                    self.appendDiscoverInstallLog(line, activityID: activityID)
                }
            }
            await reloadSkills()
            finishDiscoverInstallActivity(activityID: activityID, status: .succeeded, finalMessage: "Install completed for \(agentIDs.joined(separator: ", "))")
        } catch {
            finishDiscoverInstallActivity(activityID: activityID, status: .failed, finalMessage: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func installDiscoverSkill(_ skill: DiscoverSkill) async {
        let defaultAgents = AgentRegistry.installedAgents().contains(where: { $0.id == "claude-code" }) ? ["claude-code"] : []
        await installDiscoverSkill(skill, agentIDs: defaultAgents)
    }

    func uninstallDiscoverSkill(_ skill: DiscoverSkill) async {
        guard let installed = skills.first(where: { $0.name == skill.skillId || $0.name == skill.name }) else { return }
        await uninstallSkill(installed)
    }

    func isInstallingDiscoverSkill(_ skill: DiscoverSkill) -> Bool {
        discoverInstallActivities.contains { $0.skillID == skill.id && $0.status == .running }
    }

    func discoverInstallActivity(for skillID: String) -> DiscoverInstallActivity? {
        discoverInstallActivities.first { $0.skillID == skillID }
    }

    func orderedDiscoverInstallActivities(prioritizing skillID: String?) -> [DiscoverInstallActivity] {
        discoverInstallActivities.sorted { lhs, rhs in
            let lhsPriority = lhs.skillID == skillID ? 0 : 1
            let rhsPriority = rhs.skillID == skillID ? 0 : 1
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.startedAt > rhs.startedAt
        }
    }

    // MARK: - Skill-level install/uninstall

    /// Marks a skill as installed (trial → keep, or re-install state).
    func installSkill(_ skill: Skill) async {
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index].installState = .installed
        }
    }

    /// Deletes the skill from disk and removes it from the list immediately.
    func uninstallSkill(_ skill: Skill) async {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        switch skill.source {
        case .local:
            let skillsBase = home.appendingPathComponent(".claude/skills").standardized
            let target = skill.directoryPath.standardized
            if target.path.hasPrefix(skillsBase.path + "/") {
                do { try fm.removeItem(at: target) } catch { errorMessage = error.localizedDescription }
            } else if skill.canonicalPath != nil {
                do { try SymlinkInstaller.uninstall(skillName: skill.name) } catch { errorMessage = error.localizedDescription }
            }
        case .plugin(let pluginSource, let pluginName):
            // Delete the skill's own subdirectory inside the local plugin cache.
            // skill.directoryPath is e.g. ~/.claude/plugins/cache/{pluginSource}/{plugin}/{version}/skills/{skillName}
            // We only remove that leaf directory — the cached plugin bundle remains usable.
            let cacheBase = home.appendingPathComponent(".claude/plugins/cache").standardized
            let target = skill.directoryPath.standardized
            if target.path.hasPrefix(cacheBase.path + "/\(pluginSource)/\(pluginName)/") {
                do { try fm.removeItem(at: target) } catch { errorMessage = error.localizedDescription }
            }
        case .symlinked:
            // Remove the symlink in ~/.claude/skills/ but leave the target intact
            let skillsBase = home.appendingPathComponent(".claude/skills").standardized
            let target = skill.directoryPath.standardized
            if target.path.hasPrefix(skillsBase.path + "/") {
                do { try fm.removeItem(at: target) } catch { errorMessage = error.localizedDescription }
            }
        case .projectLocal:
            // Project-local skills are not managed here; use Promote instead
            return
        }

        // Remove from memory immediately — row disappears without a reload
        skills.removeAll { $0.id == skill.id }
    }

    /// Convenience batch variant used by multi-select.
    func uninstallSkills(_ batch: [Skill]) async {
        for skill in batch { await uninstallSkill(skill) }
    }

    func installSkills(_ batch: [Skill]) async {
        for skill in batch { await installSkill(skill) }
    }

    // MARK: - Install to agents via SymlinkInstaller

    func installSkillToAgents(_ skill: Skill, agentIDs: [String]) async {
        do {
            try SymlinkInstaller.install(
                content: skill.markdownContent,
                skillName: skill.name,
                agentIDs: agentIDs
            )
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Project skills

    func openProject(url: URL) async {
        currentProjectURL = url
        await loadProjectSkills()
    }

    func loadProjectSkills() async {
        guard let projectURL = currentProjectURL else {
            projectSkills = []
            return
        }
        isLoadingProject = true
        defer { isLoadingProject = false }
        // Run filesystem scan on a background thread to avoid blocking the MainActor.
        // Skill is Sendable so the result crosses the actor boundary safely.
        let results = await Task.detached(priority: .userInitiated) {
            ProjectScanner().scan(projectURL: projectURL)
        }.value
        projectSkills = results
    }

    /// Copies a project-local skill to ~/.claude/skills/.
    /// Converts .mdc → SKILL.md format if needed.
    func promoteSkill(_ skill: Skill) async {
        // Use displayName (from frontmatter name: field) for a more meaningful directory name.
        // Falls back to skill.name if displayName equals the raw directory name.
        let destDirName = skill.displayName.isEmpty ? skill.name : skill.displayName
        let skillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills/\(destDirName)")
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: skillsDir.path) {
                try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            }
            let destFile = skillsDir.appendingPathComponent("SKILL.md")
            let content: String
            if skill.filePath.pathExtension == "mdc" {
                content = SkillFormatConverter.toSKILLMD(
                    name: skill.name,
                    mdcContent: skill.markdownContent
                )
            } else {
                content = try String(contentsOf: skill.filePath, encoding: .utf8)
            }
            try content.write(to: destFile, atomically: true, encoding: .utf8)
            await reloadSkills()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsertDiscoverInstallActivity(_ activity: DiscoverInstallActivity) {
        discoverInstallActivities.removeAll { $0.id == activity.id }
        discoverInstallActivities.insert(activity, at: 0)
        if discoverInstallActivities.count > 20 {
            discoverInstallActivities = Array(discoverInstallActivities.prefix(20))
        }
    }

    private func appendDiscoverInstallLog(_ line: String, activityID: String) {
        guard let index = discoverInstallActivities.firstIndex(where: { $0.id == activityID }) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        discoverInstallActivities[index].log.append(trimmed)
    }

    private func finishDiscoverInstallActivity(activityID: String, status: DiscoverInstallStatus, finalMessage: String) {
        guard let index = discoverInstallActivities.firstIndex(where: { $0.id == activityID }) else { return }
        let trimmed = finalMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            discoverInstallActivities[index].log.append(trimmed)
        }
        discoverInstallActivities[index].status = status
        discoverInstallActivities[index].finishedAt = Date()
    }

    private static func defaultDiscoverInstaller(_ skill: DiscoverSkill, agentIDs: [String], appendLog: @escaping @Sendable (String) -> Void) async throws {
        for agentID in agentIDs {
            appendLog("Installing to \(agentID)")
            try await runCommand(
                "npx",
                args: [
                    "-y",
                    "skills",
                    "add",
                    skill.repoURL.absoluteString,
                    "--skill",
                    skill.skillId,
                    "--yes",
                    "--global",
                    "--agent",
                    agentID
                ],
                appendLog: appendLog
            )
        }
    }

    private static func runCommand(_ command: String, args: [String], appendLog: @escaping @Sendable (String) -> Void) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        guard let executablePath = ExecutableLocator.resolve(command: command, homePath: home.path) else {
            throw SkillStoreProcessError.missingExecutable(command)
        }

        let environment = ExecutableLocator.buildEnvironment(
            homePath: home.path,
            resolvedExecutable: executablePath
        )

        try await runProcess(
            executablePath,
            args: args,
            currentDirectory: home,
            environment: environment,
            appendLog: appendLog
        )
    }

    private static func runProcess(
        _ exec: String,
        args: [String],
        currentDirectory: URL,
        environment: [String: String],
        appendLog: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            let state = ProcessRunState()

            process.executableURL = URL(fileURLWithPath: exec)
            process.arguments = args
            process.currentDirectoryURL = currentDirectory
            process.environment = environment
            process.standardOutput = outPipe
            process.standardError = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                appendLog(text)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                appendLog(text)
            }
            process.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let errData = errPipe.fileHandleForReading.availableData
                if p.terminationStatus == 0 {
                    state.resume {
                        continuation.resume()
                    }
                } else {
                    let msg = String(data: errData, encoding: .utf8) ?? ""
                    state.resume {
                        continuation.resume(throwing: NSError(domain: "SkillStore", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg]))
                    }
                }
            }
            do {
                try process.run()
            } catch {
                state.resume {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class ProcessRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        action()
    }
}

private enum SkillStoreProcessError: LocalizedError {
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let command):
            return "Unable to find `\(command)` for Skill installation. Install Node.js or ensure `\(command)` is available in a standard path such as /opt/homebrew/bin or /usr/local/bin."
        }
    }
}

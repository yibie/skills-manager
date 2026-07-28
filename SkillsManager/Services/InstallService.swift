import CryptoKit
import Foundation

enum SkillContentHasher {
    static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// 安装完成后 canonical SKILL.md 的内容指纹,写入 manifest 供更新前漂移检测。
private func canonicalContentHash(_ canonical: URL) -> String? {
    (try? String(contentsOf: canonical.appendingPathComponent("SKILL.md"), encoding: .utf8))
        .map(SkillContentHasher.hash)
}

struct SkillLifecycleService: Sendable {
    /// 供应链 pin:与 TUI 侧 DiscoverInstallService 保持一致,
    /// 未固定版本的 npx 在包被接管时等于本机任意代码执行。
    static let skillsCLIVersion = "1.5.20"

    typealias NativeInstaller = @Sendable (
        DiscoverSkill,
        [String],
        @escaping @Sendable (String) -> Void
    ) async throws -> Void
    typealias NativeRemover = @Sendable (Skill) throws -> Void
    typealias TrashItem = @Sendable (URL) throws -> Void
    typealias ProviderCommandRunner = @Sendable (
        [String],
        @escaping @Sendable (String) -> Void
    ) async throws -> Void

    private let home: URL
    private let canonicalSkillsDirectory: URL
    private let environment: [String: String]
    private let installNative: NativeInstaller
    private let removeNative: NativeRemover
    private let trashItem: TrashItem
    private let runProviderCommand: ProviderCommandRunner
    private let isSkillsCLIAvailable: @Sendable () -> Bool

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        canonicalSkillsDirectory: URL = AgentRegistry.canonicalGlobalSkillsDir,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        installNative: NativeInstaller? = nil,
        removeNative: NativeRemover? = nil,
        trashItem: @escaping TrashItem = SkillLifecycleService.moveToTrash,
        runProviderCommand: @escaping ProviderCommandRunner = SkillLifecycleService.runSkillsCLI,
        isSkillsCLIAvailable: @escaping @Sendable () -> Bool = {
            ExecutableLocator.resolve(command: "npx") != nil
        }
    ) {
        self.home = home.standardizedFileURL
        self.canonicalSkillsDirectory = canonicalSkillsDirectory.standardizedFileURL
        self.environment = environment
        self.installNative = installNative ?? { skill, agentIDs, appendLog in
            try await NativeSkillPackageInstaller.install(
                skill,
                agentIDs: agentIDs,
                canonicalSkillsDirectory: canonicalSkillsDirectory,
                appendLog: appendLog
            )
        }
        self.removeNative = removeNative ?? { skill in
            try SkillLifecycleService.removeNatively(
                skill,
                canonicalSkillsDirectory: canonicalSkillsDirectory,
                home: home,
                trashItem: trashItem
            )
        }
        self.trashItem = trashItem
        self.runProviderCommand = runProviderCommand
        self.isSkillsCLIAvailable = isSkillsCLIAvailable
    }

    func annotate(_ skills: [Skill]) -> [Skill] {
        let lock = SkillsCLILockfile.load(from: skillsCLILockfileURL)
        return skills.map { skill in
            var annotated = skill
            if let canonicalPath = skill.canonicalPath {
                annotated.provenance = Self.trustedProvenance(ManagedSkillManifest.load(from: canonicalPath))
                    ?? SkillProvenance(provider: .skillsManager, sourceURL: nil, skillID: skill.name)
            } else if isSkillsCLIInstallation(skill),
                      let entry = lock?.entry(for: skill.name) {
                annotated.provenance = entry.provenance(skillName: skill.name)
            } else {
                annotated.provenance = inferredProvenance(for: skill)
            }
            return annotated
        }
    }

    func installDiscover(
        _ skill: DiscoverSkill,
        agentIDs: [String],
        appendLog: @escaping @Sendable (String) -> Void
    ) async throws {
        try await installNative(skill, agentIDs, appendLog)
    }

    func install(
        _ skill: Skill,
        agentIDs: [String],
        appendLog: @escaping @Sendable (String) -> Void
    ) async throws {
        guard !agentIDs.isEmpty else { return }
        if skill.provenance.provider == .skillsCLI,
           isSkillsCLIAvailable(),
           let sourceURL = skill.provenance.sourceURL,
           let skillID = skill.provenance.skillID {
            try await runProviderCommand(
                ["-y", "skills@\(Self.skillsCLIVersion)", "add", sourceURL.absoluteString, "--skill", skillID, "--agent"]
                    + agentIDs
                    + ["--global", "--yes"],
                appendLog
            )
            return
        }

        let shouldTakeOver = skill.provenance.provider == .skillsCLI
            && isSkillsCLIInstallation(skill)
        let canonical = canonicalSkillsDirectory
            .appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
        let takeoverNeedsInstall = try shouldTakeOver
            ? prepareSkillsCLITakeover(skill, canonical: canonical)
            : true

        if takeoverNeedsInstall {
            if skill.isDedicatedDirectory {
                try SymlinkInstaller.install(
                    sourceDirectory: skill.directoryPath,
                    skillName: skill.name,
                    agentIDs: agentIDs,
                    canonicalSkillsDirectory: canonicalSkillsDirectory
                )
            } else {
                try SymlinkInstaller.install(
                    content: skill.markdownContent,
                    skillName: skill.name,
                    agentIDs: agentIDs,
                    canonicalSkillsDirectory: canonicalSkillsDirectory
                )
            }

            if let sourceURL = skill.provenance.sourceURL,
               let skillID = skill.provenance.skillID {
                try ManagedSkillManifest(
                    sourceURL: sourceURL,
                    skillID: skillID,
                    sourceRef: skill.provenance.sourceRef,
                    installedAt: Date(),
                    contentHash: canonicalContentHash(canonical)
                ).write(to: canonical)
            }
        }

        if shouldTakeOver {
            let removeCanonicalOnFailure = takeoverNeedsInstall
            do {
                try takeOverSkillsCLIInstallation(skill, canonical: canonical)
            } catch {
                if removeCanonicalOnFailure {
                    try? SymlinkInstaller.removeFromLibrary(
                        skillName: skill.name,
                        canonicalSkillsDirectory: canonicalSkillsDirectory
                    )
                }
                throw error
            }
            removeSkillsCLILockEntry(skill.name, appendLog: appendLog)
        }
    }

    func update(
        _ skill: Skill,
        agentIDs: [String],
        appendLog: @escaping @Sendable (String) -> Void
    ) async throws {
        if skill.provenance.provider == .skillsCLI, isSkillsCLIAvailable() {
            try await runProviderCommand(
                ["-y", "skills@\(Self.skillsCLIVersion)", "update", skill.name, "--global", "--yes"],
                appendLog
            )
            return
        }

        guard let sourceURL = skill.provenance.sourceURL,
              let skillID = skill.provenance.skillID
        else {
            throw SkillLifecycleError.missingSource(skill.name)
        }

        let shouldTakeOver = skill.provenance.provider == .skillsCLI
            && isSkillsCLIInstallation(skill)
        let canonical = canonicalSkillsDirectory
            .appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
        let takeoverNeedsInstall = try shouldTakeOver
            ? prepareSkillsCLITakeover(skill, canonical: canonical)
            : true

        if takeoverNeedsInstall {
            appendLog("The original provider is unavailable; taking over management in Skills Manager.")
            try await installNative(
                DiscoverSkill(
                    id: "\(sourceURL.absoluteString):\(skillID)",
                    source: sourceURL.pathComponents.dropFirst().prefix(2).joined(separator: "/"),
                    skillId: skillID,
                    name: skill.displayName,
                    installs: 0,
                    repoURL: sourceURL,
                    repositoryRef: skill.provenance.sourceRef,
                    installCommand: "",
                    baseDescription: skill.baseDescription,
                    baseDescriptionLocale: skill.baseDescriptionLocale,
                    localizedDescription: skill.localizedDescription,
                    readmeExcerpt: nil
                ),
                agentIDs,
                appendLog
            )
        }

        if shouldTakeOver {
            let removeCanonicalOnFailure = takeoverNeedsInstall
            do {
                try takeOverSkillsCLIInstallation(skill, canonical: canonical)
            } catch {
                if removeCanonicalOnFailure {
                    try? SymlinkInstaller.removeFromLibrary(
                        skillName: skill.name,
                        canonicalSkillsDirectory: canonicalSkillsDirectory
                    )
                }
                throw error
            }
            removeSkillsCLILockEntry(skill.name, appendLog: appendLog)
        }
    }

    /// manifest 位于技能目录内、可被第三方内容自带,只信任 github.com 来源的 sourceURL;
    /// 其余降级 .manual(无更新通道),阻断伪造 manifest 把 Update 变成任意仓库覆盖。
    private static func trustedProvenance(_ manifest: ManagedSkillManifest?) -> SkillProvenance? {
        guard let manifest else { return nil }
        guard manifest.sourceURL.host?.lowercased() == "github.com" else { return .manual }
        return manifest.provenance
    }

    /// 更新会用远端内容覆盖 canonical 副本;若本地内容与安装时的记录不一致,调用方须先取得用户确认。
    /// manifest 缺 hash(旧安装)或内容读不到时视为无漂移——没有证据不阻断。
    func hasLocalDrift(_ skill: Skill) -> Bool {
        let canonical = skill.canonicalPath
            ?? canonicalSkillsDirectory.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
        guard let manifest = ManagedSkillManifest.load(from: canonical),
              let recorded = manifest.contentHash,
              let current = try? String(contentsOf: canonical.appendingPathComponent("SKILL.md"), encoding: .utf8)
        else { return false }
        return SkillContentHasher.hash(current) != recorded
    }

    func removeFromLibrary(
        _ skill: Skill,
        appendLog: @escaping @Sendable (String) -> Void
    ) async throws {
        if skill.provenance.provider == .skillsCLI, isSkillsCLIAvailable() {
            try await runProviderCommand(
                ["-y", "skills@\(Self.skillsCLIVersion)", "remove", skill.name, "--global", "--yes"],
                appendLog
            )
        } else {
            if skill.provenance.provider == .skillsCLI {
                appendLog("The original provider is unavailable; removing the installation natively.")
            }
            try removeNative(skill)
            if skill.provenance.provider == .skillsCLI {
                removeSkillsCLILockEntry(skill.name, appendLog: appendLog)
            }
        }
    }

    private var skillsCLILockfileURL: URL {
        if let xdgStateHome = environment["XDG_STATE_HOME"], xdgStateHome.hasPrefix("/") {
            return URL(fileURLWithPath: xdgStateHome)
                .appendingPathComponent("skills/.skill-lock.json")
        }
        return home.appendingPathComponent(".agents/.skill-lock.json")
    }

    private func inferredProvenance(for skill: Skill) -> SkillProvenance {
        switch skill.source {
        case .plugin:
            SkillProvenance(provider: .plugin, sourceURL: nil, skillID: skill.name)
        case .openClaw:
            SkillProvenance(provider: .openClaw, sourceURL: nil, skillID: skill.name)
        case .local, .symlinked, .projectLocal:
            .manual
        }
    }

    private func isSkillsCLIInstallation(_ skill: Skill) -> Bool {
        let expected = home.appendingPathComponent(".agents/skills")
            .appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
        return skill.directoryPath.resolvingSymlinksInPath().standardizedFileURL
            == expected.resolvingSymlinksInPath().standardizedFileURL
    }

    private func prepareSkillsCLITakeover(_ skill: Skill, canonical: URL) throws -> Bool {
        let fm = FileManager.default
        let backup = skillsCLIProviderBackup(for: skill)
        guard itemExistsIncludingSymlink(canonical, fm: fm) else {
            if itemExistsIncludingSymlink(backup, fm: fm) {
                throw SymlinkInstallerError.destinationConflict(backup)
            }
            return true
        }
        guard isRecoverableCanonical(canonical, for: skill) else {
            throw SymlinkInstallerError.destinationConflict(canonical)
        }
        return false
    }

    private func isRecoverableCanonical(_ canonical: URL, for skill: Skill) -> Bool {
        guard SymlinkInstaller.isManagedCanonicalDirectory(canonical),
              let manifest = ManagedSkillManifest.load(from: canonical)
        else { return false }

        let expected = skill.provenance
        guard SymlinkInstaller.sanitize(manifest.skillID)
            == SymlinkInstaller.sanitize(expected.skillID ?? skill.name)
        else { return false }

        let actual = manifest.provenance
        guard let expectedSource = expected.trustedGitHubRepoIdentity,
              let actualSource = actual.trustedGitHubRepoIdentity
        else { return false }
        return expectedSource == actualSource
            && expected.sourceRef == manifest.sourceRef
    }

    private func takeOverSkillsCLIInstallation(_ skill: Skill, canonical: URL) throws {
        let fm = FileManager.default
        let target = skillsCLIProviderDirectory(for: skill)
        let backup = skillsCLIProviderBackup(for: skill)
        guard itemExistsIncludingSymlink(canonical, fm: fm),
              isRecoverableCanonical(canonical, for: skill)
        else {
            throw SymlinkInstallerError.destinationConflict(canonical)
        }

        if itemExistsIncludingSymlink(target, fm: fm) {
            guard !isSymbolicLink(target, fm: fm) else {
                guard isLink(target, pointingTo: canonical, fm: fm) else {
                    throw SymlinkInstallerError.destinationConflict(target)
                }
                try? trashItem(backup)
                return
            }
            guard !itemExistsIncludingSymlink(backup, fm: fm) else {
                throw SymlinkInstallerError.destinationConflict(backup)
            }
            try fm.moveItem(at: target, to: backup)
        }

        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(
                atPath: target.path,
                withDestinationPath: canonical.resolvingSymlinksInPath().path
            )
        } catch {
            try? fm.removeItem(at: target)
            if !itemExistsIncludingSymlink(target, fm: fm) {
                try? fm.moveItem(at: backup, to: target)
            }
            throw error
        }
        try? trashItem(backup)
    }

    private func skillsCLIProviderDirectory(for skill: Skill) -> URL {
        home.appendingPathComponent(".agents/skills")
            .appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
            .standardizedFileURL
    }

    private func skillsCLIProviderBackup(for skill: Skill) -> URL {
        let target = skillsCLIProviderDirectory(for: skill)
        return target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent)-skills-cli-backup")
            .standardizedFileURL
    }

    private func isSymbolicLink(_ url: URL, fm: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func itemExistsIncludingSymlink(_ url: URL, fm: FileManager) -> Bool {
        fm.fileExists(atPath: url.path)
            || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func isLink(_ link: URL, pointingTo target: URL, fm: FileManager) -> Bool {
        guard let rawDestination = try? fm.destinationOfSymbolicLink(atPath: link.path) else { return false }
        let destination = rawDestination.hasPrefix("/")
            ? URL(fileURLWithPath: rawDestination)
            : link.deletingLastPathComponent().appendingPathComponent(rawDestination)
        return destination.resolvingSymlinksInPath().standardizedFileURL
            == target.resolvingSymlinksInPath().standardizedFileURL
    }

    private func removeSkillsCLILockEntry(
        _ skillName: String,
        appendLog: @escaping @Sendable (String) -> Void
    ) {
        do {
            try SkillsCLILockfile.removeEntry(named: skillName, from: skillsCLILockfileURL)
        } catch {
            appendLog("Installed skill was handled, but Skills CLI metadata could not be updated: \(error.localizedDescription)")
        }
    }

    private static func runSkillsCLI(
        args: [String],
        appendLog: @escaping @Sendable (String) -> Void
    ) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        guard let executable = ExecutableLocator.resolve(command: "npx", homePath: home.path) else {
            throw SkillLifecycleError.missingExecutable("npx")
        }
        var environment = ExecutableLocator.buildEnvironment(
            homePath: home.path,
            resolvedExecutable: executable
        )
        environment["DISABLE_TELEMETRY"] = "1"
        try await SkillProviderProcess.run(
            executable,
            args: args,
            currentDirectory: home,
            environment: environment,
            appendLog: appendLog
        )
    }

    private static func removeNatively(
        _ skill: Skill,
        canonicalSkillsDirectory: URL,
        home: URL,
        trashItem: TrashItem
    ) throws {
        if skill.canonicalPath != nil {
            try SymlinkInstaller.removeFromLibrary(
                skillName: skill.name,
                canonicalSkillsDirectory: canonicalSkillsDirectory
            )
            return
        }
        switch skill.provenance.provider {
        case .skillsManager:
            try SymlinkInstaller.removeFromLibrary(
                skillName: skill.name,
                canonicalSkillsDirectory: canonicalSkillsDirectory
            )
        case .skillsCLI:
            try moveSkillsCLIInstallationToTrash(skill, trashItem: trashItem)
        case .plugin:
            let cache = home
                .appendingPathComponent(".claude/plugins/cache")
                .standardizedFileURL.path
            let target = skill.trashTargetURL.standardizedFileURL
            guard target.path.hasPrefix(cache + "/") else {
                throw SkillLifecycleError.externalSkillRequiresExplicitRemoval(target)
            }
            try trashItem(target)
        case .openClaw:
            let target = skill.trashTargetURL.standardizedFileURL
            guard case .openClaw(let root) = skill.source else {
                throw SkillLifecycleError.externalSkillRequiresExplicitRemoval(target)
            }
            let allowedRoot = openClawRoot(root, home: home)
            guard let allowedRoot,
                  target.path.hasPrefix(allowedRoot.standardizedFileURL.path + "/")
            else {
                throw SkillLifecycleError.externalSkillRequiresExplicitRemoval(target)
            }
            try trashItem(target)
        case .manual:
            throw SkillLifecycleError.externalSkillRequiresExplicitRemoval(skill.trashTargetURL)
        }
    }

    private static func openClawRoot(_ id: String, home: URL) -> URL? {
        switch id {
        case "clawd": home.appendingPathComponent("clawd/skills")
        case "npm-global": home.appendingPathComponent(".npm-global/lib/node_modules/openclaw/skills")
        case "workspace-main": home.appendingPathComponent(".openclaw/workspace-main/skills")
        default: nil
        }
    }

    private static func moveSkillsCLIInstallationToTrash(
        _ skill: Skill,
        trashItem: TrashItem
    ) throws {
        let fm = FileManager.default
        let target = skill.trashTargetURL.standardizedFileURL
        guard (try? fm.attributesOfItem(atPath: target.path)) != nil else { return }

        for agent in AgentRegistry.all {
            let link = AgentRegistry.resolvedSkillsDir(for: agent)
                .appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
            guard link.standardizedFileURL != target,
                  let destination = try? fm.destinationOfSymbolicLink(atPath: link.path)
            else { continue }
            let resolved = destination.hasPrefix("/")
                ? URL(fileURLWithPath: destination)
                : link.deletingLastPathComponent().appendingPathComponent(destination)
            if resolved.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL {
                try fm.removeItem(at: link)
            }
        }

        try trashItem(target)
    }

    private static func moveToTrash(_ url: URL) throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
}

private struct SkillsCLILockfile: Decodable {
    struct Entry: Decodable {
        var sourceURL: String
        var skillPath: String?
        var ref: String?

        enum CodingKeys: String, CodingKey {
            case sourceURL = "sourceUrl"
            case skillPath
            case ref
        }

        func provenance(skillName: String) -> SkillProvenance {
            let url = sourceURL.hasPrefix("/")
                ? URL(fileURLWithPath: sourceURL)
                : URL(string: sourceURL)
            return SkillProvenance(
                provider: .skillsCLI,
                sourceURL: url,
                skillID: skillPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? skillName,
                sourceRef: ref
            )
        }
    }

    var version: Int
    var skills: [String: Entry]

    static func load(from url: URL) -> SkillsCLILockfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func entry(for skillName: String) -> Entry? {
        let safeName = SymlinkInstaller.sanitize(skillName)
        return skills.first { SymlinkInstaller.sanitize($0.key) == safeName }?.value
    }

    static func removeEntry(named skillName: String, from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var skills = root["skills"] as? [String: Any]
        else {
            throw SkillLifecycleError.invalidProviderMetadata
        }
        let safeName = SymlinkInstaller.sanitize(skillName)
        guard let key = skills.keys.first(where: {
            SymlinkInstaller.sanitize($0) == safeName
        }) else { return }
        skills.removeValue(forKey: key)
        root["skills"] = skills
        let updated = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updated.write(to: url, options: .atomic)
    }
}

private struct ManagedSkillManifest: Codable {
    static let fileName = SymlinkInstaller.managedManifestName

    var sourceURL: URL
    var skillID: String
    var sourceRef: String?
    var installedAt: Date
    var contentHash: String? = nil

    var provenance: SkillProvenance {
        SkillProvenance(
            provider: .skillsManager,
            sourceURL: sourceURL,
            skillID: skillID,
            sourceRef: sourceRef
        )
    }

    static func load(from directory: URL) -> ManagedSkillManifest? {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write(to directory: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

enum NativeSkillPackageInstaller {
    static func install(
        _ skill: DiscoverSkill,
        agentIDs: [String],
        canonicalSkillsDirectory: URL,
        appendLog: @escaping @Sendable (String) -> Void
    ) async throws {
        let archiveURL = try archiveURL(for: skill.repoURL, ref: skill.repositoryRef)
        var request = URLRequest(url: archiveURL)
        request.setValue("skills-manager-macos", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        appendLog("Downloading \(skill.repoURL.absoluteString)")

        let session = NetworkSessionFactory.makeEphemeralSession()
        let (downloadURL, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw SkillLifecycleError.downloadFailed(skill.repoURL)
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-manager-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workDirectory) }
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let archive = workDirectory.appendingPathComponent("source.zip")
        let extracted = workDirectory.appendingPathComponent("extracted")
        try FileManager.default.copyItem(at: downloadURL, to: archive)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)

        appendLog("Extracting skill package")
        try await Task.detached {
            try extract(archive: archive, to: extracted)
        }.value
        let skillDirectory = try findSkillDirectory(in: extracted, skillID: skill.skillId)

        appendLog("Installing into the Skills Manager library")
        try SymlinkInstaller.install(
            sourceDirectory: skillDirectory,
            skillName: skill.skillId,
            agentIDs: agentIDs,
            canonicalSkillsDirectory: canonicalSkillsDirectory
        )
        let canonical = canonicalSkillsDirectory
            .appendingPathComponent(SymlinkInstaller.sanitize(skill.skillId))
        try ManagedSkillManifest(
            sourceURL: skill.repoURL,
            skillID: skill.skillId,
            sourceRef: skill.repositoryRef,
            installedAt: Date(),
            contentHash: canonicalContentHash(canonical)
        ).write(to: canonical)
    }

    static func archiveURL(for repositoryURL: URL, ref: String? = nil) throws -> URL {
        let components = repositoryURL.pathComponents.filter { $0 != "/" }
        guard repositoryURL.host?.lowercased() == "github.com", components.count >= 2 else {
            throw SkillLifecycleError.unsupportedSource(repositoryURL)
        }
        let repository = components[1].hasSuffix(".git")
            ? String(components[1].dropLast(4))
            : components[1]
        let refCharacters = CharacterSet.urlPathAllowed
            .subtracting(CharacterSet(charactersIn: "/"))
        let encodedRef = ref?.addingPercentEncoding(withAllowedCharacters: refCharacters)
        guard let url = URL(
            string: "https://api.github.com/repos/\(components[0])/\(repository)/zipball"
                + (encodedRef.map { "/\($0)" } ?? "")
        ) else {
            throw SkillLifecycleError.unsupportedSource(repositoryURL)
        }
        return url
    }

    private static func extract(archive: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SkillLifecycleError.archiveExtractionFailed
        }
    }

    private static func findSkillDirectory(in root: URL, skillID: String) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw SkillLifecycleError.skillNotFound(skillID)
        }

        let safeID = SymlinkInstaller.sanitize(skillID)
        var fallback: URL?
        for case let file as URL in enumerator where file.lastPathComponent == "SKILL.md" {
            let directory = file.deletingLastPathComponent()
            let resolved = directory.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path + "/") else {
                continue
            }
            if SymlinkInstaller.sanitize(directory.lastPathComponent) == safeID {
                return directory
            }
            if let content = try? String(contentsOf: file, encoding: .utf8),
               let name = SkillParser.parse(content: content).frontmatter["name"],
               SymlinkInstaller.sanitize(name) == safeID {
                fallback = directory
            }
        }
        guard let fallback else { throw SkillLifecycleError.skillNotFound(skillID) }
        return fallback
    }
}

private enum SkillProviderProcess {
    static func run(
        _ executable: String,
        args: [String],
        currentDirectory: URL,
        environment: [String: String],
        appendLog: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            let state = ProviderProcessRunState()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.currentDirectoryURL = currentDirectory
            process.environment = environment
            process.standardOutput = output
            process.standardError = errors
            output.fileHandleForReading.readabilityHandler = {
                appendLog(String(data: $0.availableData, encoding: .utf8) ?? "")
            }
            errors.fileHandleForReading.readabilityHandler = {
                appendLog(String(data: $0.availableData, encoding: .utf8) ?? "")
            }
            process.terminationHandler = { process in
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                state.resume {
                    process.terminationStatus == 0
                        ? continuation.resume()
                        : continuation.resume(
                            throwing: SkillLifecycleError.providerCommandFailed(process.terminationStatus)
                        )
                }
            }
            do {
                try process.run()
            } catch {
                state.resume { continuation.resume(throwing: error) }
            }
        }
    }
}

private final class ProviderProcessRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        action()
    }
}

enum SkillLifecycleError: LocalizedError {
    case missingExecutable(String)
    case missingSource(String)
    case unsupportedSource(URL)
    case downloadFailed(URL)
    case archiveExtractionFailed
    case skillNotFound(String)
    case providerCommandFailed(Int32)
    case externalSkillRequiresExplicitRemoval(URL)
    case invalidProviderMetadata

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let command):
            "Unable to find the external provider executable `\(command)`."
        case .missingSource(let skill):
            "No update source is known for \(skill)."
        case .unsupportedSource(let url):
            "Skills Manager cannot yet acquire skill packages from \(url.host ?? url.absoluteString)."
        case .downloadFailed(let url):
            "Failed to download the skill source from \(url.absoluteString)."
        case .archiveExtractionFailed:
            "The downloaded skill package could not be extracted."
        case .skillNotFound(let skill):
            "The downloaded repository does not contain a skill named \(skill)."
        case .providerCommandFailed(let status):
            "The external skill provider exited with status \(status)."
        case .externalSkillRequiresExplicitRemoval(let url):
            "The external skill at \(url.path) must be explicitly moved to Trash."
        case .invalidProviderMetadata:
            "The external provider metadata is not valid JSON."
        }
    }
}

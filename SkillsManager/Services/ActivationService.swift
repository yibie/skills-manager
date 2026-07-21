import Foundation

enum MountStatus: String, Sendable {
    case unmounted   // 意图未挂载且磁盘无 link
    case mounted     // 意图挂载且磁盘全部就位
    case diverged    // 其余:意图与磁盘不一致(或部分挂载)
}

struct MountReport: Equatable, Sendable {
    struct Skipped: Equatable, Sendable {
        let skillID: String
        let reason: String
    }
    var changed: [String] = []
    var skipped: [Skipped] = []

    var summaryText: String {
        var parts: [String] = []
        if !changed.isEmpty { parts.append("成功 \(changed.count) 个") }
        if !skipped.isEmpty {
            let reasons = skipped.map { "\($0.skillID)(\($0.reason))" }.joined(separator: "、")
            parts.append("跳过 \(skipped.count) 个:\(reasons)")
        }
        return parts.isEmpty ? "无变化" : parts.joined(separator: ",")
    }
}

/// 分组挂载服务:把技能 symlink 进 agent 目录(挂载)或移除 link(卸载)。
/// canonical(~/.config/agents/skills/)是库的本体,永远不删。
/// 实体技能(.local)挂载前先迁移进 canonical,原处留 link,原 agent 不受影响。
enum ActivationService {

    /// 状态灯纯函数:意图 + 磁盘事实 → 卡片/开关状态。
    static func status(intentMounted: Bool, linkedCount: Int, memberCount: Int) -> MountStatus {
        guard memberCount > 0 else { return intentMounted ? .diverged : .unmounted }
        if intentMounted && linkedCount == memberCount { return .mounted }
        if !intentMounted && linkedCount == 0 { return .unmounted }
        return .diverged
    }

    /// 数成员技能里有多少个在 agentSkillsDir 已有指向 canonical 的 link。
    static func probeLinkedCount(
        memberSkills: [Skill],
        agentSkillsDir: URL,
        canonicalDir: URL = AgentRegistry.canonicalGlobalSkillsDir,
        fm: FileManager = .default
    ) -> Int {
        memberSkills.reduce(0) { count, skill in
            let link = agentSkillsDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
            guard isLink(link, pointingTo: canonicalPath(for: skill, canonicalDir: canonicalDir), fm: fm)
            else { return count }
            return count + 1
        }
    }

    /// 挂载:确保每个技能有 canonical 副本,再在 agentSkillsDir 建 link。
    /// 冲突(目标已有同名实体)跳过该技能并记录,不阻塞整组。
    static func mount(
        skills: [Skill],
        agentSkillsDir: URL,
        canonicalDir: URL = AgentRegistry.canonicalGlobalSkillsDir,
        fm: FileManager = .default
    ) throws -> MountReport {
        var report = MountReport()
        try fm.createDirectory(at: agentSkillsDir, withIntermediateDirectories: true)
        for skill in skills {
            do {
                let canonical = try ensureCanonical(skill: skill, canonicalDir: canonicalDir, fm: fm)
                let link = agentSkillsDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
                try createLink(from: canonical, at: link, fm: fm)
                report.changed.append(skill.id)
            } catch ActivationError.conflict(let url) {
                report.skipped.append(.init(skillID: skill.id, reason: "目标已存在 \(url.lastPathComponent)"))
            }
        }
        return report
    }

    /// 卸载:删 agentSkillsDir 里指向 canonical 的 link;实体目录不动;canonical 保留。
    static func unmount(
        skills: [Skill],
        agentSkillsDir: URL,
        canonicalDir: URL = AgentRegistry.canonicalGlobalSkillsDir,
        fm: FileManager = .default
    ) -> MountReport {
        var report = MountReport()
        for skill in skills {
            let link = agentSkillsDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
            let canonical = canonicalPath(for: skill, canonicalDir: canonicalDir)
            if isLink(link, pointingTo: canonical, fm: fm) {
                try? fm.removeItem(at: link)
                report.changed.append(skill.id)
            } else if (try? fm.attributesOfItem(atPath: link.path)) != nil {
                report.skipped.append(.init(skillID: skill.id, reason: "实体目录不删除"))
            }
        }
        return report
    }

    // MARK: - 内部

    enum ActivationError: LocalizedError {
        case conflict(URL)
        var errorDescription: String? {
            switch self {
            case .conflict(let url): "A file or directory already exists at \(url.path)."
            }
        }
    }

    static func canonicalPath(for skill: Skill, canonicalDir: URL) -> URL {
        skill.canonicalPath ?? canonicalDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
    }

    /// 确保技能在 canonical 有实体副本:.local 实体迁移(原处留 link);
    /// 其他来源(plugin 等只读缓存)写内容副本。已有 canonical 直接返回。
    private static func ensureCanonical(skill: Skill, canonicalDir: URL, fm: FileManager) throws -> URL {
        let dest = canonicalDir.appendingPathComponent(SymlinkInstaller.sanitize(skill.name))
        if let existing = skill.canonicalPath,
           (try? fm.attributesOfItem(atPath: existing.path)) != nil {
            return existing
        }
        if (try? fm.attributesOfItem(atPath: dest.path)) != nil {
            guard SymlinkInstaller.isManagedCanonicalDirectory(dest, fm: fm) else {
                throw ActivationError.conflict(dest)
            }
            return dest
        }

        try fm.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        if case .local = skill.source,
           (try? fm.attributesOfItem(atPath: skill.directoryPath.path)) != nil {
            // 迁移实体:原位置变 link,原 agent 无感知
            try fm.moveItem(at: skill.directoryPath, to: dest)
        } else {
            // 只读来源:写内容副本
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try skill.markdownContent.write(
                to: dest.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
        }
        try "1\n".write(
            to: dest.appendingPathComponent(SymlinkInstaller.managedMarkerName),
            atomically: true,
            encoding: .utf8
        )
        if case .local = skill.source {
            try fm.createSymbolicLink(atPath: skill.directoryPath.path, withDestinationPath: dest.path)
        }
        return dest
    }

    private static func createLink(from canonical: URL, at link: URL, fm: FileManager) throws {
        if (try? fm.attributesOfItem(atPath: link.path)) != nil {
            guard isLink(link, pointingTo: canonical, fm: fm) else {
                throw ActivationError.conflict(link)
            }
            return // 已挂好,幂等
        }
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: canonical.path)
    }

    private static func isLink(_ link: URL, pointingTo target: URL, fm: FileManager) -> Bool {
        guard let raw = try? fm.destinationOfSymbolicLink(atPath: link.path) else { return false }
        let destination: URL = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : link.deletingLastPathComponent().appendingPathComponent(raw)
        return destination.resolvingSymlinksInPath().standardizedFileURL.path
            == target.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

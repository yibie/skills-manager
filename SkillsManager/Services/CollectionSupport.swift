import Foundation

/// 组成员 id 维护。挂载时实体技能会迁移进 canonical,id 可能从 path-keyed
/// (`universal:/path/to/review`)变成 name-keyed(`universal:review`);
/// 重扫后按(清洗后的)名字把失效的旧 id 重写到新 id。
/// 无匹配或多匹配时保持原 id,诚实显示"缺失"。
enum CollectionSupport {
    static func reconcileMemberIDs(_ ids: [String], skills: [Skill]) -> [String] {
        ids.map { id in
            guard !skills.contains(where: { $0.id == id }) else { return id }
            let name = entryName(from: id)
            let matches = skills.filter {
                SymlinkInstaller.sanitize($0.name) == SymlinkInstaller.sanitize(name)
            }
            return matches.count == 1 ? matches[0].id : id
        }
    }

    /// 旧 id 取名字:`local:commit` 取冒号后;`universal:/path/to/review` 取最后路径分量。
    private static func entryName(from id: String) -> String {
        let afterColon = id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id
        return afterColon.split(separator: "/").last.map(String.init) ?? afterColon
    }
}

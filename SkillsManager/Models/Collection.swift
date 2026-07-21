import Foundation
import SwiftData

// 分组:用户自定义的技能集合 + 装载意图(希望挂载到哪些 agent)。
// 磁盘是挂载状态的真相;mountedAgentIDs 只记意图,供 reconcile 对比。
@Model
final class CollectionRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var memberSkillIDs: [String]      // skill.id("{source}:{name}")
    var mountedAgentIDs: [String]     // AgentRegistry id(装载意图)
    /// 预留:Phase 2 工作区绑定。
    var projectPaths: [String]

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        memberSkillIDs: [String] = [],
        mountedAgentIDs: [String] = [],
        projectPaths: [String] = []
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.memberSkillIDs = memberSkillIDs
        self.mountedAgentIDs = mountedAgentIDs
        self.projectPaths = projectPaths
    }
}

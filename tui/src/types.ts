export interface Skill {
  name: string
  displayName: string
  description: string
  filePath: string
  /** Directory containing the skill when it is folder-based (…/skill-name/SKILL.md). */
  directoryPath?: string
  /** 'local' = standalone local resource; 'plugin' = bundled inside a plugin/package cache */
  source: 'local' | 'plugin'
  /** 'skill' = SKILL.md-based resource; 'extension' = Pi extension entrypoint */
  resourceType: 'skill' | 'extension'
  /** Set when source === 'plugin'; identifies the cache/package source, not Discover */
  pluginSource?: string
  pluginName?: string
  /** Set when resourceType === 'extension'; where Pi discovered the extension. */
  extensionScope?: 'global' | 'project' | 'settings' | 'package'
  compatibleAgents: string[]
  isStarred: boolean
  isInstalled: boolean
  version?: string
}

export interface Commit {
  hash: string
  date: string
  message: string
  isHead: boolean
}

export type Panel = 'sidebar' | 'list' | 'detail'
export type Overlay = 'none' | 'search' | 'history' | 'agent-select' | 'skill-detail'

export type FilterState = 'discover' | 'all' | 'installed' | 'starred'
/** Agent filter is now dynamic - can be 'all' or any agent ID */
export type AgentFilter = string

export interface AgentDefinition {
  id: string
  label: string
  detectPath: string
  skillsDir: string
}

export interface DiscoverSkill {
  id: string
  source: string
  skillId: string
  name: string
  installs: number
  repoUrl: string
  installCommand: string
  summary?: string
  readmeExcerpt?: string
}

export type SidebarSelection = `library:${FilterState}` | `agent:${string}` | `source:${string}`

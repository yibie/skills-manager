export interface Skill {
  name: string
  displayName: string
  description: string
  filePath: string
  /** 'local' = standalone skill in ~/.claude/skills/; 'plugin' = bundled inside a plugin */
  source: 'local' | 'plugin'
  /** Set when source === 'plugin' */
  marketplace?: string
  pluginName?: string
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
export type Overlay = 'none' | 'search' | 'history'

export type FilterState = 'all' | 'installed' | 'starred'
/** Agent filter is now dynamic - can be 'all' or any agent ID */
export type AgentFilter = string

export interface AgentDefinition {
  id: string
  label: string
  detectPath: string
  skillsDir: string
}

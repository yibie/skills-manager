export interface Skill {
  name: string
  displayName: string
  description: string
  filePath: string
  source: 'local' | 'marketplace'
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
export type AgentFilter = 'all' | 'claude-code' | 'copilot-cli' | 'codex'

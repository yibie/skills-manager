import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import matter from 'gray-matter'
import type { Skill, AgentDefinition } from '../types.js'

const LOCAL_SKILLS_DIR = path.join(os.homedir(), '.claude', 'skills')
const PLUGIN_CACHE_DIR = path.join(os.homedir(), '.claude', 'plugins', 'cache')
const STATE_FILE = path.join(os.homedir(), '.skills-manager', 'tui-state.json')

const AGENT_DEFINITIONS: AgentDefinition[] = [
  { id: 'claude-code', label: 'Claude Code', detectPath: path.join(os.homedir(), '.claude'), skillsDir: path.join(os.homedir(), '.claude', 'skills') },
  { id: 'codex', label: 'Codex', detectPath: path.join(os.homedir(), '.codex'), skillsDir: path.join(os.homedir(), '.codex', 'skills') },
  { id: 'gemini-cli', label: 'Gemini CLI', detectPath: path.join(os.homedir(), '.gemini'), skillsDir: path.join(os.homedir(), '.gemini', 'skills') },
  { id: 'copilot', label: 'Copilot', detectPath: path.join(os.homedir(), '.copilot'), skillsDir: path.join(os.homedir(), '.copilot', 'skills') },
  { id: 'roo', label: 'Roo', detectPath: path.join(os.homedir(), '.roo'), skillsDir: path.join(os.homedir(), '.roo', 'skills') },
  { id: 'continue', label: 'Continue', detectPath: path.join(os.homedir(), '.continue'), skillsDir: path.join(os.homedir(), '.continue', 'skills') },
  { id: 'augment', label: 'Augment', detectPath: path.join(os.homedir(), '.augment'), skillsDir: path.join(os.homedir(), '.augment', 'skills') },
  { id: 'commandcode', label: 'CommandCode', detectPath: path.join(os.homedir(), '.commandcode'), skillsDir: path.join(os.homedir(), '.commandcode', 'skills') },
  { id: 'hermes', label: 'Hermes', detectPath: path.join(os.homedir(), '.hermes'), skillsDir: path.join(os.homedir(), '.hermes', 'skills') },
  { id: 'iflow', label: 'iFlow', detectPath: path.join(os.homedir(), '.iflow'), skillsDir: path.join(os.homedir(), '.iflow', 'skills') },
  { id: 'kilocode', label: 'KiloCode', detectPath: path.join(os.homedir(), '.kilocode'), skillsDir: path.join(os.homedir(), '.kilocode', 'skills') },
  { id: 'kiro', label: 'Kiro', detectPath: path.join(os.homedir(), '.kiro'), skillsDir: path.join(os.homedir(), '.kiro', 'skills') },
  { id: 'mcpjam', label: 'MCPJam', detectPath: path.join(os.homedir(), '.mcpjam'), skillsDir: path.join(os.homedir(), '.mcpjam', 'skills') },
  { id: 'mux', label: 'Mux', detectPath: path.join(os.homedir(), '.mux'), skillsDir: path.join(os.homedir(), '.mux', 'skills') },
  { id: 'neovate', label: 'Neovate', detectPath: path.join(os.homedir(), '.neovate'), skillsDir: path.join(os.homedir(), '.neovate', 'skills') },
  { id: 'openhands', label: 'OpenHands', detectPath: path.join(os.homedir(), '.openhands'), skillsDir: path.join(os.homedir(), '.openhands', 'skills') },
  { id: 'openwukong', label: 'OpenWukong', detectPath: path.join(os.homedir(), '.openwukong'), skillsDir: path.join(os.homedir(), '.openwukong', 'skills') },
  { id: 'qwen', label: 'Qwen', detectPath: path.join(os.homedir(), '.qwen'), skillsDir: path.join(os.homedir(), '.qwen', 'skills') },
  { id: 'stepfun', label: 'StepFun', detectPath: path.join(os.homedir(), '.stepfun'), skillsDir: path.join(os.homedir(), '.stepfun', 'skills') },
]

interface TuiState {
  starred: string[]
}

function readState(): TuiState {
  try {
    const parsed = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')) as unknown
    if (
      typeof parsed === 'object' && parsed !== null &&
      'starred' in parsed &&
      Array.isArray((parsed as Record<string, unknown>)['starred'])
    ) {
      return parsed as TuiState
    }
    return { starred: [] }
  } catch {
    return { starred: [] }
  }
}

function writeState(state: TuiState): void {
  try {
    const dir = path.dirname(STATE_FILE)
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2))
  } catch {
    // Silent: star state is best-effort, never crash the TUI
  }
}

export function getInstalledAgents(): AgentDefinition[] {
  return AGENT_DEFINITIONS.filter(agent => {
    try {
      return fs.existsSync(agent.detectPath)
    } catch {
      return false
    }
  })
}

/** Resolve a symlink to its real path; return original path if not a symlink. */
function resolveSymlink(p: string): string {
  try {
    const dest = fs.readlinkSync(p)
    return dest.startsWith('/') ? dest : path.resolve(path.dirname(p), dest)
  } catch {
    return p
  }
}

/** Recursively resolve symlinks until we reach a real file/directory. */
function resolveSymlinkFully(p: string): string {
  try {
    return fs.realpathSync(p)
  } catch {
    return p
  }
}

/** Return the lexicographically highest subdirectory (latest version) inside a plugin dir. */
function latestVersion(pluginDir: string): string | null {
  try {
    const entries = fs.readdirSync(pluginDir, { withFileTypes: true })
      .filter(e => e.isDirectory())
      .map(e => e.name)
      .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))
    return entries.length > 0 ? path.join(pluginDir, entries[entries.length - 1]) : null
  } catch {
    return null
  }
}

function parseSkillFile(
  filePath: string,
  starredNames: string[],
  overrides: Partial<Skill> = {}
): Skill | null {
  try {
    const raw = fs.readFileSync(filePath, 'utf8')
    const { data, content } = matter(raw)
    const name = overrides.name ?? path.basename(path.dirname(filePath))
    return {
      name,
      displayName: (data['name'] as string | undefined) ?? name,
      description: (data['description'] as string | undefined) ?? content.trimStart().slice(0, 100).trim(),
      filePath,
      source: 'local',
      compatibleAgents: (data['agents'] as string[] | undefined) ?? ['claude-code'],
      isStarred: starredNames.includes(name),
      isInstalled: false,
      version: data['version'] as string | undefined,
      ...overrides,
    }
  } catch {
    return null
  }
}

/**
 * Scan ~/.claude/skills/
 * Each entry is either:
 *   - a directory (possibly a symlink to a dir) containing SKILL.md  → local skill
 *   - a bare .md file directly in the dir                            → local skill
 */
function scanLocalSkills(starredNames: string[], agentId: string): Skill[] {
  if (!fs.existsSync(LOCAL_SKILLS_DIR)) return []
  const skills: Skill[] = []

  for (const entry of fs.readdirSync(LOCAL_SKILLS_DIR, { withFileTypes: true })) {
    const entryPath = path.join(LOCAL_SKILLS_DIR, entry.name)
    const resolved = resolveSymlink(entryPath)

    let isDir = false
    try {
      isDir = fs.statSync(resolved).isDirectory()
    } catch {
      continue
    }

    if (isDir) {
      // Skill directory: look for SKILL.md inside
      const skillFile = path.join(resolved, 'SKILL.md')
      if (!fs.existsSync(skillFile)) continue
      const skill = parseSkillFile(skillFile, starredNames, {
        name: entry.name,
        source: 'local',
        isInstalled: true,
        compatibleAgents: [agentId],
      })
      if (skill) skills.push(skill)
    } else if (entry.name.endsWith('.md')) {
      // Bare .md file in skills dir
      const name = entry.name.replace(/\.md$/, '')
      const skill = parseSkillFile(resolved, starredNames, {
        name,
        source: 'local',
        isInstalled: true,
        compatibleAgents: [agentId],
      })
      if (skill) skills.push(skill)
    }
  }

  return skills
}

/**
 * Scan a specific agent's skills directory.
 * Skills may be symlinks to shared ~/.agents/skills/ directory.
 */
function scanAgentSkills(agent: AgentDefinition, starredNames: string[]): Skill[] {
  if (!fs.existsSync(agent.skillsDir)) return []
  const skills: Skill[] = []

  for (const entry of fs.readdirSync(agent.skillsDir, { withFileTypes: true })) {
    const entryPath = path.join(agent.skillsDir, entry.name)
    const resolved = resolveSymlink(entryPath)

    let isDir = false
    try {
      isDir = fs.statSync(resolved).isDirectory()
    } catch {
      continue
    }

    if (isDir) {
      const skillFile = path.join(resolved, 'SKILL.md')
      if (!fs.existsSync(skillFile)) continue
      const skill = parseSkillFile(skillFile, starredNames, {
        name: entry.name,
        source: 'local',
        isInstalled: true,
        compatibleAgents: [agent.id],
      })
      if (skill) skills.push(skill)
    } else if (entry.name.endsWith('.md')) {
      const name = entry.name.replace(/\.md$/, '')
      const skill = parseSkillFile(resolved, starredNames, {
        name,
        source: 'local',
        isInstalled: true,
        compatibleAgents: [agent.id],
      })
      if (skill) skills.push(skill)
    }
  }

  return skills
}

/**
 * Scan ~/.claude/plugins/cache/
 * Structure: {marketplace}/{plugin}/{version}/skills/{skillName}/SKILL.md
 *   or occasionally:  …/skills/{skillName}.md  (flat file)
 * Only the latest version directory of each plugin is scanned.
 */
function scanPluginSkills(starredNames: string[], installedIds: Set<string>): Skill[] {
  if (!fs.existsSync(PLUGIN_CACHE_DIR)) return []
  const skills: Skill[] = []

  for (const mktEntry of fs.readdirSync(PLUGIN_CACHE_DIR, { withFileTypes: true })) {
    if (!mktEntry.isDirectory()) continue
    const marketplace = mktEntry.name
    const marketplaceDir = path.join(PLUGIN_CACHE_DIR, marketplace)

    for (const pluginEntry of fs.readdirSync(marketplaceDir, { withFileTypes: true })) {
      if (!pluginEntry.isDirectory()) continue
      const pluginName = pluginEntry.name
      const pluginDir = path.join(marketplaceDir, pluginName)

      const versionDir = latestVersion(pluginDir)
      if (!versionDir) continue

      const skillsDir = path.join(versionDir, 'skills')
      if (!fs.existsSync(skillsDir)) continue

      for (const skillEntry of fs.readdirSync(skillsDir, { withFileTypes: true })) {
        const skillEntryPath = path.join(skillsDir, skillEntry.name)
        const resolved = resolveSymlink(skillEntryPath)

        let isDir = false
        try { isDir = fs.statSync(resolved).isDirectory() } catch { continue }

        const skillName = skillEntry.name.replace(/\.md$/, '')
        // A plugin skill is "installed" if it also exists in ~/.claude/skills/
        const isInstalled = installedIds.has(skillName)

        if (isDir) {
          const skillFile = path.join(resolved, 'SKILL.md')
          if (!fs.existsSync(skillFile)) continue
          const skill = parseSkillFile(skillFile, starredNames, {
            name: skillName,
            source: 'plugin',
            marketplace,
            pluginName,
            isInstalled,
          })
          if (skill) skills.push(skill)
        } else if (skillEntry.name.endsWith('.md')) {
          const skill = parseSkillFile(resolved, starredNames, {
            name: skillName,
            source: 'plugin',
            marketplace,
            pluginName,
            isInstalled,
          })
          if (skill) skills.push(skill)
        }
      }
    }
  }

  return skills
}

export function loadSkills(): Skill[] {
  const { starred } = readState()
  const installedAgents = getInstalledAgents()

  // Collect all skills from all agents
  const allSkills: Skill[] = []
  for (const agent of installedAgents) {
    const agentSkills = agent.id === 'claude-code'
      ? scanLocalSkills(starred, agent.id)
      : scanAgentSkills(agent, starred)
    allSkills.push(...agentSkills)
  }

  // Deduplicate by resolving symlinks to real paths
  const skillMap = new Map<string, Skill>()
  for (const skill of allSkills) {
    const realPath = resolveSymlinkFully(skill.filePath)
    const existing = skillMap.get(realPath)
    if (existing) {
      // Merge compatibleAgents
      existing.compatibleAgents = [...new Set([...existing.compatibleAgents, ...skill.compatibleAgents])]
    } else {
      skillMap.set(realPath, skill)
    }
  }

  const localSkills = Array.from(skillMap.values())
  // Build a set of local skill names so plugin scan can mark installed state
  const localNames = new Set(localSkills.map(s => s.name))

  const pluginSkills = scanPluginSkills(starred, localNames)

  return [...localSkills, ...pluginSkills]
}

export function toggleStar(skillName: string): void {
  const state = readState()
  const idx = state.starred.indexOf(skillName)
  if (idx === -1) {
    state.starred.push(skillName)
  } else {
    state.starred.splice(idx, 1)
  }
  writeState(state)
}

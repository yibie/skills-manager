import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import matter from 'gray-matter'
import type { Skill } from '../types.js'

const SKILLS_DIRS = [
  path.join(os.homedir(), '.claude', 'skills'),
  path.join(os.homedir(), '.claude', 'plugins', 'cache'),
]

const STATE_FILE = path.join(os.homedir(), '.skills-manager', 'tui-state.json')

interface TuiState {
  starred: string[]
}

function readState(): TuiState {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')) as TuiState
  } catch {
    return { starred: [] }
  }
}

function writeState(state: TuiState): void {
  const dir = path.dirname(STATE_FILE)
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true })
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2))
}

function parseSkillFile(filePath: string, isInstalled: boolean, starredNames: string[]): Skill | null {
  try {
    const raw = fs.readFileSync(filePath, 'utf8')
    const { data, content } = matter(raw)
    const name = path.basename(filePath, path.extname(filePath))
    return {
      name,
      displayName: (data['name'] as string | undefined) ?? name,
      description: (data['description'] as string | undefined) ?? content.slice(0, 100).trim(),
      filePath,
      source: 'local',
      compatibleAgents: (data['agents'] as string[] | undefined) ?? ['claude-code'],
      isStarred: starredNames.includes(name),
      isInstalled,
      version: data['version'] as string | undefined,
    }
  } catch {
    return null
  }
}

function scanDir(dir: string, isInstalled: boolean, starredNames: string[]): Skill[] {
  if (!fs.existsSync(dir)) return []
  const skills: Skill[] = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isFile() && (entry.name.endsWith('.md') || entry.name.endsWith('.yaml'))) {
      const skill = parseSkillFile(path.join(dir, entry.name), isInstalled, starredNames)
      if (skill) skills.push(skill)
    }
  }
  return skills
}

export function loadSkills(): Skill[] {
  const { starred } = readState()
  const installedDir = path.join(os.homedir(), '.claude', 'skills')
  const installed = scanDir(installedDir, true, starred)
  const installedNames = new Set(installed.map(s => s.name))

  // Scan plugin cache dirs for marketplace skills not yet installed
  const cacheBase = path.join(os.homedir(), '.claude', 'plugins', 'cache')
  const marketplace: Skill[] = []
  if (fs.existsSync(cacheBase)) {
    for (const plugin of fs.readdirSync(cacheBase, { withFileTypes: true })) {
      if (!plugin.isDirectory()) continue
      const skillsDir = path.join(cacheBase, plugin.name, 'skills')
      for (const s of scanDir(skillsDir, false, starred)) {
        if (!installedNames.has(s.name)) {
          marketplace.push({ ...s, source: 'marketplace' })
        }
      }
    }
  }

  return [...installed, ...marketplace]
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

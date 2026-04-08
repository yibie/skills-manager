import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import type { DiscoverSkill, Skill } from '../types.js'
import { uninstall } from './InstallService.js'

const exec = promisify(execFile)

export async function installDiscoverSkill(entry: DiscoverSkill, agents: string[]): Promise<void> {
  for (const agent of agents) {
    await exec('npx', [
      '-y',
      'skills',
      'add',
      `https://github.com/${entry.source}`,
      '--skill',
      entry.skillId,
      '--yes',
      '--global',
      '--agent',
      agent,
    ])
  }
}

export async function uninstallDiscoverSkill(entry: DiscoverSkill, installedSkill: Skill | undefined): Promise<void> {
  if (!installedSkill) return
  await uninstall(installedSkill)
}

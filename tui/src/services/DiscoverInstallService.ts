import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import type { DiscoverSkill, Skill } from '../types.js'
import { uninstall } from './InstallService.js'

const exec = promisify(execFile)

// 供应链 pin:与 Swift 侧 SkillLifecycleService.skillsCLIVersion 保持一致,
// 未固定版本的 npx 在包被接管时等于本机任意代码执行。
const SKILLS_CLI_VERSION = '1.5.20'

export async function installDiscoverSkill(entry: DiscoverSkill, agents: string[]): Promise<void> {
  if (agents.length === 0) return
  // skills CLI 支持一次传多个 --agent,单次调用避免逐 agent 串行 npx
  await exec('npx', [
    '-y',
    `skills@${SKILLS_CLI_VERSION}`,
    'add',
    `https://github.com/${entry.source}`,
    '--skill',
    entry.skillId,
    '--yes',
    '--global',
    ...agents.flatMap(agent => ['--agent', agent]),
  ])
}

export async function uninstallDiscoverSkill(entry: DiscoverSkill, installedSkill: Skill | undefined): Promise<void> {
  if (!installedSkill) return
  await uninstall(installedSkill)
}

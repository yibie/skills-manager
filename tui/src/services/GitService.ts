import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import path from 'node:path'
import os from 'node:os'
import fs from 'node:fs'
import type { Commit, Skill } from '../types.js'

const exec = promisify(execFile)
const INSTALL_DIR = path.join(os.homedir(), '.claude', 'skills')

function installedRelativePath(skill: Skill): string | null {
  const installedDirectorySkill = path.join(skill.name, 'SKILL.md')
  if (fs.existsSync(path.join(INSTALL_DIR, installedDirectorySkill))) {
    return installedDirectorySkill
  }

  const ext = path.extname(skill.filePath) || '.md'
  const installedFileSkill = `${skill.name}${ext}`
  if (fs.existsSync(path.join(INSTALL_DIR, installedFileSkill))) {
    return installedFileSkill
  }

  if (skill.filePath.startsWith(`${INSTALL_DIR}${path.sep}`)) {
    return path.relative(INSTALL_DIR, skill.filePath)
  }

  return null
}

export async function getHistory(skill: Skill): Promise<Commit[]> {
  const relativePath = installedRelativePath(skill)
  if (!relativePath) return []

  try {
    const { stdout } = await exec('git', [
      '-C', INSTALL_DIR,
      'log', '--format=%H|%as|%s',
      '--', relativePath,
    ])
    const lines = stdout.trim().split('\n').filter(Boolean)
    return lines.map((line, idx) => {
      const [hash, date, ...msgParts] = line.split('|')
      return {
        hash: hash ?? '',
        date: date ?? '',
        message: msgParts.join('|'),
        isHead: idx === 0,
      }
    })
  } catch {
    return []
  }
}

export async function getDiff(skill: Skill, fromHash: string): Promise<string> {
  const relativePath = installedRelativePath(skill)
  if (!relativePath) return ''

  try {
    const { stdout } = await exec('git', [
      '-C', INSTALL_DIR,
      'diff', `${fromHash}..HEAD`,
      '--', relativePath,
    ])
    if (!stdout.trim()) return '(no changes)'
    const lines = stdout.split('\n').filter(l =>
      l.startsWith('+') || l.startsWith('-') || l.startsWith(' ')
    )
    return lines.slice(0, 30).join('\n')
  } catch {
    return ''
  }
}

export async function rollback(skill: Skill, toHash: string): Promise<void> {
  const relativePath = installedRelativePath(skill)
  if (!relativePath) {
    throw new Error(`Rollback failed for ${skill.name}: skill is not installed in ${INSTALL_DIR}`)
  }

  try {
    await exec('git', ['-C', INSTALL_DIR, 'checkout', toHash, '--', relativePath])
    await exec('git', ['-C', INSTALL_DIR, 'add', relativePath])
    await exec('git', ['-C', INSTALL_DIR, 'commit', '-m', `rollback: ${skill.name} to ${toHash.slice(0, 7)}`])
  } catch (err) {
    throw new Error(`Rollback failed for ${skill.name}: ${String(err)}`)
  }
}

import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import path from 'node:path'
import os from 'node:os'
import type { Commit } from '../types.js'

const exec = promisify(execFile)
const INSTALL_DIR = path.join(os.homedir(), '.claude', 'skills')

export async function getHistory(skillName: string): Promise<Commit[]> {
  const fileName = skillName.endsWith('.md') ? skillName : `${skillName}.md`
  try {
    const { stdout } = await exec('git', [
      '-C', INSTALL_DIR,
      'log', '--format=%H|%as|%s',
      '--', fileName,
    ])
    const lines = stdout.trim().split('\n').filter(Boolean)
    const commits = lines.map((line, idx) => {
      const [hash, date, ...msgParts] = line.split('|')
      return {
        hash: hash ?? '',
        date: date ?? '',
        message: msgParts.join('|'),
        isHead: idx === 0,
      }
    })
    return commits
  } catch {
    return []
  }
}

export async function getDiff(skillName: string, fromHash: string): Promise<string> {
  const fileName = skillName.endsWith('.md') ? skillName : `${skillName}.md`
  try {
    const { stdout } = await exec('git', [
      '-C', INSTALL_DIR,
      'diff', `${fromHash}..HEAD`,
      '--', fileName,
    ])
    if (!stdout.trim()) return '(no changes)'
    // Return only the diff lines (skip git header lines), capped at 30 lines
    const lines = stdout.split('\n').filter(l =>
      l.startsWith('+') || l.startsWith('-') || l.startsWith(' ')
    )
    return lines.slice(0, 30).join('\n')
  } catch {
    return ''
  }
}

export async function rollback(skillName: string, toHash: string): Promise<void> {
  const fileName = skillName.endsWith('.md') ? skillName : `${skillName}.md`
  try {
    await exec('git', ['-C', INSTALL_DIR, 'checkout', toHash, '--', fileName])
    await exec('git', ['-C', INSTALL_DIR, 'commit', '-m', `rollback: ${skillName} to ${toHash.slice(0, 7)}`])
  } catch (err) {
    throw new Error(`Rollback failed for ${skillName}: ${String(err)}`)
  }
}

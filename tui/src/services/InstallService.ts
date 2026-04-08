import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import type { Skill } from '../types.js'

const exec = promisify(execFile)
const INSTALL_DIR = path.join(os.homedir(), '.claude', 'skills')

function ensureInstallDir(): void {
  if (!fs.existsSync(INSTALL_DIR)) {
    fs.mkdirSync(INSTALL_DIR, { recursive: true })
  }
}

function sourcePath(skill: Skill): string {
  return skill.directoryPath ?? skill.filePath
}

function destinationPath(skill: Skill): string {
  if (skill.directoryPath) return path.join(INSTALL_DIR, skill.name)
  const ext = path.extname(skill.filePath) || '.md'
  return path.join(INSTALL_DIR, `${skill.name}${ext}`)
}

function copyRecursive(src: string, dest: string): void {
  const stat = fs.statSync(src)

  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true })
    for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
      copyRecursive(path.join(src, entry.name), path.join(dest, entry.name))
    }
    return
  }

  fs.mkdirSync(path.dirname(dest), { recursive: true })
  fs.copyFileSync(src, dest)
}

async function commitAll(message: string): Promise<void> {
  const gitDir = path.join(INSTALL_DIR, '.git')

  if (!fs.existsSync(gitDir)) {
    await exec('git', ['-C', INSTALL_DIR, 'init'])
  }

  await exec('git', ['-C', INSTALL_DIR, 'add', '-A'])
  const { stdout } = await exec('git', ['-C', INSTALL_DIR, 'status', '--porcelain'])
  if (!stdout.trim()) return
  await exec('git', ['-C', INSTALL_DIR, 'commit', '-m', message])
}

export async function install(skill: Skill): Promise<void> {
  ensureInstallDir()

  const src = sourcePath(skill)
  const dest = destinationPath(skill)

  if (!fs.existsSync(src)) {
    throw new Error(`Skill source not found: ${src}`)
  }

  if (fs.existsSync(dest)) {
    fs.rmSync(dest, { recursive: true, force: true })
  }

  copyRecursive(src, dest)

  try {
    await commitAll(`install: ${skill.name}`)
  } catch (err) {
    throw new Error(`Git tracking failed for ${skill.name}: ${String(err)}`)
  }
}

export async function uninstall(skill: Skill): Promise<void> {
  ensureInstallDir()

  const target = destinationPath(skill)
  if (!fs.existsSync(target)) return

  fs.rmSync(target, { recursive: true, force: true })

  const gitDir = path.join(INSTALL_DIR, '.git')
  if (!fs.existsSync(gitDir)) return

  try {
    await commitAll(`uninstall: ${skill.name}`)
  } catch (err) {
    throw new Error(`Git tracking failed for ${skill.name}: ${String(err)}`)
  }
}

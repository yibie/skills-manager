import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import type { Skill } from '../types.js'

const exec = promisify(execFile)

const INSTALL_DIR = path.join(os.homedir(), '.claude', 'skills')

export async function install(skill: Skill): Promise<void> {
  if (!fs.existsSync(INSTALL_DIR)) {
    fs.mkdirSync(INSTALL_DIR, { recursive: true })
  }
  const dest = path.join(INSTALL_DIR, path.basename(skill.filePath))
  fs.copyFileSync(skill.filePath, dest)

  // git init + initial commit if not already a git repo
  const gitDir = path.join(INSTALL_DIR, '.git')
  try {
    if (!fs.existsSync(gitDir)) {
      await exec('git', ['-C', INSTALL_DIR, 'init'])
      await exec('git', ['-C', INSTALL_DIR, 'add', '.'])
      await exec('git', ['-C', INSTALL_DIR, 'commit', '-m', 'Initial install'])
    } else {
      await exec('git', ['-C', INSTALL_DIR, 'add', path.basename(skill.filePath)])
      await exec('git', ['-C', INSTALL_DIR, 'commit', '-m', `install: ${skill.name}`])
    }
  } catch (err) {
    throw new Error(`Git tracking failed for ${skill.name}: ${String(err)}`)
  }
}

export async function uninstall(skill: Skill): Promise<void> {
  const target = path.join(INSTALL_DIR, path.basename(skill.filePath))
  if (!fs.existsSync(target)) return
  fs.rmSync(target)
  const gitDir = path.join(INSTALL_DIR, '.git')
  if (fs.existsSync(gitDir)) {
    try {
      await exec('git', ['-C', INSTALL_DIR, 'rm', path.basename(skill.filePath)])
      await exec('git', ['-C', INSTALL_DIR, 'commit', '-m', `uninstall: ${skill.name}`])
    } catch (err) {
      throw new Error(`Git tracking failed for ${skill.name}: ${String(err)}`)
    }
  }
}

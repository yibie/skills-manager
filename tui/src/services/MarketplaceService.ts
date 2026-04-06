import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const CACHE_DIR = path.join(os.homedir(), '.skills-manager', 'cache')
const CACHE_FILE = path.join(CACHE_DIR, 'marketplace.json')
const CACHE_TTL_MS = 30 * 60 * 1000  // 30 minutes

const MARKETPLACE_URL =
  'https://api.github.com/repos/anthropics/claude-code/contents/skills'

interface MarketplaceEntry {
  name: string
  description: string
  downloadUrl: string
}

function readCache(): MarketplaceEntry[] | null {
  try {
    const stat = fs.statSync(CACHE_FILE)
    if (Date.now() - stat.mtimeMs > CACHE_TTL_MS) return null
    return JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8')) as MarketplaceEntry[]
  } catch {
    return null
  }
}

function writeCache(entries: MarketplaceEntry[]): void {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true })
  fs.writeFileSync(CACHE_FILE, JSON.stringify(entries, null, 2))
}

export async function syncMarketplace(): Promise<MarketplaceEntry[]> {
  const cached = readCache()
  if (cached) return cached

  try {
    const res = await fetch(MARKETPLACE_URL, {
      headers: { 'User-Agent': 'skills-manager-tui' },
    })
    if (!res.ok) return []
    const files = await res.json() as Array<{ name: string; download_url: string }>
    const entries: MarketplaceEntry[] = files
      .filter(f => f.name.endsWith('.md'))
      .map(f => ({
        name: f.name.replace(/\.md$/, ''),
        description: '',
        downloadUrl: f.download_url,
      }))
    writeCache(entries)
    return entries
  } catch {
    return []
  }
}

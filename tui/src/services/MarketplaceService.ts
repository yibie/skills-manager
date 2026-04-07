/**
 * MarketplaceService
 *
 * Reads Claude Code's existing local plugin metadata — no network requests.
 * Claude Code itself handles syncing known_marketplaces.json and marketplace.json files.
 *
 * Key files (maintained by Claude Code, not by us):
 *   ~/.claude/plugins/known_marketplaces.json      — list of registered marketplaces
 *   ~/.claude/plugins/marketplaces/{name}/.claude-plugin/marketplace.json  — plugin catalog
 *   ~/.claude/plugins/installed_plugins.json       — installed plugin records
 */

import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

const PLUGINS_BASE = path.join(os.homedir(), '.claude', 'plugins')
const KNOWN_MARKETPLACES_FILE = path.join(PLUGINS_BASE, 'known_marketplaces.json')
const INSTALLED_PLUGINS_FILE = path.join(PLUGINS_BASE, 'installed_plugins.json')

// ── Types ────────────────────────────────────────────────────────────────────

export interface MarketplacePlugin {
  /** "{marketplace}:{name}" */
  id: string
  name: string
  description: string
  marketplace: string
  category?: string
  isInstalled: boolean
  installedVersion?: string
}

interface KnownMarketplace {
  source: { source: string; repo?: string }
  installLocation: string
  lastUpdated?: string
}

interface InstalledPluginRecord {
  installPath: string
  version: string
  scope: string
}

interface InstalledPluginsFile {
  plugins: Record<string, InstalledPluginRecord[]>
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function readJSON<T>(filePath: string): T | null {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T
  } catch {
    return null
  }
}

function knownMarketplaceNames(): string[] {
  const dict = readJSON<Record<string, KnownMarketplace>>(KNOWN_MARKETPLACES_FILE)
  if (!dict) return []
  return Object.keys(dict).sort()
}

function loadCachedPlugins(marketplaceName: string): MarketplacePlugin[] {
  const catalogPath = path.join(
    PLUGINS_BASE, 'marketplaces', marketplaceName, '.claude-plugin', 'marketplace.json'
  )
  const root = readJSON<{ plugins?: Array<Record<string, unknown>> }>(catalogPath)
  if (!root?.plugins) return []

  return root.plugins.flatMap(dict => {
    const name = dict['name']
    if (typeof name !== 'string') return []
    const description = typeof dict['description'] === 'string' ? dict['description'] : ''
    const category = typeof dict['category'] === 'string' ? dict['category'] : undefined
    const plugin: MarketplacePlugin = {
      id: `${marketplaceName}:${name}`,
      name,
      description,
      marketplace: marketplaceName,
      category,
      isInstalled: false,
    }
    return [plugin]
  })
}

// ── Public API ───────────────────────────────────────────────────────────────

/**
 * Load all plugins from all known marketplace catalogs, merged with install state.
 * This is purely a local filesystem read — instant, no network.
 */
export function loadMarketplacePlugins(): MarketplacePlugin[] {
  const names = knownMarketplaceNames()
  const plugins = names.flatMap(name => loadCachedPlugins(name))

  // Merge install state from installed_plugins.json
  const installed = readJSON<InstalledPluginsFile>(INSTALLED_PLUGINS_FILE)
  if (!installed?.plugins) return plugins

  return plugins.map(plugin => {
    // Key format in installed_plugins.json: "{pluginName}@{marketplace}"
    const key = `${plugin.name}@${plugin.marketplace}`
    const records = installed.plugins[key]
    if (records && records.length > 0) {
      return {
        ...plugin,
        isInstalled: true,
        installedVersion: records[0]?.version,
      }
    }
    return plugin
  })
}

/**
 * No-op: Claude Code handles marketplace syncing via its own update mechanism.
 * We call this from app.tsx for API compatibility but there's nothing to do.
 */
export async function syncMarketplace(): Promise<void> {
  // Intentionally empty — Claude Code owns the sync lifecycle
}

import blessed from 'blessed'
import { execFile } from 'node:child_process'
import { loadSkills, toggleStar, getInstalledAgents } from './services/SkillStore.js'
import { install, uninstall } from './services/InstallService.js'
import { loadSkillsDirectory, syncSkillsDirectory, fetchDiscoverSkillDetail } from './services/SkillsDirectoryService.js'
import { installDiscoverSkill, uninstallDiscoverSkill } from './services/DiscoverInstallService.js'
import { getHistory, getDiff, rollback } from './services/GitService.js'
import type { Skill, AgentDefinition, SidebarSelection, DiscoverSkill, Commit } from './types.js'

const terminalName = (() => {
  const term = process.env.TERM || 'xterm-256color'
  if (term.includes('ghostty')) return 'xterm-256color'
  return term
})()

// Create screen with better terminal compatibility
const screen = blessed.screen({
  smartCSR: true,
  title: 'Skills Manager',
  fullUnicode: true,
  terminal: terminalName,
  warnings: false, // Suppress terminfo warnings
  ignoreLocked: ['C-c'],
})

// State
let skills = loadSkills()
let agents = getInstalledAgents()
let discoverState = loadSkillsDirectory()
let discoverDetails: Record<string, DiscoverSkill> = {}
let sidebarSelection: SidebarSelection = 'library:all' as SidebarSelection
let selectedIndex = 0
let activePanel: 'sidebar' | 'list' | 'detail' = 'list'
let discoverSourceFilter = 'all'
let statusMessage = ''

// Create layout boxes
const sidebar = blessed.box({
  parent: screen,
  top: 0,
  left: 0,
  width: '20%',
  height: '100%-1',
  border: { type: 'line' },
  style: {
    border: { fg: 'white' },
  },
  tags: true,
  scrollable: true,
  alwaysScroll: true,
})

const list = blessed.list({
  parent: screen,
  top: 0,
  left: '20%',
  width: '40%',
  height: '100%-1',
  border: { type: 'line' },
  style: {
    border: { fg: 'white' },
    selected: { bg: 'blue', fg: 'white' },
  },
  tags: true,
  scrollable: true,
  interactive: true,
})

// Listen to list selection changes
list.on('select', () => {
  if (activePanel === 'list') {
    const rawSelected = (list as any).selected as number
    selectedIndex = sidebarSelection === 'library:discover'
      ? Math.max(0, rawSelected - 1)
      : rawSelected
    updateDetail()
    updateStatusBar()
  }
})

const detail = blessed.box({
  parent: screen,
  top: 0,
  left: '60%',
  width: '40%',
  height: '100%-1',
  border: { type: 'line' },
  style: {
    border: { fg: 'white' },
  },
  tags: true,
  scrollable: true,
  alwaysScroll: true,
  keys: true,
  vi: true,
})

const statusBar = blessed.box({
  parent: screen,
  bottom: 0,
  left: 0,
  width: '100%',
  height: 1,
  style: {
    fg: 'white',
    bg: 'black',
  },
  tags: true,
})

type SidebarRow = {
  key: SidebarSelection
  label: string
  count: number
}

// Helper functions
function applySidebarSelection(skills: Skill[], selection: SidebarSelection): Skill[] {
  if (selection === 'library:discover') return []
  if (selection === 'library:installed') return skills.filter(skill => skill.isInstalled)
  if (selection === 'library:starred') return skills.filter(skill => skill.isStarred)
  if (selection.startsWith('agent:')) {
    const agentId = selection.slice('agent:'.length)
    return skills.filter(skill => skill.compatibleAgents.includes(agentId))
  }
  if (selection.startsWith('source:')) {
    const sourceId = selection.slice('source:'.length)
    if (sourceId === 'local') return skills.filter(skill => skill.source === 'local')

    const pluginBundleSkills = skills.filter(skill =>
      skill.source === 'plugin' &&
      `${skill.pluginSource ?? 'unknown-source'}::${skill.pluginName ?? 'unknown-plugin'}` === sourceId
    )
    if (pluginBundleSkills.length > 0) return pluginBundleSkills

    return skills.filter(skill => skill.pluginSource === sourceId)
  }
  return skills
}

function isDiscoverSkillInstalled(entry: DiscoverSkill, skills: Skill[]): Skill | undefined {
  return skills.find(skill => skill.resourceType === 'skill' && (skill.name === entry.skillId || skill.name === entry.name))
}

function getFilteredSkills(): Skill[] {
  return applySidebarSelection(skills, sidebarSelection)
}

function getFilteredDiscoverEntries(): DiscoverSkill[] {
  return sidebarSelection === 'library:discover'
    ? discoverState.entries.filter(entry => discoverSourceFilter === 'all' || entry.source === discoverSourceFilter)
    : []
}

function getSidebarRows(): SidebarRow[] {
  const skillAgentMap = new Map<string, string>()
  for (const skill of skills) {
    for (const agentId of skill.compatibleAgents) {
      if (!skillAgentMap.has(agentId)) skillAgentMap.set(agentId, agentId)
    }
  }
  for (const agent of agents) skillAgentMap.set(agent.id, agent.label)

  const sortedAgents = Array.from(skillAgentMap.entries())
    .map(([id, fallback]) => ({ id, label: agents.find(agent => agent.id === id)?.label ?? fallback }))
    .sort((a, b) => a.label.localeCompare(b.label))

  const localCount = skills.filter(skill => skill.source === 'local').length
  const pluginBundleCounts = new Map<string, { label: string; count: number }>()
  for (const skill of skills) {
    if (skill.source !== 'plugin') continue

    const pluginSource = skill.pluginSource ?? 'unknown-source'
    const pluginName = skill.pluginName ?? 'unknown-plugin'
    const id = `${pluginSource}::${pluginName}`
    const current = pluginBundleCounts.get(id)
    if (current) {
      current.count += 1
    } else {
      pluginBundleCounts.set(id, {
        label: `${pluginSource} · ${pluginName}`,
        count: 1,
      })
    }
  }

  const sourceRows: SidebarRow[] = [
    { key: 'source:local', label: 'Local', count: localCount },
    ...Array.from(pluginBundleCounts.entries())
      .map(([id, value]) => ({ key: `source:${id}` as SidebarSelection, label: value.label, count: value.count }))
      .sort((a, b) => a.label.localeCompare(b.label)),
  ]

  return [
    { key: 'library:all', label: 'All', count: skills.length },
    { key: 'library:discover', label: 'Discover', count: discoverState.total },
    { key: 'library:installed', label: 'Installed', count: skills.filter(skill => skill.isInstalled).length },
    { key: 'library:starred', label: 'Starred', count: skills.filter(skill => skill.isStarred).length },
    ...sortedAgents.map(agent => ({
      key: `agent:${agent.id}` as SidebarSelection,
      label: agent.label,
      count: skills.filter(skill => skill.compatibleAgents.includes(agent.id)).length,
    })),
    ...sourceRows,
  ]
}

function getSelectedSkill(): Skill | undefined {
  return getFilteredSkills()[selectedIndex]
}

function getSelectedDiscoverEntry(): DiscoverSkill | undefined {
  return getFilteredDiscoverEntries()[selectedIndex]
}

function getDiscoverSources(): string[] {
  return ['all', ...Array.from(new Set(discoverState.entries.map(entry => entry.source))).sort()]
}

function cycleOption(current: string, options: string[], step: 1 | -1): string {
  if (options.length === 0) return current
  const index = Math.max(0, options.indexOf(current))
  return options[(index + step + options.length) % options.length] || current
}

function refreshLocalSkills() {
  skills = loadSkills()
  agents = getInstalledAgents()
  return skills
}

function escapeTags(text: string): string {
  return text.replace(/\{/g, '{open}').replace(/\}/g, '{close}')
}

function openTarget(target: string, callback?: (error?: Error) => void) {
  const command = process.platform === 'darwin'
    ? 'open'
    : process.platform === 'win32'
      ? 'cmd'
      : 'xdg-open'

  const args = process.platform === 'win32'
    ? ['/c', 'start', '', target]
    : [target]

  execFile(command, args, error => {
    callback?.(error ?? undefined)
  })
}

function showErrorStatus(error: unknown, timeout = 3000) {
  statusMessage = String(error)
  render()
  setTimeout(() => { statusMessage = ''; render() }, timeout)
}

function showSuccessStatus(message: string, timeout = 2000) {
  statusMessage = message
  render()
  setTimeout(() => { statusMessage = ''; render() }, timeout)
}

function fullRefresh() {
  statusMessage = 'Refreshing all...'
  discoverDetails = {}
  refreshLocalSkills()
  screen.realloc()
  render()

  syncSkillsDirectory()
    .then(result => {
      discoverState = result
      screen.realloc()
      showSuccessStatus('Fully refreshed')
    })
    .catch(error => {
      showErrorStatus(error)
    })
}

function installSelectedItem() {
  if (activePanel !== 'list' && activePanel !== 'detail') return

  if (sidebarSelection === 'library:discover') {
    const entry = getSelectedDiscoverEntry()
    if (!entry) return

    const installedSkill = isDiscoverSkillInstalled(entry, skills)
    if (installedSkill) {
      showSuccessStatus(`Already installed: ${entry.skillId}. Press x to uninstall.`)
      return
    }

    showAgentSelectionDialog(entry)
    return
  }

  const skill = getSelectedSkill()
  if (!skill) return

  if (skill.resourceType === 'extension') {
    showSuccessStatus('This plugin resource is read-only here')
    return
  }

  if (!skill.compatibleAgents.includes('claude-code')) {
    showSuccessStatus('Direct install is currently only supported for Claude Code skills')
    return
  }

  if (skill.isInstalled) {
    showSuccessStatus(`Already installed: ${skill.name}. Press x to uninstall.`)
    return
  }

  install(skill)
    .then(() => {
      refreshLocalSkills()
      showSuccessStatus(`Installed: ${skill.name}`)
    })
    .catch(error => {
      showErrorStatus(error)
    })
}

function uninstallSelectedItem() {
  if (activePanel !== 'list' && activePanel !== 'detail') return

  if (sidebarSelection === 'library:discover') {
    const entry = getSelectedDiscoverEntry()
    if (!entry) return

    const installedSkill = isDiscoverSkillInstalled(entry, skills)
    if (!installedSkill) {
      showSuccessStatus(`Not installed: ${entry.skillId}`)
      return
    }

    uninstallDiscoverSkill(entry, installedSkill)
      .then(() => {
        refreshLocalSkills()
        showSuccessStatus(`Uninstalled skill: ${entry.skillId}`)
      })
      .catch(error => {
        showErrorStatus(error)
      })
    return
  }

  const skill = getSelectedSkill()
  if (!skill) return

  if (skill.resourceType === 'extension') {
    showSuccessStatus('This plugin resource is read-only here')
    return
  }

  if (!skill.compatibleAgents.includes('claude-code')) {
    showSuccessStatus('Direct uninstall is currently only supported for Claude Code skills')
    return
  }

  if (!skill.isInstalled) {
    showSuccessStatus(`Not installed: ${skill.name}`)
    return
  }

  uninstall(skill)
    .then(() => {
      refreshLocalSkills()
      showSuccessStatus(`Uninstalled: ${skill.name}`)
    })
    .catch(error => {
      showErrorStatus(error)
    })
}

function updateSidebar() {
  const rows = getSidebarRows()
  const lines: string[] = []

  const pushSection = (title: string, sectionRows: SidebarRow[]) => {
    if (sectionRows.length === 0) return
    if (lines.length > 0) lines.push('')
    lines.push(`{bold}${title}{/bold}`)
    sectionRows.forEach(row => {
      const countText = ` (${row.count})`
      const maxLabelWidth = 16 - countText.length
      const truncatedLabel = row.label.length > maxLabelWidth
        ? `${row.label.slice(0, Math.max(0, maxLabelWidth - 1))}…`
        : row.label
      const line = `○ ${truncatedLabel}${countText}`
      lines.push(sidebarSelection === row.key ? `{blue-fg}${line}{/blue-fg}` : `  ${truncatedLabel}${countText}`)
    })
  }

  pushSection('Library', rows.filter(row => row.key.startsWith('library:')))
  pushSection('Agents', rows.filter(row => row.key.startsWith('agent:')))
  pushSection('Sources', rows.filter(row => row.key.startsWith('source:')))

  sidebar.setContent(lines.join('\n'))
  sidebar.style.border.fg = activePanel === 'sidebar' ? 'blue' : 'white'
  screen.render()
}

function getListInnerWidth(): number {
  const listWidth = typeof list.width === 'number' ? list.width : 0
  const screenWidth = typeof screen.width === 'number' ? screen.width : 100
  const computedWidth = listWidth > 0 ? listWidth : Math.floor(screenWidth * 0.4)
  const innerPadding = Number(list.iwidth) || 0

  return Math.max(8, computedWidth - innerPadding - 1)
}

function textWidth(text: string): number {
  return Number(list.strWidth(text)) || 0
}

function truncateToListWidth(text: string, maxWidth: number): string {
  if (maxWidth <= 0) return ''
  if (textWidth(text) <= maxWidth) return text

  const ellipsis = '…'
  const ellipsisWidth = textWidth(ellipsis)
  let out = ''
  let width = 0

  for (const char of text) {
    const charWidth = textWidth(char)
    if (width + charWidth + ellipsisWidth > maxWidth) break
    out += char
    width += charWidth
  }

  return out + ellipsis
}

function formatDiscoverListItem(entry: DiscoverSkill): string {
  const installed = isDiscoverSkillInstalled(entry, skills)
  const marker = installed ? '{green-fg}●{/green-fg}' : ' '
  const plainPrefix = `${installed ? '●' : ' '} `
  const nameWidth = Math.max(1, getListInnerWidth() - textWidth(plainPrefix))
  return `${marker} ${truncateToListWidth(entry.name, nameWidth)}`
}

function formatSkillListItem(skill: Skill): string {
  const star = skill.isStarred ? '{yellow-fg}★{/yellow-fg}' : ' '
  const installed = skill.isInstalled ? '{green-fg}●{/green-fg}' : ' '
  const sourceMarker = skill.source === 'plugin' || skill.resourceType === 'extension'
    ? '{magenta-fg}P{/magenta-fg}'
    : '{cyan-fg}L{/cyan-fg}'
  const plainTypeMarker = skill.source === 'plugin' || skill.resourceType === 'extension' ? 'P' : 'L'
  const plainPrefix = `${skill.isStarred ? '★' : ' '}${skill.isInstalled ? '●' : ' '}${plainTypeMarker} `
  const nameWidth = Math.max(1, getListInnerWidth() - textWidth(plainPrefix))
  const label = skill.resourceType === 'extension'
    ? `${skill.displayName} · ${skill.pluginName ?? skill.extensionScope ?? 'plugin'}`
    : skill.source === 'plugin'
      ? `${skill.displayName} · ${skill.pluginName ?? skill.pluginSource ?? 'plugin'}`
      : skill.displayName
  return `${star}${installed}${sourceMarker} ${truncateToListWidth(label, nameWidth)}`
}

function updateList(resetSelection = false) {
  const filteredSkills = applySidebarSelection(skills, sidebarSelection)
  const filteredDiscoverEntries = sidebarSelection === 'library:discover'
    ? discoverState.entries.filter(e => discoverSourceFilter === 'all' || e.source === discoverSourceFilter)
    : []

  let items: string[] = []

  if (sidebarSelection === 'library:discover') {
    const sourceLabel = discoverSourceFilter === 'all' ? 'All sources' : discoverSourceFilter
    items = [
      `{bold}Discover{/bold} {gray-fg}· src: ${escapeTags(sourceLabel)}{/gray-fg}`,
      ...filteredDiscoverEntries.map(formatDiscoverListItem),
    ]
  } else {
    items = filteredSkills.map(formatSkillListItem)
  }

  list.setItems(items)

  if (sidebarSelection === 'library:discover') {
    const maxIndex = Math.max(0, filteredDiscoverEntries.length - 1)
    selectedIndex = Math.min(Math.max(selectedIndex, 0), maxIndex)
    list.select(filteredDiscoverEntries.length > 0 ? selectedIndex + 1 : 0)
    list.style.border.fg = activePanel === 'list' ? 'blue' : 'white'
    screen.render()
    return
  }

  const maxIndex = Math.max(0, items.length - 1)
  selectedIndex = Math.min(Math.max(selectedIndex, 0), maxIndex)
  list.select(selectedIndex)

  list.style.border.fg = activePanel === 'list' ? 'blue' : 'white'
  screen.render()
}

function updateDetail() {
  const filteredSkills = applySidebarSelection(skills, sidebarSelection)
  const filteredDiscoverEntries = sidebarSelection === 'library:discover'
    ? discoverState.entries.filter(e => discoverSourceFilter === 'all' || e.source === discoverSourceFilter)
    : []

  let content = ''

  if (sidebarSelection === 'library:discover') {
    const entry = filteredDiscoverEntries[selectedIndex]
    if (entry) {
      const detailEntry = discoverDetails[entry.id] ?? entry
      content = `{bold}${detailEntry.name}{/bold}\n`
      content += `{cyan-fg}${detailEntry.source}{/cyan-fg}\n`
      content += `${'─'.repeat(40)}\n`
      content += `Installs: ${detailEntry.installs.toLocaleString()}\n`
      content += `Repo: ${detailEntry.repoUrl}\n`

      if (detailEntry.summary) {
        content += `\n{bold}Summary{/bold}\n${detailEntry.summary}\n`
      } else if (!discoverDetails[entry.id]) {
        content += `\n{gray-fg}Loading details...{/gray-fg}\n`
        // Async load details
        fetchDiscoverSkillDetail(entry)
          .then(detail => {
            discoverDetails[detail.id] = detail
            // Only update if still on the same entry
            const currentEntry = filteredDiscoverEntries[selectedIndex]
            if (currentEntry && currentEntry.id === detail.id) {
              updateDetail()
            }
          })
          .catch(() => {})
      }

      if (detailEntry.readmeExcerpt) {
        content += `\n{bold}SKILL.md excerpt{/bold}\n${detailEntry.readmeExcerpt.slice(0, 500)}\n`
      }

      content += `\n{bold}Install command{/bold}\n${detailEntry.installCommand}\n`
    }
  } else {
    const skill = filteredSkills[selectedIndex]
    if (skill) {
      const sourceText = skill.resourceType === 'extension'
        ? skill.source === 'plugin'
          ? `Plugin · ${skill.pluginSource ?? 'unknown source'} · ${skill.pluginName ?? 'unknown package'}`
          : `Plugin · local extension · ${skill.extensionScope ?? 'local'}`
        : skill.source === 'plugin'
          ? `Plugin · ${skill.pluginSource ?? 'unknown source'} · ${skill.pluginName ?? 'unknown plugin'}`
          : 'Local / user-installed'

      content = `{bold}${skill.displayName}{/bold}\n`
      content += `{cyan-fg}${sourceText}{/cyan-fg}\n`
      content += `${'─'.repeat(40)}\n`
      content += `${skill.description}\n`
      content += `\n{bold}Type:{/bold} ${skill.resourceType === 'extension' ? 'Plugin' : 'Skill'}\n`
      content += `\n{bold}Compatible:{/bold}\n`
      skill.compatibleAgents.forEach(agent => {
        content += `{green-fg}✓{/green-fg} ${agent}\n`
      })

      if (skill.version) {
        content += `\nVersion: ${skill.version}\n`
      }

      content += `\nStarred: ${skill.isStarred ? 'Yes' : 'No'}\n`
      content += `Installed: ${skill.isInstalled ? 'Yes' : 'No'}\n`
    }
  }

  detail.setContent(content)
  detail.style.border.fg = activePanel === 'detail' ? 'blue' : 'white'
  screen.render()
}

function updateStatusBar() {
  let text = 'h/l: panels  j/k: move  g/G: first/last  /: search  q: quit'

  if (statusMessage) {
    text = `{red-fg}${statusMessage}{/red-fg}`
  } else if (activePanel === 'list' || activePanel === 'detail') {
    if (sidebarSelection === 'library:discover') {
      text += '  ·  i: install  x: uninstall  d: details  o: open file  O: source page  r: refresh dir  R: full refresh  f/F: Switch Source  0: Reset Source'
    } else {
      text += '  ·  i: install  x: uninstall  s: star  o: open file  H: history  R: full refresh'
    }
  }

  statusBar.setContent(text)
  screen.render()
}

function render() {
  updateSidebar()
  updateList(true) // Reset selection when rendering full view
  updateDetail()
  updateStatusBar()

  // Set focus to the active panel
  if (activePanel === 'sidebar') {
    sidebar.focus()
  } else if (activePanel === 'list') {
    list.focus()
  } else if (activePanel === 'detail') {
    detail.focus()
  }
}

function onGlobalKey(keys: string[], handler: () => void) {
  const normalizedKeys = new Set<string>()

  keys.forEach(key => {
    normalizedKeys.add(key)

    if (/^[A-Z]$/.test(key)) {
      normalizedKeys.add(`S-${key.toLowerCase()}`)
    }
  })

  normalizedKeys.forEach(key => {
    screen.on(`key ${key}`, handler)
  })
}

function showAgentSelectionDialog(entry: DiscoverSkill) {
  // Create overlay
  const overlay = blessed.box({
    parent: screen,
    top: 'center',
    left: 'center',
    width: 50,
    height: agents.length + 6,
    border: { type: 'line' },
    style: {
      border: { fg: 'blue' },
      bg: 'black',
    },
    tags: true,
  })

  const title = blessed.text({
    parent: overlay,
    top: 0,
    left: 'center',
    content: `{bold}Install ${entry.name}{/bold}`,
    tags: true,
  })

  const instruction = blessed.text({
    parent: overlay,
    top: 1,
    left: 1,
    content: 'Select agents (Space to toggle, Enter to install, Esc to cancel):',
    tags: true,
  })

  const agentList = blessed.list({
    parent: overlay,
    top: 3,
    left: 1,
    width: '100%-2',
    height: agents.length,
    keys: true,
    vi: true,
    style: {
      selected: { bg: 'blue', fg: 'white' },
    },
    tags: true,
  })

  const selectedAgents = new Set<string>(['claude-code']) // Default to claude-code
  const agentItems = agents.map(a => `[✓] ${a.label}`)
  agentItems.unshift('[✓] All')
  agentList.setItems(agentItems)
  agentList.select(0)

  const closeDialog = () => {
    screen.grabKeys = false
    overlay.destroy()
    render()
  }

  screen.grabKeys = true

  agentList.on('key space', () => {
    const idx = (agentList as any).selected
    if (idx === 0) {
      // Toggle all
      if (selectedAgents.size === agents.length) {
        selectedAgents.clear()
      } else {
        selectedAgents.clear()
        agents.forEach(a => selectedAgents.add(a.id))
      }
    } else {
      const agent = agents[idx - 1]
      if (agent) {
        if (selectedAgents.has(agent.id)) {
          selectedAgents.delete(agent.id)
        } else {
          selectedAgents.add(agent.id)
        }
      }
    }

    // Update display
    const newItems = agents.map(a =>
      selectedAgents.has(a.id) ? `[✓] ${a.label}` : `[ ] ${a.label}`
    )
    newItems.unshift(selectedAgents.size === agents.length ? '[✓] All' : '[ ] All')
    agentList.setItems(newItems)
    agentList.select(idx)
    screen.render()
  })

  agentList.on('key enter', () => {
    closeDialog()

    if (selectedAgents.size === 0) {
      showSuccessStatus('No agents selected')
      return
    }

    const agentIds = Array.from(selectedAgents)
    installDiscoverSkill(entry, agentIds)
      .then(() => {
        const nextSkills = refreshLocalSkills()
        const targetIndex = Math.max(0, nextSkills.findIndex(skill => skill.name === entry.skillId || skill.name === entry.name))
        sidebarSelection = 'library:all'
        activePanel = 'list'
        selectedIndex = targetIndex === -1 ? 0 : targetIndex
        showSuccessStatus(`Installed ${entry.skillId} to ${agentIds.length} agent(s)`)
      })
      .catch(err => {
        showErrorStatus(err)
      })
  })

  agentList.on('key escape', closeDialog)
  agentList.on('key q', closeDialog)

  agentList.focus()
  screen.render()
}

function openSkillInEditor(skill: Skill) {
  const editor = process.env['EDITOR']
  const fallback = () => {
    openTarget(skill.filePath, error => {
      if (error) showErrorStatus(error)
      else showSuccessStatus(`Opening source file: ${skill.filePath}`)
    })
  }

  if (!editor) {
    fallback()
    return
  }

  execFile(editor, [skill.filePath], error => {
    if (error) {
      fallback()
      return
    }
    showSuccessStatus(`Opening source file: ${skill.filePath}`)
  })
}

function openSelectedSourceFile() {
  if (activePanel !== 'list' && activePanel !== 'detail') return

  if (sidebarSelection === 'library:discover') {
    const entry = getSelectedDiscoverEntry()
    if (!entry) return

    const sourceSkill = skills.find(skill => skill.resourceType === 'skill' && (skill.name === entry.skillId || skill.name === entry.name))
    if (!sourceSkill?.filePath) {
      showSuccessStatus('No local source file available. Press O to open the source page.')
      return
    }

    openSkillInEditor(sourceSkill)
    return
  }

  const skill = getSelectedSkill()
  if (!skill?.filePath) return
  openSkillInEditor(skill)
}

function openDiscoverSourcePage(entry: DiscoverSkill) {
  const url = `https://skills.sh/${entry.source}/${entry.skillId}`
  openTarget(url, error => {
    if (error) showErrorStatus(error)
    else showSuccessStatus(`Opening source page: ${url}`)
  })
}

function showSearchOverlay() {
  const mode = sidebarSelection === 'library:discover' ? 'discover' : 'skills'
  const screenWidth = typeof screen.width === 'number' ? screen.width : 100
  const screenHeight = typeof screen.height === 'number' ? screen.height : 30
  const overlayWidth = Math.max(50, Math.min(screenWidth - 4, 100))
  const overlayHeight = Math.max(14, Math.min(screenHeight - 2, 20))
  const overlay = blessed.box({
    parent: screen,
    top: 'center',
    left: 'center',
    width: overlayWidth,
    height: overlayHeight,
    border: { type: 'line' },
    style: {
      border: { fg: 'blue' },
      bg: 'black',
    },
    tags: true,
    keys: true,
  })

  let query = ''
  let cursor = 0

  const getResults = () => {
    if (!query) return [] as Array<Skill | DiscoverSkill>
    const normalized = query.toLowerCase()

    if (mode === 'skills') {
      return getFilteredSkills().filter(skill =>
        skill.name.toLowerCase().includes(normalized) ||
        skill.displayName.toLowerCase().includes(normalized) ||
        skill.description.toLowerCase().includes(normalized)
      )
    }

    return getFilteredDiscoverEntries().filter(entry =>
      entry.name.toLowerCase().includes(normalized) ||
      entry.skillId.toLowerCase().includes(normalized) ||
      entry.source.toLowerCase().includes(normalized) ||
      (entry.summary?.toLowerCase().includes(normalized) ?? false)
    )
  }

  const renderOverlay = () => {
    const results = getResults()
    cursor = Math.max(0, Math.min(cursor, Math.max(0, results.length - 1)))
    const maxLineWidth = Math.max(12, overlayWidth - 6)
    const visibleResultCount = Math.max(4, overlayHeight - 8)
    const visibleStart = Math.max(0, Math.min(
      cursor - Math.floor(visibleResultCount / 2),
      Math.max(0, results.length - visibleResultCount),
    ))
    const visibleResults = results.slice(visibleStart, visibleStart + visibleResultCount)
    const lines: string[] = [
      `{bold}${mode === 'skills' ? 'Search Skills' : 'Search skills.sh'}{/bold}`,
      '{gray-fg}j/k or ↑/↓: move   Enter: select   Esc: cancel{/gray-fg}',
      '',
      `{blue-fg}> {/blue-fg}${escapeTags(query)}{blue-fg}_{/blue-fg}`,
      '',
    ]

    if (!query) {
      lines.push('{gray-fg}Type to search current view{/gray-fg}')
    } else if (results.length === 0) {
      lines.push('{gray-fg}No results{/gray-fg}')
    } else {
      if (visibleStart > 0) {
        lines.push('{gray-fg}↑ more{/gray-fg}')
      }

      visibleResults.forEach((result, idx) => {
        const actualIndex = visibleStart + idx
        const isSelected = actualIndex === cursor
        const prefix = isSelected ? '▶ ' : '  '
        const plainLabel = mode === 'skills'
          ? (() => {
              const skill = result as Skill
              const markers = `${skill.isStarred ? ' ★' : ''}${skill.isInstalled ? ' ●' : ''}`
              return `${prefix}${skill.displayName}${markers} — ${skill.description}`
            })()
          : (() => {
              const entry = result as DiscoverSkill
              return `${prefix}${entry.name} — ${entry.source} · ${entry.installs}`
            })()

        const label = escapeTags(truncateToListWidth(plainLabel, maxLineWidth))
        lines.push(isSelected ? `{blue-bg}{white-fg}${label}{/white-fg}{/blue-bg}` : label)
      })

      if (visibleStart + visibleResults.length < results.length) {
        lines.push('{gray-fg}↓ more{/gray-fg}')
      }
    }

    overlay.setContent(lines.join('\n'))
    screen.render()
  }

  const closeOverlay = () => {
    screen.grabKeys = false
    overlay.destroy()
    render()
  }

  overlay.on('keypress', (ch, key) => {
    const results = getResults()

    if (key.name === 'escape') {
      closeOverlay()
      return
    }

    if (key.name === 'enter') {
      const selected = results[cursor]
      if (!selected) return

      if (mode === 'skills') {
        const filteredSkills = getFilteredSkills()
        const index = filteredSkills.findIndex(skill => skill.name === (selected as Skill).name)
        if (index !== -1) selectedIndex = index
      } else {
        const filteredEntries = getFilteredDiscoverEntries()
        const index = filteredEntries.findIndex(entry => entry.id === (selected as DiscoverSkill).id)
        if (index !== -1) selectedIndex = index
      }

      closeOverlay()
      return
    }

    if (key.name === 'down' || ch === 'j') {
      if (cursor < results.length - 1) {
        cursor++
        renderOverlay()
      }
      return
    }

    if (key.name === 'up' || ch === 'k') {
      if (cursor > 0) {
        cursor--
        renderOverlay()
      }
      return
    }

    if (key.name === 'backspace' || key.name === 'delete') {
      query = query.slice(0, -1)
      cursor = 0
      renderOverlay()
      return
    }

    if (ch && !key.ctrl && !key.meta) {
      query += ch
      cursor = 0
      renderOverlay()
    }
  })

  screen.grabKeys = true
  renderOverlay()
  overlay.focus()
  screen.render()
}

function showVersionHistoryOverlay(skill: Skill) {
  const screenWidth = typeof screen.width === 'number' ? screen.width : 100
  const screenHeight = typeof screen.height === 'number' ? screen.height : 30
  const overlayWidth = Math.max(60, Math.min(screenWidth - 4, 110))
  const overlayHeight = Math.max(12, Math.min(screenHeight - 2, 24))
  const overlay = blessed.box({
    parent: screen,
    top: 'center',
    left: 'center',
    width: overlayWidth,
    height: overlayHeight,
    border: { type: 'line' },
    style: {
      border: { fg: 'blue' },
      bg: 'black',
    },
    tags: true,
    keys: true,
  })

  let commits: Commit[] = []
  let cursor = 0
  let diff = ''
  let loading = true
  let overlayStatus = ''
  let closed = false
  let diffRequestId = 0

  const renderOverlay = () => {
    cursor = Math.max(0, Math.min(cursor, Math.max(0, commits.length - 1)))
    const maxLineWidth = Math.max(20, overlayWidth - 6)
    const lines: string[] = [
      `{bold}Version History: ${escapeTags(skill.name)}{/bold}`,
      '{gray-fg}j/k: move   r: rollback   Esc: close{/gray-fg}',
      '',
    ]

    if (loading) {
      lines.push('{gray-fg}Loading history...{/gray-fg}')
    } else if (commits.length === 0) {
      lines.push('{gray-fg}No version history (not tracked by git){/gray-fg}')
    } else {
      const visibleCommitCount = Math.max(4, Math.min(8, overlayHeight - 10))
      const start = Math.max(0, Math.min(cursor - Math.floor(visibleCommitCount / 2), Math.max(0, commits.length - visibleCommitCount)))
      const visibleCommits = commits.slice(start, start + visibleCommitCount)

      visibleCommits.forEach((commit, idx) => {
        const actualIndex = start + idx
        const prefix = actualIndex === cursor ? '▶ ' : '  '
        const head = commit.isHead ? ' HEAD' : ''
        const plainLine = `${prefix}${commit.date}  ${commit.message}${head}`
        const line = escapeTags(truncateToListWidth(plainLine, maxLineWidth))
        lines.push(actualIndex === cursor ? `{blue-bg}{white-fg}${line}{/white-fg}{/blue-bg}` : line)
      })
    }

    if (diff) {
      lines.push('')
      lines.push('{gray-fg}── Diff ──{/gray-fg}')
      diff.split('\n').slice(0, 12).forEach(line => {
        const safeLine = escapeTags(truncateToListWidth(line, maxLineWidth))
        if (line.startsWith('+')) lines.push(`{green-fg}${safeLine}{/green-fg}`)
        else if (line.startsWith('-')) lines.push(`{red-fg}${safeLine}{/red-fg}`)
        else lines.push(safeLine)
      })
    }

    if (overlayStatus) {
      lines.push('')
      lines.push(`{yellow-fg}${escapeTags(overlayStatus)}{/yellow-fg}`)
    }

    overlay.setContent(lines.join('\n'))
    screen.render()
  }

  const closeOverlay = () => {
    if (closed) return
    closed = true
    screen.grabKeys = false
    overlay.destroy()
    render()
  }

  const loadDiffForCursor = () => {
    const commit = commits[cursor]
    if (!commit) {
      diff = ''
      renderOverlay()
      return
    }

    const requestId = ++diffRequestId
    getDiff(skill, commit.hash)
      .then(result => {
        if (closed || requestId !== diffRequestId) return
        diff = result
        renderOverlay()
      })
      .catch(() => {
        if (closed || requestId !== diffRequestId) return
        diff = ''
        renderOverlay()
      })
  }

  overlay.on('keypress', (ch, key) => {
    if (key.name === 'escape' || key.name === 'q') {
      closeOverlay()
      return
    }

    if ((key.name === 'down' || ch === 'j') && cursor < commits.length - 1) {
      cursor++
      renderOverlay()
      loadDiffForCursor()
      return
    }

    if ((key.name === 'up' || ch === 'k') && cursor > 0) {
      cursor--
      renderOverlay()
      loadDiffForCursor()
      return
    }

    if (ch === 'r') {
      const commit = commits[cursor]
      if (!commit) return

      overlayStatus = `Rolling back to ${commit.hash.slice(0, 7)}…`
      renderOverlay()

      rollback(skill, commit.hash)
        .then(() => {
          refreshLocalSkills()
          closeOverlay()
          showSuccessStatus(`Rolled back ${skill.name} to ${commit.hash.slice(0, 7)}`)
        })
        .catch(error => {
          overlayStatus = String(error)
          renderOverlay()
        })
    }
  })

  screen.grabKeys = true
  renderOverlay()
  overlay.focus()
  screen.render()

  getHistory(skill)
    .then(result => {
      if (closed) return
      commits = result
      cursor = 0
      loading = false
      overlayStatus = ''
      renderOverlay()
      loadDiffForCursor()
    })
    .catch(error => {
      if (closed) return
      loading = false
      overlayStatus = String(error)
      renderOverlay()
    })
}

function showSkillDetailOverlay(entry: DiscoverSkill) {
  const screenWidth = typeof screen.width === 'number' ? screen.width : 100
  const screenHeight = typeof screen.height === 'number' ? screen.height : 30
  const overlayWidth = Math.max(60, Math.min(screenWidth - 4, 110))
  const overlayHeight = Math.max(12, Math.min(screenHeight - 2, 26))
  const overlay = blessed.box({
    parent: screen,
    top: 'center',
    left: 'center',
    width: overlayWidth,
    height: overlayHeight,
    border: { type: 'line' },
    style: {
      border: { fg: 'blue' },
      bg: 'black',
    },
    tags: true,
    scrollable: true,
    alwaysScroll: true,
    keys: true,
    vi: true,
  })

  let detailEntry = discoverDetails[entry.id] ?? entry
  let loading = !discoverDetails[entry.id]
  let overlayError = ''
  let closed = false

  const renderOverlay = () => {
    const lines: string[] = [
      `{bold}${escapeTags(detailEntry.name)}{/bold}`,
      '{gray-fg}j/k: scroll   q/esc/enter: close{/gray-fg}',
      escapeTags(detailEntry.source),
      '────────────────────────────────────────',
    ]

    if (loading) {
      lines.push('{gray-fg}Loading details...{/gray-fg}')
    }

    if (overlayError) {
      lines.push(`{red-fg}${escapeTags(overlayError)}{/red-fg}`)
    }

    lines.push(`Installs: ${detailEntry.installs.toLocaleString()}`)
    lines.push(`Repo: ${escapeTags(detailEntry.repoUrl)}`)

    if (detailEntry.summary) {
      lines.push('')
      lines.push('{bold}Summary{/bold}')
      lines.push(escapeTags(detailEntry.summary))
    }

    if (detailEntry.readmeExcerpt) {
      lines.push('')
      lines.push('{bold}SKILL.md excerpt{/bold}')
      lines.push(escapeTags(detailEntry.readmeExcerpt))
    }

    lines.push('')
    lines.push('{bold}Install command{/bold}')
    lines.push(escapeTags(detailEntry.installCommand))

    overlay.setContent(lines.join('\n'))
    screen.render()
  }

  const closeOverlay = () => {
    if (closed) return
    closed = true
    screen.grabKeys = false
    overlay.destroy()
    render()
  }

  overlay.on('keypress', (ch, key) => {
    if (ch === 'q' || key.name === 'escape' || key.name === 'enter') {
      closeOverlay()
    }
  })

  screen.grabKeys = true
  renderOverlay()
  overlay.focus()
  screen.render()

  if (!discoverDetails[entry.id]) {
    fetchDiscoverSkillDetail(entry)
      .then(result => {
        if (closed) return
        discoverDetails[result.id] = result
        detailEntry = result
        loading = false
        renderOverlay()
      })
      .catch(error => {
        if (closed) return
        overlayError = String(error)
        loading = false
        renderOverlay()
      })
  }
}

// Keyboard handling
onGlobalKey(['q', 'C-c'], () => {
  process.exit(0)
})

onGlobalKey(['h'], () => {
  if (activePanel === 'detail') activePanel = 'list'
  else if (activePanel === 'list') activePanel = 'sidebar'
  render()
})

onGlobalKey(['l', 'enter'], () => {
  if (activePanel === 'sidebar') {
    activePanel = 'list'
    render()
    return
  }

  if (activePanel === 'list') {
    activePanel = 'detail'
    render()
  }
})

onGlobalKey(['j', 'down'], () => {
  if (activePanel === 'list') {
    const maxIndex = sidebarSelection === 'library:discover'
      ? getFilteredDiscoverEntries().length - 1
      : getFilteredSkills().length - 1

    if (selectedIndex < maxIndex) {
      selectedIndex++
      list.select(sidebarSelection === 'library:discover' ? selectedIndex + 1 : selectedIndex)
      updateDetail()
      updateStatusBar()
    }
  } else if (activePanel === 'sidebar') {
    const items = getSidebarRows().map(row => row.key)
    const currentIdx = items.indexOf(sidebarSelection)
    if (currentIdx < items.length - 1) {
      sidebarSelection = items[currentIdx + 1] ?? sidebarSelection
      selectedIndex = 0
      render()
    }
  }
})

onGlobalKey(['k', 'up'], () => {
  if (activePanel === 'list') {
    if (selectedIndex > 0) {
      selectedIndex--
      list.select(sidebarSelection === 'library:discover' ? selectedIndex + 1 : selectedIndex)
      updateDetail()
      updateStatusBar()
    }
  } else if (activePanel === 'sidebar') {
    const items = getSidebarRows().map(row => row.key)
    const currentIdx = items.indexOf(sidebarSelection)
    if (currentIdx > 0) {
      sidebarSelection = items[currentIdx - 1] ?? sidebarSelection
      selectedIndex = 0
      render()
    }
  }
})

onGlobalKey(['g'], () => {
  if (activePanel === 'list') {
    list.select(sidebarSelection === 'library:discover' ? 1 : 0)
    selectedIndex = 0
    updateDetail()
    updateStatusBar()
  }
})

onGlobalKey(['G'], () => {
  if (activePanel === 'list') {
    const maxIndex = sidebarSelection === 'library:discover'
      ? getFilteredDiscoverEntries().length - 1
      : getFilteredSkills().length - 1
    list.select(sidebarSelection === 'library:discover' ? Math.max(1, maxIndex + 1) : Math.max(0, maxIndex))
    selectedIndex = Math.max(0, maxIndex)
    updateDetail()
    updateStatusBar()
  }
})

// Operations
onGlobalKey(['i'], () => {
  installSelectedItem()
})

onGlobalKey(['x'], () => {
  uninstallSelectedItem()
})

onGlobalKey(['s'], () => {
  if (activePanel !== 'list' && activePanel !== 'detail') return
  if (sidebarSelection === 'library:discover') return

  const skill = getSelectedSkill()
  if (!skill) return

  toggleStar(skill.name)
  refreshLocalSkills()
  render()
})

onGlobalKey(['H'], () => {
  if (activePanel !== 'list' && activePanel !== 'detail') return
  if (sidebarSelection === 'library:discover') return

  const skill = getSelectedSkill()
  if (!skill) return
  showVersionHistoryOverlay(skill)
})

onGlobalKey(['d'], () => {
  if (activePanel !== 'list' && activePanel !== 'detail') return
  if (sidebarSelection !== 'library:discover') return

  const entry = getSelectedDiscoverEntry()
  if (!entry) return
  showSkillDetailOverlay(entry)
})

onGlobalKey(['o'], () => {
  openSelectedSourceFile()
})

onGlobalKey(['O'], () => {
  if (activePanel !== 'list' && activePanel !== 'detail') return
  if (sidebarSelection !== 'library:discover') {
    showSuccessStatus('Source page is only available in Discover view')
    return
  }

  const entry = getSelectedDiscoverEntry()
  if (!entry) return
  openDiscoverSourcePage(entry)
})

onGlobalKey(['r'], () => {
  if (activePanel !== 'list' && activePanel !== 'detail') return
  if (sidebarSelection !== 'library:discover') return

  statusMessage = 'Refreshing...'
  render()

  syncSkillsDirectory()
    .then(result => {
      discoverState = result
      showSuccessStatus('Refreshed skills.sh directory')
    })
    .catch(error => {
      showErrorStatus(error)
    })
})

onGlobalKey(['R'], () => {
  fullRefresh()
})

onGlobalKey(['/'], () => {
  showSearchOverlay()
})

onGlobalKey(['f'], () => {
  if (activePanel !== 'list' && activePanel !== 'detail') return
  if (sidebarSelection !== 'library:discover') return

  discoverSourceFilter = cycleOption(discoverSourceFilter, getDiscoverSources(), 1)
  selectedIndex = 0
  render()
})

onGlobalKey(['F'], () => {
  if (activePanel !== 'list' && activePanel !== 'detail') return
  if (sidebarSelection !== 'library:discover') return

  discoverSourceFilter = cycleOption(discoverSourceFilter, getDiscoverSources(), -1)
  selectedIndex = 0
  render()
})

onGlobalKey(['0'], () => {
  if (activePanel !== 'list' && activePanel !== 'detail') return
  if (sidebarSelection !== 'library:discover') return

  discoverSourceFilter = 'all'
  selectedIndex = 0
  render()
})

screen.on('resize', () => {
  render()
})

// Initial render
render()

syncSkillsDirectory()
  .then(result => {
    discoverState = result
    render()
  })
  .catch(() => {})

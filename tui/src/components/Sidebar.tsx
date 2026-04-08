import React, { useEffect, useMemo, useState } from 'react'
import { Box, Text, useInput } from 'ink'
import type { Skill, AgentDefinition, SidebarSelection } from '../types.js'

interface Props {
  selected: SidebarSelection
  skills: Skill[]
  agents: AgentDefinition[]
  discoverCount: number
  isActive: boolean
  height: number
  onSelect: (selection: SidebarSelection) => void
}

type SidebarRow = {
  kind: 'row'
  key: SidebarSelection
  label: string
  count: number
}

type SidebarHeader = {
  kind: 'header'
  title: string
}

type SidebarItem = SidebarRow | SidebarHeader

export function Sidebar({ selected, skills, agents, discoverCount, isActive, height, onSelect }: Props) {
  const [cursorIdx, setCursorIdx] = useState(0)

  const rows = useMemo<SidebarRow[]>(() => {
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
    const sourceCounts = new Map<string, number>()
    for (const skill of skills) {
      if (skill.pluginSource) sourceCounts.set(skill.pluginSource, (sourceCounts.get(skill.pluginSource) ?? 0) + 1)
    }
    const sourceOptions = Array.from(sourceCounts.entries())
      .map(([id, count]) => ({ id, label: id, count }))
      .sort((a, b) => a.label.localeCompare(b.label))

    return [
      { kind: 'row', key: 'library:discover', label: 'Discover', count: discoverCount },
      { kind: 'row', key: 'library:all', label: 'All', count: skills.length },
      { kind: 'row', key: 'library:installed', label: 'Installed', count: skills.filter(s => s.isInstalled).length },
      { kind: 'row', key: 'library:starred', label: 'Starred', count: skills.filter(s => s.isStarred).length },
      ...sortedAgents.map(agent => ({
        kind: 'row' as const,
        key: `agent:${agent.id}` as SidebarSelection,
        label: agent.label,
        count: skills.filter(skill => skill.compatibleAgents.includes(agent.id)).length,
      })),
      { kind: 'row', key: 'source:local', label: 'Local', count: localCount },
      ...sourceOptions.map(source => ({
        kind: 'row' as const,
        key: `source:${source.id}` as SidebarSelection,
        label: source.label,
        count: source.count,
      })),
    ]
  }, [skills, agents, discoverCount])

  const items = useMemo<SidebarItem[]>(() => {
    const libraryRows = rows.filter(row => row.key.startsWith('library:'))
    const agentRows = rows.filter(row => row.key.startsWith('agent:'))
    const sourceRows = rows.filter(row => row.key.startsWith('source:'))

    const result: SidebarItem[] = []
    if (libraryRows.length > 0) result.push({ kind: 'header', title: 'Library' }, ...libraryRows)
    if (agentRows.length > 0) result.push({ kind: 'header', title: 'Agents' }, ...agentRows)
    if (sourceRows.length > 0) result.push({ kind: 'header', title: 'Sources' }, ...sourceRows)
    return result
  }, [rows])

  useEffect(() => {
    const idx = rows.findIndex(row => row.key === selected)
    if (idx !== -1) setCursorIdx(idx)
  }, [selected, rows])

  useInput((input, key) => {
    if (!isActive) return
    if ((key.downArrow || input === 'j') && cursorIdx < rows.length - 1) {
      const next = cursorIdx + 1
      setCursorIdx(next)
      onSelect(rows[next]!.key)
      return
    }
    if ((key.upArrow || input === 'k') && cursorIdx > 0) {
      const prev = cursorIdx - 1
      setCursorIdx(prev)
      onSelect(rows[prev]!.key)
    }
  })

  const lineBudget = Math.max(4, height - 2)
  const rowToItemIndex = rows.map(row => items.findIndex(item => item.kind === 'row' && item.key === row.key))
  const selectedItemIndex = rowToItemIndex[cursorIdx] ?? 0
  const visibleStart = Math.max(0, Math.min(
    selectedItemIndex - Math.floor(lineBudget / 2),
    Math.max(0, items.length - lineBudget),
  ))
  const visibleItems = items.slice(visibleStart, visibleStart + lineBudget)
  const showTopMore = visibleStart > 0
  const showBottomMore = visibleStart + lineBudget < items.length

  return (
    <Box flexDirection="column" width={22} borderStyle="round" borderColor={isActive ? 'blue' : undefined} paddingX={1}>
      {showTopMore && <Text dimColor>↑ more</Text>}
      {!showTopMore && <Text dimColor> </Text>}
      {visibleItems.map(item => item.kind === 'header'
        ? <Text key={`h:${item.title}`} bold>{item.title}</Text>
        : <Row key={item.key} label={item.label} count={item.count} active={item.key === selected} />,
      )}
      {showBottomMore && <Text dimColor>↓ more</Text>}
    </Box>
  )
}

function Row({ label, count, active }: { label: string; count: number; active: boolean }) {
  const countText = String(count)
  const maxLabelWidth = 16 - countText.length
  const text = label.length > maxLabelWidth ? `${label.slice(0, Math.max(0, maxLabelWidth - 1))}…` : label
  return (
    <Box>
      <Text color={active ? 'blue' : undefined}>{active ? '● ' : '○ '}{text.padEnd(Math.max(1, maxLabelWidth), ' ')}</Text>
      <Text dimColor>{countText}</Text>
    </Box>
  )
}

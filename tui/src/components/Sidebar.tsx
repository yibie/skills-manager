import React, { useState, useEffect } from 'react'
import { Box, Text, useInput } from 'ink'
import type { Skill, FilterState, AgentFilter, AgentDefinition } from '../types.js'

interface Props {
  filterState: FilterState
  agentFilter: AgentFilter
  skills: Skill[]
  agents: AgentDefinition[]
  isActive: boolean
  onFilterChange: (f: FilterState) => void
  onAgentChange: (a: AgentFilter) => void
}

const FILTER_OPTIONS: { key: FilterState; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'installed', label: 'Installed' },
  { key: 'starred', label: 'Starred' },
]

export function Sidebar({ filterState, agentFilter, skills, agents, isActive, onFilterChange, onAgentChange }: Props) {
  const [cursorIdx, setCursorIdx] = useState(0)

  const allCount = skills.length
  const installedCount = skills.filter(s => s.isInstalled).length
  const starredCount = skills.filter(s => s.isStarred).length
  const counts: Record<FilterState, number> = { all: allCount, installed: installedCount, starred: starredCount }

  // Count skills per agent
  const agentCounts = new Map<string, number>()
  agentCounts.set('all', allCount)
  for (const agent of agents) {
    const count = skills.filter(s => s.compatibleAgents.includes(agent.id)).length
    agentCounts.set(agent.id, count)
  }

  const borderColor = isActive ? 'blue' : undefined

  // Build agent options dynamically from installed agents
  const agentOptions: { key: AgentFilter; label: string; count: number }[] = [
    { key: 'all', label: 'All Agents', count: agentCounts.get('all') || 0 },
    ...agents.map(a => ({ key: a.id, label: a.label, count: agentCounts.get(a.id) || 0 })),
  ]

  // All selectable rows: 3 filter + N agent
  const allRows: Array<{ type: 'filter'; key: FilterState } | { type: 'agent'; key: AgentFilter }> = [
    ...FILTER_OPTIONS.map(f => ({ type: 'filter' as const, key: f.key })),
    ...agentOptions.map(a => ({ type: 'agent' as const, key: a.key })),
  ]

  // Sync cursor with current filter/agent state when they change externally
  useEffect(() => {
    const idx = allRows.findIndex(r =>
      (r.type === 'filter' && r.key === filterState) ||
      (r.type === 'agent' && r.key === agentFilter)
    )
    if (idx !== -1) setCursorIdx(idx)
  }, [filterState, agentFilter])

  useInput((input, key) => {
    if (!isActive) return
    if (key.downArrow || input === 'j') {
      const next = Math.min(cursorIdx + 1, allRows.length - 1)
      setCursorIdx(next)
      const row = allRows[next]
      if (row) {
        if (row.type === 'filter') onFilterChange(row.key)
        else onAgentChange(row.key)
      }
    }
    if (key.upArrow || input === 'k') {
      const prev = Math.max(cursorIdx - 1, 0)
      setCursorIdx(prev)
      const row = allRows[prev]
      if (row) {
        if (row.type === 'filter') onFilterChange(row.key)
        else onAgentChange(row.key)
      }
    }
  })

  return (
    <Box
      flexDirection="column"
      width={20}
      borderStyle="round"
      borderColor={borderColor}
      paddingX={1}
    >
      <Text bold>Filter</Text>
      <Box flexDirection="column" marginTop={1}>
        {FILTER_OPTIONS.map(f => (
          <FilterRow
            key={f.key}
            label={f.label}
            count={counts[f.key]}
            active={filterState === f.key}
          />
        ))}
      </Box>
      <Box flexDirection="column" marginTop={1}>
        <Text bold>Agents</Text>
        {agentOptions.map(a => (
          <FilterRow key={a.key} label={a.label} count={a.count} active={agentFilter === a.key} />
        ))}
      </Box>
    </Box>
  )
}

function FilterRow({ label, count, active }: { label: string; count?: number; active: boolean }) {
  return (
    <Box>
      <Text color={active ? 'blue' : undefined}>{active ? '●' : '○'} </Text>
      <Text color={active ? 'blue' : undefined}>{label}</Text>
      {count !== undefined && <Text dimColor> {count}</Text>}
    </Box>
  )
}

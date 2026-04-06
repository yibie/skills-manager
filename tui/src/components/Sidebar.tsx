import React from 'react'
import { Box, Text, useInput } from 'ink'
import type { Skill, FilterState, AgentFilter } from '../types.js'

interface Props {
  filterState: FilterState
  agentFilter: AgentFilter
  skills: Skill[]
  isActive: boolean
  onFilterChange: (f: FilterState) => void
  onAgentChange: (a: AgentFilter) => void
}

const FILTER_OPTIONS: { key: FilterState; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'installed', label: 'Installed' },
  { key: 'starred', label: 'Starred' },
]

const AGENT_OPTIONS: { key: AgentFilter; label: string }[] = [
  { key: 'all', label: 'All Agents' },
  { key: 'claude-code', label: 'Claude Code' },
  { key: 'copilot-cli', label: 'Copilot CLI' },
  { key: 'codex', label: 'Codex' },
]

export function Sidebar({ filterState, agentFilter, skills, isActive, onFilterChange, onAgentChange }: Props) {
  const allCount = skills.length
  const installedCount = skills.filter(s => s.isInstalled).length
  const starredCount = skills.filter(s => s.isStarred).length
  const counts: Record<FilterState, number> = { all: allCount, installed: installedCount, starred: starredCount }

  const borderColor = isActive ? 'blue' : undefined

  // All selectable rows: 3 filter + 4 agent = 7
  const allRows: Array<{ type: 'filter'; key: FilterState } | { type: 'agent'; key: AgentFilter }> = [
    ...FILTER_OPTIONS.map(f => ({ type: 'filter' as const, key: f.key })),
    ...AGENT_OPTIONS.map(a => ({ type: 'agent' as const, key: a.key })),
  ]

  const currentRowIdx = allRows.findIndex(r =>
    (r.type === 'filter' && r.key === filterState) ||
    (r.type === 'agent' && r.key === agentFilter)
  )

  useInput((input, key) => {
    if (!isActive) return
    if (key.downArrow || input === 'j') {
      const next = Math.min(currentRowIdx + 1, allRows.length - 1)
      const row = allRows[next]
      if (row) {
        if (row.type === 'filter') onFilterChange(row.key)
        else onAgentChange(row.key)
      }
    }
    if (key.upArrow || input === 'k') {
      const prev = Math.max(currentRowIdx - 1, 0)
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
      width={18}
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
        <Text dimColor>── Agents ──</Text>
        {AGENT_OPTIONS.map(a => (
          <FilterRow key={a.key} label={a.label} active={agentFilter === a.key} />
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

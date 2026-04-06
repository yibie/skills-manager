import React from 'react'
import { Box, Text } from 'ink'
import type { Skill, FilterState, AgentFilter } from '../types.js'

interface Props {
  filterState: FilterState
  agentFilter: AgentFilter
  skills: Skill[]
  isActive: boolean
  onFilterChange: (f: FilterState) => void
  onAgentChange: (a: AgentFilter) => void
}

const AGENTS: { key: AgentFilter; label: string }[] = [
  { key: 'all', label: 'All Agents' },
  { key: 'claude-code', label: 'Claude Code' },
  { key: 'copilot-cli', label: 'Copilot CLI' },
  { key: 'codex', label: 'Codex' },
]

export function Sidebar({ filterState, agentFilter, skills, isActive }: Props) {
  const allCount = skills.length
  const installedCount = skills.filter(s => s.isInstalled).length
  const starredCount = skills.filter(s => s.isStarred).length

  const borderColor = isActive ? 'blue' : undefined

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
        <FilterRow label="All" count={allCount} active={filterState === 'all'} />
        <FilterRow label="Installed" count={installedCount} active={filterState === 'installed'} />
        <FilterRow label="Starred" count={starredCount} active={filterState === 'starred'} />
      </Box>
      <Box flexDirection="column" marginTop={1}>
        <Text dimColor>── Agents ──</Text>
        {AGENTS.slice(1).map(a => (
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

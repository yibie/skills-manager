import React, { memo } from 'react'
import { Box, Text } from 'ink'
import type { DiscoverSkill } from '../types.js'

interface Props {
  entries: DiscoverSkill[]
  selectedIndex: number
  isActive: boolean
  height: number
  sourceLabel: string
  totalCount: number
}

export const DiscoverList = memo(function DiscoverList({ entries, selectedIndex, isActive, height, sourceLabel, totalCount }: Props) {
  const borderColor = isActive ? 'blue' : undefined
  const visibleRows = Math.max(1, height - 5)
  const scrollStart = Math.max(0, Math.min(
    selectedIndex - Math.floor(visibleRows / 2),
    Math.max(0, entries.length - visibleRows),
  ))
  const visibleEntries = entries.slice(scrollStart, scrollStart + visibleRows)

  return (
    <Box flexDirection="column" flexGrow={1} borderStyle="round" borderColor={borderColor} paddingX={1}>
      <Box>
        <Text bold>Discover </Text>
        <Text dimColor>{entries.length > 0 ? `${selectedIndex + 1}/${entries.length}` : '0'}</Text>
      </Box>
      <Text dimColor>skills.sh · top {entries.length} / {totalCount || entries.length} · src: {sourceLabel}</Text>
      <Box flexDirection="column" marginTop={1}>
        {entries.length === 0 && <Text dimColor>No skills found in directory</Text>}
        {visibleEntries.map((entry, relIdx) => (
          <Box key={entry.id}>
            <Text backgroundColor={scrollStart + relIdx === selectedIndex ? 'blue' : undefined} wrap="truncate-end">
              {scrollStart + relIdx === selectedIndex ? '▶ ' : '  '}{entry.name}
            </Text>
            <Text dimColor>  {entry.installs}</Text>
          </Box>
        ))}
      </Box>
    </Box>
  )
})

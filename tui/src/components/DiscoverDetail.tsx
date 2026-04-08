import React, { memo } from 'react'
import { Box, Text } from 'ink'
import type { DiscoverSkill } from '../types.js'

interface Props {
  entry: DiscoverSkill | undefined
  isActive: boolean
  sourceLabel: string
  height?: number
}

export const DiscoverDetail = memo(function DiscoverDetail({ entry, isActive, sourceLabel, height }: Props) {
  const borderColor = isActive ? 'blue' : undefined

  if (!entry) {
    return (
      <Box flexDirection="column" width={50} height={height} borderStyle="round" borderColor={borderColor} paddingX={1}>
        <Text dimColor>Select a skill</Text>
        <Text dimColor>src: {sourceLabel}</Text>
      </Box>
    )
  }

  return (
    <Box flexDirection="column" width={50} height={height} borderStyle="round" borderColor={borderColor} paddingX={1}>
      <Text bold>{entry.name}</Text>
      <Text dimColor>{entry.source}</Text>
      <Text dimColor>────────────────────────────────────</Text>
      <Text dimColor>Installs: {entry.installs.toLocaleString()}</Text>
      <Text dimColor wrap="truncate-end">Repo: {entry.repoUrl}</Text>

      {entry.summary && (
        <Box flexDirection="column" marginTop={1}>
          <Text dimColor>Summary</Text>
          <Text wrap="wrap">{entry.summary}</Text>
        </Box>
      )}

      {entry.readmeExcerpt && (
        <Box flexDirection="column" marginTop={1}>
          <Text dimColor>SKILL.md excerpt</Text>
          <Text wrap="wrap">{entry.readmeExcerpt.slice(0, 900)}</Text>
        </Box>
      )}

      <Box flexDirection="column" marginTop={1}>
        <Text dimColor>Install command</Text>
        <Text wrap="wrap">{entry.installCommand}</Text>
      </Box>
    </Box>
  )
}, (prevProps, nextProps) => {
  // CRITICAL: Only re-render if these specific props change
  // This prevents re-renders when parent state changes
  if (prevProps.entry?.id !== nextProps.entry?.id) return false
  if (prevProps.isActive !== nextProps.isActive) return false
  if (prevProps.sourceLabel !== nextProps.sourceLabel) return false
  if (prevProps.height !== nextProps.height) return false

  // If entry exists and summary/readmeExcerpt changed, re-render
  if (prevProps.entry && nextProps.entry) {
    if (prevProps.entry.summary !== nextProps.entry.summary) return false
    if (prevProps.entry.readmeExcerpt !== nextProps.entry.readmeExcerpt) return false
  }

  return true // Skip re-render
})

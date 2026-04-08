import React, { useEffect, useRef } from 'react'
import { Box, Text } from 'ink'
import type { DiscoverSkill } from '../types.js'

interface Props {
  entry: DiscoverSkill | undefined
  isActive: boolean
  sourceLabel: string
  height?: number
}

let renderCount = 0

export function DiscoverDetailDebug({ entry, isActive, sourceLabel, height }: Props) {
  const renderCountRef = useRef(0)
  renderCountRef.current++
  renderCount++

  useEffect(() => {
    console.error(`[DiscoverDetail] Mounted/Updated - Component renders: ${renderCountRef.current}, Global renders: ${renderCount}, Entry ID: ${entry?.id}`)
  })

  const borderColor = isActive ? 'blue' : undefined

  if (!entry) {
    return (
      <Box flexDirection="column" width={50} height={height} borderStyle="round" borderColor={borderColor} paddingX={1}>
        <Text dimColor>Select a skill</Text>
        <Text dimColor>src: {sourceLabel}</Text>
        <Text dimColor>Renders: {renderCountRef.current}</Text>
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
      <Text color="yellow">Component renders: {renderCountRef.current}</Text>

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
        <Text dimColor>Install</Text>
        <Text wrap="wrap">{entry.installCommand}</Text>
        <Text dimColor>Skills Manager lets you choose agents</Text>
      </Box>

      <Box flexDirection="column" marginTop={1}>
        <Text dimColor>[i] install/uninstall  [d] details</Text>
        <Text dimColor>[o] open in browser  [r] refresh</Text>
        <Text dimColor>[f/F] cycle source  [0] reset</Text>
      </Box>
    </Box>
  )
}

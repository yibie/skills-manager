import React from 'react'
import { Box, Text } from 'ink'
import type { Skill } from '../types.js'

interface Props {
  skill: Skill | undefined
  isActive: boolean
  height?: number
}

export function DetailPanel({ skill, isActive, height }: Props) {
  const borderColor = isActive ? 'blue' : undefined

  if (!skill) {
    return (
      <Box
        flexDirection="column"
        width={50}
        height={height}
        borderStyle="round"
        borderColor={borderColor}
        paddingX={1}
      >
        <Text dimColor>Select a skill</Text>
      </Box>
    )
  }

  return (
    <Box
      flexDirection="column"
      width={50}
      height={height}
      borderStyle="round"
      borderColor={borderColor}
      paddingX={1}
    >
      <Text bold>{skill.displayName}</Text>
      <Text dimColor>────────────────────────────────────</Text>
      <Text wrap="wrap">{skill.description}</Text>

      <Box flexDirection="column" marginTop={1}>
        <Text dimColor>Compatible:</Text>
        {skill.compatibleAgents.map(agent => (
          <Text key={agent} color="green"> ✓ {agent}</Text>
        ))}
      </Box>

      {(skill.version || skill.source === 'plugin') && (
        <Box marginTop={1} flexDirection="column">
          {skill.version && <Text dimColor>v{skill.version}</Text>}
          <Text dimColor>{skill.source}{skill.pluginSource ? ` · ${skill.pluginSource}` : ''}</Text>
        </Box>
      )}

      <Box flexDirection="column" marginTop={1}>
        <Text dimColor>
          [i]{skill.isInstalled ? 'uninstall' : 'install'}{' '}
          [s]{skill.isStarred ? 'unstar' : 'star'}
        </Text>
        <Text dimColor>[H]istory  [l]open</Text>
      </Box>
    </Box>
  )
}

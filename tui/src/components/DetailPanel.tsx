import React from 'react'
import { Box, Text } from 'ink'
import type { Skill } from '../types.js'

interface Props {
  skill: Skill | undefined
  isActive: boolean
}

export function DetailPanel({ skill, isActive }: Props) {
  const borderColor = isActive ? 'blue' : undefined

  if (!skill) {
    return (
      <Box
        flexDirection="column"
        width={30}
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
      width={30}
      borderStyle="round"
      borderColor={borderColor}
      paddingX={1}
    >
      <Text bold>{skill.name}</Text>
      <Text dimColor>────────────────</Text>
      <Text wrap="wrap">{skill.description}</Text>

      <Box flexDirection="column" marginTop={1}>
        <Text dimColor>Compatible:</Text>
        {skill.compatibleAgents.map(agent => (
          <Text key={agent} color="green"> ✓ {agent}</Text>
        ))}
      </Box>

      {skill.version && (
        <Box marginTop={1}>
          <Text dimColor>v{skill.version} · {skill.source}</Text>
        </Box>
      )}

      <Box flexDirection="column" marginTop={1}>
        <Text dimColor>
          [i]{skill.isInstalled ? 'uninstall' : 'install'}{' '}
          [s]{skill.isStarred ? 'unstar' : 'star'}
        </Text>
        <Text dimColor>[h]istory  [o]pen</Text>
      </Box>
    </Box>
  )
}

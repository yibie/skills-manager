import React, { useState } from 'react'
import { Box, Text, useInput } from 'ink'
import type { AgentDefinition } from '../types.js'

interface Props {
  agents: AgentDefinition[]
  onConfirm: (selectedAgents: string[]) => void
  onCancel: () => void
}

export function AgentSelectOverlay({ agents, onConfirm, onCancel }: Props) {
  const [selectedAgents, setSelectedAgents] = useState<Set<string>>(new Set(['claude-code']))
  const [cursorIndex, setCursorIndex] = useState(0)

  const options = [
    { id: 'all', label: 'All agents' },
    ...agents.map(agent => ({ id: agent.id, label: agent.label })),
  ]

  useInput((input, key) => {
    if (input === 'q' || key.escape) {
      onCancel()
      return
    }

    if (key.return) {
      if (selectedAgents.has('all')) {
        onConfirm(agents.map(a => a.id))
      } else {
        onConfirm(Array.from(selectedAgents))
      }
      return
    }

    if ((input === 'j' || key.downArrow) && cursorIndex < options.length - 1) {
      setCursorIndex(cursorIndex + 1)
      return
    }

    if ((input === 'k' || key.upArrow) && cursorIndex > 0) {
      setCursorIndex(cursorIndex - 1)
      return
    }

    if (input === ' ') {
      const option = options[cursorIndex]
      if (!option) return

      setSelectedAgents(prev => {
        const next = new Set(prev)
        if (option.id === 'all') {
          if (next.has('all')) {
            next.clear()
            next.add('claude-code')
          } else {
            next.clear()
            next.add('all')
          }
        } else {
          next.delete('all')
          if (next.has(option.id)) {
            next.delete(option.id)
            if (next.size === 0) next.add('claude-code')
          } else {
            next.add(option.id)
          }
        }
        return next
      })
    }
  })

  return (
    <Box flexDirection="column" padding={1} borderStyle="round" borderColor="blue">
      <Text bold>Select agents to install to:</Text>
      <Text dimColor>Use [space] to toggle, [enter] to confirm, [q] to cancel</Text>
      <Box flexDirection="column" marginTop={1}>
        {options.map((option, idx) => {
          const isSelected = selectedAgents.has(option.id) || (selectedAgents.has('all') && option.id !== 'all')
          const isCursor = idx === cursorIndex
          return (
            <Box key={option.id}>
              <Text backgroundColor={isCursor ? 'blue' : undefined}>
                {isCursor ? '▶ ' : '  '}
                {isSelected ? '[✓] ' : '[ ] '}
                {option.label}
              </Text>
            </Box>
          )
        })}
      </Box>
    </Box>
  )
}

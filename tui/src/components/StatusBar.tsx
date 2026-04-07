import React from 'react'
import { Box, Text } from 'ink'
import type { Panel, Overlay } from '../types.js'

interface Props {
  activePanel: Panel
  overlay: Overlay
  /** Error/status message — shown instead of keybinding hints when set */
  message?: string
}

export function StatusBar({ activePanel, overlay, message }: Props) {
  // Error message takes priority
  if (message) {
    return (
      <Box borderStyle="single" borderTop borderBottom={false} borderLeft={false} borderRight={false}>
        <Text color="red">{message}</Text>
      </Box>
    )
  }

  if (overlay === 'search') {
    return (
      <Box borderStyle="single" borderTop borderBottom={false} borderLeft={false} borderRight={false}>
        <Text dimColor>j/k: move   Enter: select   Esc: cancel</Text>
      </Box>
    )
  }
  if (overlay === 'history') {
    return (
      <Box borderStyle="single" borderTop borderBottom={false} borderLeft={false} borderRight={false}>
        <Text dimColor>j/k: move   r: rollback   Esc: close</Text>
      </Box>
    )
  }

  return (
    <Box borderStyle="single" borderTop borderBottom={false} borderLeft={false} borderRight={false}>
      <Text dimColor>h/l: panels  j/k: move  g/G: first/last  /: search  q: quit</Text>
      {activePanel === 'detail' && (
        <Text dimColor>  ·  i: install  s: star  H: history  l: open</Text>
      )}
    </Box>
  )
}

import React from 'react'
import { Box, Text } from 'ink'
import type { Panel, Overlay } from '../types.js'

interface Props {
  activePanel: Panel
  overlay: Overlay
}

export function StatusBar({ activePanel, overlay }: Props) {
  if (overlay === 'search') {
    return (
      <Box borderStyle="single" borderTop borderBottom={false} borderLeft={false} borderRight={false}>
        <Text dimColor>Enter: select   Esc: cancel</Text>
      </Box>
    )
  }
  if (overlay === 'history') {
    return (
      <Box borderStyle="single" borderTop borderBottom={false} borderLeft={false} borderRight={false}>
        <Text dimColor>↑/↓: navigate   r: rollback   Esc: close</Text>
      </Box>
    )
  }
  return (
    <Box borderStyle="single" borderTop borderBottom={false} borderLeft={false} borderRight={false}>
      <Text dimColor>Tab: switch panel   /: search   q: quit   </Text>
      {activePanel === 'detail' && <Text dimColor>i: install/uninstall   s: star   h: history   o: open in editor</Text>}
    </Box>
  )
}

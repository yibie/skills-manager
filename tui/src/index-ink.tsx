#!/usr/bin/env node
import React from 'react'
import { render } from 'ink'
import { App } from './app.js'

// Enter alternate screen buffer (like vim/lazygit) — isolates from terminal history
process.stdout.write('\x1B[?1049h')
process.stdout.write('\x1B[2J\x1B[H') // clear screen, move cursor to top

const { unmount, waitUntilExit } = render(<App />, { patchConsole: false })

async function cleanup() {
  unmount()
  // Restore original screen buffer
  process.stdout.write('\x1B[?1049l')
}

process.on('SIGINT', () => { cleanup().then(() => process.exit(0)) })
process.on('SIGTERM', () => { cleanup().then(() => process.exit(0)) })

waitUntilExit().then(cleanup).catch(cleanup)

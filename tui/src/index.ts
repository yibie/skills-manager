#!/usr/bin/env node

// Suppress blessed terminal capability warnings
process.env.BLESSED_FORCE_MODES = 'true'

// Blessed cannot currently compile some ghostty-specific terminfo capabilities
// (for example Setulc). Normalize to xterm-256color before startup.
if ((process.env.TERM || '').includes('ghostty')) {
  process.env.TERM = 'xterm-256color'
}

import './app-blessed.js'

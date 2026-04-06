import React, { useState, useEffect } from 'react'
import { Box, Text, useInput } from 'ink'
import { getHistory, getDiff, rollback } from '../services/GitService.js'
import type { Skill, Commit } from '../types.js'

interface Props {
  skill: Skill
  onClose: () => void
}

export function VersionHistoryOverlay({ skill, onClose }: Props) {
  const [commits, setCommits] = useState<Commit[]>([])
  const [cursor, setCursor] = useState(0)
  const [diff, setDiff] = useState('')
  const [status, setStatus] = useState('')

  useEffect(() => {
    getHistory(skill.name).then(setCommits)
  }, [skill.name])

  useEffect(() => {
    if (commits[cursor]) {
      getDiff(skill.name, commits[cursor].hash).then(setDiff)
    }
  }, [cursor, commits, skill.name])

  useInput((input, key) => {
    if (key.escape) { onClose(); return }
    if ((key.downArrow || input === 'j') && cursor < commits.length - 1) {
      setCursor(c => c + 1)
      return
    }
    if ((key.upArrow || input === 'k') && cursor > 0) {
      setCursor(c => c - 1)
      return
    }
    if (input === 'r' && commits[cursor]) {
      setStatus('Rolling back…')
      rollback(skill.name, commits[cursor].hash)
        .then(() => { setStatus('Rolled back successfully'); setTimeout(onClose, 1000) })
        .catch(e => setStatus(`Error: ${String(e)}`))
    }
  })

  const diffLines = diff.split('\n').slice(0, 12)

  return (
    <Box
      flexDirection="column"
      flexGrow={1}
      borderStyle="round"
      borderColor="blue"
      paddingX={1}
    >
      <Text bold>Version History: {skill.name}</Text>

      {commits.length === 0 && (
        <Text dimColor>No version history (not tracked by git)</Text>
      )}

      <Box flexDirection="column" marginTop={1}>
        {commits.map((commit, idx) => (
          <Box key={commit.hash}>
            <Text backgroundColor={idx === cursor ? 'blue' : undefined}>
              {idx === cursor ? '▶ ' : '  '}
              {commit.date}  {commit.message.slice(0, 40)}
            </Text>
            {commit.isHead && <Text color="green"> HEAD</Text>}
          </Box>
        ))}
      </Box>

      {diff && (
        <Box flexDirection="column" marginTop={1}>
          <Text dimColor>── Diff ──</Text>
          {diffLines.map((line, i) => {
            const color = line.startsWith('+') ? 'green' : line.startsWith('-') ? 'red' : undefined
            return <Text key={i} color={color}>{line}</Text>
          })}
        </Box>
      )}

      {status && <Text color="yellow">{status}</Text>}
    </Box>
  )
}

import React, { useEffect, useState } from 'react'
import { Box, Text, useInput } from 'ink'
import type { DiscoverSkill } from '../types.js'
import { fetchDiscoverSkillDetail } from '../services/SkillsDirectoryService.js'

interface Props {
  entry: DiscoverSkill
  onClose: () => void
}

export function SkillDetailOverlay({ entry, onClose }: Props) {
  const [detail, setDetail] = useState<DiscoverSkill>(entry)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setLoading(true)
    setError(null)
    fetchDiscoverSkillDetail(entry)
      .then(result => {
        setDetail(result)
        setLoading(false)
      })
      .catch(err => {
        setError(String(err))
        setLoading(false)
      })
  }, [entry.id])

  useInput((input, key) => {
    if (input === 'q' || key.escape || key.return) {
      onClose()
    }
  })

  return (
    <Box flexDirection="column" padding={1} borderStyle="round" borderColor="blue">
      <Box justifyContent="space-between">
        <Text bold>{detail.name}</Text>
        <Text dimColor>[q/esc/enter] close</Text>
      </Box>
      <Text dimColor>{detail.source}</Text>
      <Text dimColor>─────────────────────────────────────────────────</Text>

      {loading && <Text dimColor>Loading details...</Text>}
      {error && <Text color="red">Error: {error}</Text>}

      {!loading && !error && (
        <Box flexDirection="column" marginTop={1}>
          <Text dimColor>Installs: {detail.installs.toLocaleString()}</Text>
          <Text dimColor wrap="wrap">Repo: {detail.repoUrl}</Text>

          {detail.summary && (
            <Box flexDirection="column" marginTop={1}>
              <Text bold>Summary</Text>
              <Text wrap="wrap">{detail.summary}</Text>
            </Box>
          )}

          {detail.readmeExcerpt && (
            <Box flexDirection="column" marginTop={1}>
              <Text bold>SKILL.md excerpt</Text>
              <Text wrap="wrap">{detail.readmeExcerpt}</Text>
            </Box>
          )}

          <Box flexDirection="column" marginTop={1}>
            <Text bold>Install command</Text>
            <Text wrap="wrap">{detail.installCommand}</Text>
          </Box>
        </Box>
      )}
    </Box>
  )
}

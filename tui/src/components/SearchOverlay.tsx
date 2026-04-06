import React, { useState, useRef, useEffect } from 'react'
import { Box, Text, useInput } from 'ink'
import type { Skill } from '../types.js'

interface Props {
  skills: Skill[]
  onSelect: (skill: Skill) => void
  onClose: () => void
}

export function SearchOverlay({ skills, onSelect, onClose }: Props) {
  const [query, setQuery] = useState('')
  const [cursor, setCursor] = useState(0)

  const results = query.length === 0 ? [] : skills.filter(s =>
    s.name.toLowerCase().includes(query.toLowerCase()) ||
    s.description.toLowerCase().includes(query.toLowerCase())
  ).slice(0, 8)

  // Refs so useInput always reads current values (avoids stale closure)
  const resultsRef = useRef(results)
  const cursorRef = useRef(cursor)
  useEffect(() => { resultsRef.current = results }, [results])
  useEffect(() => { cursorRef.current = cursor }, [cursor])

  useInput((input, key) => {
    if (key.escape) { onClose(); return }
    if (key.return) {
      const selected = resultsRef.current[cursorRef.current]
      if (selected) onSelect(selected)
      return
    }
    if (key.downArrow && cursorRef.current < resultsRef.current.length - 1) {
      setCursor(c => c + 1)
      return
    }
    if (key.upArrow && cursorRef.current > 0) {
      setCursor(c => c - 1)
      return
    }
    if (key.backspace || key.delete) {
      setQuery(q => q.slice(0, -1))
      setCursor(0)
      return
    }
    if (input && !key.ctrl && !key.meta) {
      setQuery(q => q + input)
      setCursor(0)
    }
  })

  return (
    <Box
      flexDirection="column"
      flexGrow={1}
      borderStyle="round"
      borderColor="blue"
      paddingX={1}
    >
      <Text bold>Search</Text>
      <Box marginTop={1}>
        <Text color="blue">{'> '}</Text>
        <Text>{query}<Text color="blue">_</Text></Text>
      </Box>
      <Box flexDirection="column" marginTop={1}>
        {results.length === 0 && query.length > 0 && (
          <Text dimColor>No results</Text>
        )}
        {results.map((skill, idx) => (
          <Box key={skill.name}>
            <Text backgroundColor={idx === cursor ? 'blue' : undefined}>
              {idx === cursor ? '▶ ' : '  '}{skill.name}
            </Text>
            {skill.isStarred && <Text color="yellow"> ★</Text>}
            {skill.isInstalled && <Text color="green"> ●</Text>}
            <Text dimColor>   {skill.description.slice(0, 32)}</Text>
          </Box>
        ))}
      </Box>
    </Box>
  )
}

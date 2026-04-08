import React, { useState, useRef, useEffect } from 'react'
import { Box, Text, useInput } from 'ink'
import type { Skill, DiscoverSkill } from '../types.js'

type SkillProps = {
  mode: 'skills'
  skills: Skill[]
  onSelectSkill: (skill: Skill) => void
  onClose: () => void
}

type DiscoverProps = {
  mode: 'discover'
  entries: DiscoverSkill[]
  onSelectEntry: (entry: DiscoverSkill) => void
  onClose: () => void
}

type Props = SkillProps | DiscoverProps

export function SearchOverlay(props: Props) {
  const [query, setQuery] = useState('')
  const [cursor, setCursor] = useState(0)

  const skillResults = props.mode === 'skills' && query.length > 0
    ? props.skills.filter(s =>
      s.name.toLowerCase().includes(query.toLowerCase()) ||
      s.description.toLowerCase().includes(query.toLowerCase()) ||
      s.displayName.toLowerCase().includes(query.toLowerCase())
    ).slice(0, 8)
    : []

  const discoverResults = props.mode === 'discover' && query.length > 0
    ? props.entries.filter(entry =>
      entry.name.toLowerCase().includes(query.toLowerCase()) ||
      entry.skillId.toLowerCase().includes(query.toLowerCase()) ||
      entry.source.toLowerCase().includes(query.toLowerCase()) ||
      (entry.summary?.toLowerCase().includes(query.toLowerCase()) ?? false)
    ).slice(0, 8)
    : []

  const skillResultsRef = useRef(skillResults)
  const discoverResultsRef = useRef(discoverResults)
  const cursorRef = useRef(cursor)
  useEffect(() => { skillResultsRef.current = skillResults }, [skillResults])
  useEffect(() => { discoverResultsRef.current = discoverResults }, [discoverResults])
  useEffect(() => { cursorRef.current = cursor }, [cursor])

  const resultLength = props.mode === 'skills' ? skillResults.length : discoverResults.length

  useInput((input, key) => {
    if (key.escape) { props.onClose(); return }
    if (key.return) {
      if (props.mode === 'skills') {
        const selected = skillResultsRef.current[cursorRef.current]
        if (selected) props.onSelectSkill(selected)
      } else {
        const selected = discoverResultsRef.current[cursorRef.current]
        if (selected) props.onSelectEntry(selected)
      }
      return
    }
    if ((key.downArrow || input === 'j') && cursorRef.current < resultLength - 1) {
      setCursor(c => c + 1)
      return
    }
    if ((key.upArrow || input === 'k') && cursorRef.current > 0) {
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
    <Box flexDirection="column" flexGrow={1} borderStyle="round" borderColor="blue" paddingX={1}>
      <Text bold>{props.mode === 'skills' ? 'Search Skills' : 'Search skills.sh'}</Text>
      <Box marginTop={1}>
        <Text color="blue">{'>'} </Text>
        <Text>{query}<Text color="blue">_</Text></Text>
      </Box>
      <Box flexDirection="column" marginTop={1}>
        {resultLength === 0 && query.length > 0 && <Text dimColor>No results</Text>}
        {props.mode === 'skills' && skillResults.map((skill, idx) => (
          <Box key={skill.name}>
            <Text backgroundColor={idx === cursor ? 'blue' : undefined}>
              {idx === cursor ? '▶ ' : '  '}{skill.name}
            </Text>
            {skill.isStarred && <Text color="yellow"> ★</Text>}
            {skill.isInstalled && <Text color="green"> ●</Text>}
            <Text dimColor>   {skill.description.slice(0, 32)}</Text>
          </Box>
        ))}
        {props.mode === 'discover' && discoverResults.map((entry, idx) => (
          <Box key={entry.id}>
            <Text backgroundColor={idx === cursor ? 'blue' : undefined}>
              {idx === cursor ? '▶ ' : '  '}{entry.name}
            </Text>
            <Text dimColor>   {entry.source} · {entry.installs}</Text>
          </Box>
        ))}
      </Box>
    </Box>
  )
}

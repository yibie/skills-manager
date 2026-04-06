import React from 'react'
import { Box, Text } from 'ink'
import type { Skill } from '../types.js'

interface Props {
  skills: Skill[]
  selectedIndex: number
  isActive: boolean
  onSelect: (index: number) => void
}

export function SkillList({ skills, selectedIndex, isActive }: Props) {
  const borderColor = isActive ? 'blue' : undefined

  return (
    <Box
      flexDirection="column"
      flexGrow={1}
      borderStyle="round"
      borderColor={borderColor}
      paddingX={1}
    >
      <Text bold>Skills ({skills.length})</Text>
      <Box flexDirection="column" marginTop={1}>
        {skills.length === 0 && <Text dimColor>No skills found</Text>}
        {skills.map((skill, idx) => (
          <SkillRow
            key={skill.name}
            skill={skill}
            isSelected={idx === selectedIndex}
          />
        ))}
      </Box>
    </Box>
  )
}

function SkillRow({ skill, isSelected }: { skill: Skill; isSelected: boolean }) {
  const prefix = isSelected ? '▶ ' : '  '
  const starIcon = skill.isStarred ? <Text color="yellow"> ★</Text> : null
  const installedIcon = skill.isInstalled ? <Text color="green"> ●</Text> : null

  const descPreview = skill.description.slice(0, 28)

  return (
    <Box flexDirection="column">
      <Box>
        <Text backgroundColor={isSelected ? 'blue' : undefined}>
          {prefix}{skill.name}
        </Text>
        {starIcon}
        {installedIcon}
      </Box>
      <Text dimColor>  {descPreview}{skill.description.length > 28 ? '…' : ''}</Text>
    </Box>
  )
}

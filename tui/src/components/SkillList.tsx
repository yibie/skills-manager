import React from 'react'
import { Box, Text } from 'ink'
import type { Skill } from '../types.js'

interface Props {
  skills: Skill[]
  selectedIndex: number
  isActive: boolean
  /** Available content height in terminal rows (from parent, excluding status bar) */
  height: number
}

export function SkillList({ skills, selectedIndex, isActive, height }: Props) {
  const borderColor = isActive ? 'blue' : undefined

  // Subtract structural rows: top border(1) + header(1) + marginTop(1) + bottom border(1) = 4
  const visibleRows = Math.max(1, height - 4)

  // Keep selected item centered in the viewport
  const scrollStart = Math.max(0, Math.min(
    selectedIndex - Math.floor(visibleRows / 2),
    Math.max(0, skills.length - visibleRows)
  ))

  const visibleSkills = skills.slice(scrollStart, scrollStart + visibleRows)

  return (
    <Box
      flexDirection="column"
      flexGrow={1}
      borderStyle="round"
      borderColor={borderColor}
      paddingX={1}
    >
      <Box>
        <Text bold>Skills </Text>
        <Text dimColor>
          {skills.length > 0 ? `${selectedIndex + 1}/${skills.length}` : '0'}
        </Text>
      </Box>
      <Box flexDirection="column" marginTop={1}>
        {skills.length === 0 && <Text dimColor>No skills found</Text>}
        {visibleSkills.map((skill, relIdx) => (
          <SkillRow
            key={skill.name}
            skill={skill}
            isSelected={scrollStart + relIdx === selectedIndex}
          />
        ))}
      </Box>
    </Box>
  )
}

function SkillRow({ skill, isSelected }: { skill: Skill; isSelected: boolean }) {
  return (
    <Box>
      <Text
        backgroundColor={isSelected ? 'blue' : undefined}
        wrap="truncate"
      >
        {isSelected ? '▶ ' : '  '}{skill.displayName}
      </Text>
      {skill.isStarred && <Text color="yellow"> ★</Text>}
      {skill.isInstalled && <Text color="green"> ●</Text>}
    </Box>
  )
}

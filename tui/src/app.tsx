import React, { useState, useEffect } from 'react'
import { Box, useInput, useApp } from 'ink'
import { loadSkills, toggleStar } from './services/SkillStore.js'
import { install, uninstall } from './services/InstallService.js'
import { StatusBar } from './components/StatusBar.js'
import { Sidebar } from './components/Sidebar.js'
import { SkillList } from './components/SkillList.js'
import { DetailPanel } from './components/DetailPanel.js'
import { SearchOverlay } from './components/SearchOverlay.js'
import { VersionHistoryOverlay } from './components/VersionHistoryOverlay.js'
import type { Skill, Panel, Overlay, FilterState, AgentFilter } from './types.js'

export function App() {
  const { exit } = useApp()
  const [skills, setSkills] = useState<Skill[]>([])
  const [activePanel, setActivePanel] = useState<Panel>('list')
  const [overlay, setOverlay] = useState<Overlay>('none')
  const [filterState, setFilterState] = useState<FilterState>('all')
  const [agentFilter, setAgentFilter] = useState<AgentFilter>('all')
  const [selectedIndex, setSelectedIndex] = useState(0)

  useEffect(() => {
    setSkills(loadSkills())
  }, [])

  const filteredSkills = skills.filter(s => {
    if (filterState === 'installed' && !s.isInstalled) return false
    if (filterState === 'starred' && !s.isStarred) return false
    if (agentFilter !== 'all' && !s.compatibleAgents.includes(agentFilter)) return false
    return true
  })

  const selectedSkill: Skill | undefined = filteredSkills[selectedIndex]

  function refresh() {
    setSkills(loadSkills())
  }

  useInput((input, key) => {
    if (overlay !== 'none') return  // overlays handle their own input

    if (input === 'q') { exit(); return }
    if (input === '/') { setOverlay('search'); return }

    if (key.tab) {
      setActivePanel(p => p === 'sidebar' ? 'list' : p === 'list' ? 'detail' : 'sidebar')
      return
    }

    if (activePanel === 'list') {
      if ((input === 'j' || key.downArrow) && selectedIndex < filteredSkills.length - 1) {
        setSelectedIndex(i => i + 1)
      }
      if ((input === 'k' || key.upArrow) && selectedIndex > 0) {
        setSelectedIndex(i => i - 1)
      }
    }

    if (activePanel === 'detail' && selectedSkill) {
      if (input === 's') {
        toggleStar(selectedSkill.name)
        refresh()
      }
      if (input === 'i') {
        if (selectedSkill.isInstalled) {
          uninstall(selectedSkill).then(refresh)
        } else {
          install(selectedSkill).then(refresh)
        }
      }
      if (input === 'h') {
        setOverlay('history')
      }
      if (input === 'o' && selectedSkill.filePath) {
        import('node:child_process').then(({ execFile }) => {
          execFile('open', [selectedSkill.filePath])
        })
      }
    }
  })

  if (overlay === 'search') {
    return (
      <Box flexDirection="column" height="100%">
        <SearchOverlay
          skills={skills}
          onSelect={(skill: Skill) => {
            const idx = filteredSkills.findIndex(s => s.name === skill.name)
            if (idx !== -1) setSelectedIndex(idx)
            setOverlay('none')
          }}
          onClose={() => setOverlay('none')}
        />
        <StatusBar activePanel={activePanel} overlay={overlay} />
      </Box>
    )
  }

  if (overlay === 'history' && selectedSkill) {
    return (
      <Box flexDirection="column" height="100%">
        <VersionHistoryOverlay
          skill={selectedSkill}
          onClose={() => { setOverlay('none'); refresh() }}
        />
        <StatusBar activePanel={activePanel} overlay={overlay} />
      </Box>
    )
  }

  return (
    <Box flexDirection="column" height="100%">
      <Box flexGrow={1}>
        <Sidebar
          filterState={filterState}
          agentFilter={agentFilter}
          skills={skills}
          isActive={activePanel === 'sidebar'}
          onFilterChange={setFilterState}
          onAgentChange={setAgentFilter}
        />
        <SkillList
          skills={filteredSkills}
          selectedIndex={selectedIndex}
          isActive={activePanel === 'list'}
          onSelect={setSelectedIndex}
        />
        <DetailPanel
          skill={selectedSkill}
          isActive={activePanel === 'detail'}
        />
      </Box>
      <StatusBar activePanel={activePanel} overlay={overlay} />
    </Box>
  )
}

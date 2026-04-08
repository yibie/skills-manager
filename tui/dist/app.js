import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useMemo, useState } from 'react';
import { Box, useApp, useInput } from 'ink';
import { loadSkills, toggleStar, getInstalledAgents } from './services/SkillStore.js';
import { install, uninstall } from './services/InstallService.js';
import { loadSkillsDirectory, syncSkillsDirectory } from './services/SkillsDirectoryService.js';
import { installDiscoverSkill, uninstallDiscoverSkill } from './services/DiscoverInstallService.js';
import { StatusBar } from './components/StatusBar.js';
import { Sidebar } from './components/Sidebar.js';
import { SkillList } from './components/SkillList.js';
import { DetailPanel } from './components/DetailPanel.js';
import { SearchOverlay } from './components/SearchOverlay.js';
import { VersionHistoryOverlay } from './components/VersionHistoryOverlay.js';
import { DiscoverList } from './components/DiscoverList.js';
import { DiscoverDetail } from './components/DiscoverDetail.js';
import { AgentSelectOverlay } from './components/AgentSelectOverlay.js';
import { SkillDetailOverlay } from './components/SkillDetailOverlay.js';
function applySidebarSelection(skills, selection) {
    if (selection === 'library:discover')
        return [];
    if (selection === 'library:installed')
        return skills.filter(skill => skill.isInstalled);
    if (selection === 'library:starred')
        return skills.filter(skill => skill.isStarred);
    if (selection.startsWith('agent:')) {
        const agentId = selection.slice('agent:'.length);
        return skills.filter(skill => skill.compatibleAgents.includes(agentId));
    }
    if (selection.startsWith('source:')) {
        const sourceId = selection.slice('source:'.length);
        if (sourceId === 'local')
            return skills.filter(skill => skill.source === 'local');
        return skills.filter(skill => skill.pluginSource === sourceId);
    }
    return skills;
}
function cycleOption(current, options, step) {
    if (options.length === 0)
        return current;
    const index = Math.max(0, options.indexOf(current));
    return options[(index + step + options.length) % options.length] ?? options[0] ?? current;
}
function isDiscoverSkillInstalled(entry, skills) {
    return skills.find(skill => skill.name === entry.skillId || skill.name === entry.name);
}
export function App() {
    const { exit } = useApp();
    const [skills, setSkills] = useState(() => loadSkills());
    const [agents, setAgents] = useState(() => getInstalledAgents());
    const [discoverState, setDiscoverState] = useState(() => loadSkillsDirectory());
    const [activePanel, setActivePanel] = useState('list');
    const [overlay, setOverlay] = useState('none');
    const [sidebarSelection, setSidebarSelection] = useState('library:all');
    const [selectedIndex, setSelectedIndex] = useState(0);
    const [discoverSourceFilter, setDiscoverSourceFilter] = useState('all');
    const [statusMessage, setStatusMessage] = useState('');
    const [terminalRows, setTerminalRows] = useState(() => process.stdout.rows || 24);
    function refreshLocalSkills() {
        const nextSkills = loadSkills();
        const nextAgents = getInstalledAgents();
        setSkills(nextSkills);
        setAgents(nextAgents);
        return { nextSkills, nextAgents };
    }
    function refreshDiscover() {
        const next = loadSkillsDirectory();
        setDiscoverState(next);
        return next;
    }
    useEffect(() => {
        syncSkillsDirectory()
            .then(result => setDiscoverState(result))
            .catch(() => { });
    }, []);
    useEffect(() => {
        const onResize = () => setTerminalRows(process.stdout.rows || 24);
        process.stdout.on('resize', onResize);
        return () => { process.stdout.off('resize', onResize); };
    }, []);
    const filteredSkills = applySidebarSelection(skills, sidebarSelection);
    const discoverSources = useMemo(() => ['all', ...Array.from(new Set(discoverState.entries.map(entry => entry.source))).sort((a, b) => a.localeCompare(b))], [discoverState.entries]);
    const filteredDiscoverEntries = sidebarSelection === 'library:discover'
        ? discoverState.entries.filter(entry => discoverSourceFilter === 'all' || entry.source === discoverSourceFilter)
        : [];
    const selectedSkill = filteredSkills[selectedIndex];
    const selectedDiscoverEntryBase = filteredDiscoverEntries[selectedIndex];
    const selectedInstalledSkill = selectedDiscoverEntryBase ? isDiscoverSkillInstalled(selectedDiscoverEntryBase, skills) : undefined;
    const discoverSourceLabel = discoverSourceFilter === 'all' ? 'All sources' : discoverSourceFilter;
    useEffect(() => {
        setSelectedIndex(0);
    }, [sidebarSelection, discoverSourceFilter]);
    useEffect(() => {
        const currentLength = sidebarSelection === 'library:discover' ? filteredDiscoverEntries.length : filteredSkills.length;
        if (currentLength === 0) {
            setSelectedIndex(0);
        }
        else if (selectedIndex >= currentLength) {
            setSelectedIndex(currentLength - 1);
        }
    }, [filteredSkills.length, filteredDiscoverEntries.length, selectedIndex, sidebarSelection]);
    // DISABLED: Async loading causes flickering in Ink
    // Pre-fetch details for visible entries to reduce flickering
    // useEffect(() => {
    //   if (sidebarSelection !== 'library:discover') return
    //
    //   // Pre-fetch details for current and nearby entries
    //   const startIdx = Math.max(0, selectedIndex - 2)
    //   const endIdx = Math.min(filteredDiscoverEntries.length, selectedIndex + 3)
    //
    //   for (let i = startIdx; i < endIdx; i++) {
    //     const entry = filteredDiscoverEntries[i]
    //     if (!entry || discoverDetails[entry.id]?.summary) continue
    //
    //     fetchDiscoverSkillDetail(entry)
    //       .then(detail => {
    //         setDiscoverDetails(current => ({ ...current, [detail.id]: detail }))
    //       })
    //       .catch(() => {/* silent */})
    // }, [sidebarSelection, selectedIndex, filteredDiscoverEntries])
    // Only show base data (no async loading to avoid flickering)
    const selectedDiscoverEntry = selectedDiscoverEntryBase;
    useInput((input, key) => {
        if (overlay !== 'none')
            return;
        if (input === 'q') {
            exit();
            return;
        }
        if (input === '/') {
            setOverlay('search');
            return;
        }
        if (input === 'h') {
            setActivePanel(panel => panel === 'detail' ? 'list' : panel === 'list' ? 'sidebar' : 'sidebar');
            return;
        }
        if (input === 'l' || key.return) {
            if (activePanel === 'sidebar') {
                setActivePanel('list');
            }
            else if (activePanel === 'list') {
                setActivePanel('detail');
            }
            else if (activePanel === 'detail' && sidebarSelection !== 'library:discover' && selectedSkill?.filePath) {
                import('node:child_process').then(({ execFile }) => {
                    const editor = process.env['EDITOR'];
                    if (editor)
                        execFile(editor, [selectedSkill.filePath]);
                    else
                        execFile('open', [selectedSkill.filePath]);
                });
            }
            return;
        }
        if (sidebarSelection === 'library:discover' && (activePanel === 'list' || activePanel === 'detail')) {
            if (input === 'f') {
                setDiscoverSourceFilter(current => cycleOption(current, discoverSources, 1));
                return;
            }
            if (input === 'F') {
                setDiscoverSourceFilter(current => cycleOption(current, discoverSources, -1));
                return;
            }
            if (input === '0') {
                setDiscoverSourceFilter('all');
                return;
            }
        }
        if (activePanel === 'list') {
            const maxIndex = sidebarSelection === 'library:discover' ? filteredDiscoverEntries.length - 1 : filteredSkills.length - 1;
            if ((input === 'j' || key.downArrow) && selectedIndex < maxIndex) {
                setSelectedIndex(index => index + 1);
            }
            if ((input === 'k' || key.upArrow) && selectedIndex > 0) {
                setSelectedIndex(index => index - 1);
            }
            if (input === 'g')
                setSelectedIndex(0);
            if (input === 'G')
                setSelectedIndex(Math.max(0, maxIndex));
            // Allow operations in list panel for discover mode
            if (sidebarSelection === 'library:discover' && selectedDiscoverEntryBase) {
                if (input === 'i') {
                    if (selectedInstalledSkill) {
                        uninstallDiscoverSkill(selectedDiscoverEntryBase, selectedInstalledSkill)
                            .then(() => {
                            refreshLocalSkills();
                            setStatusMessage(`Uninstalled skill: ${selectedDiscoverEntryBase.skillId}`);
                        })
                            .catch(err => setStatusMessage(String(err)));
                    }
                    else {
                        setOverlay('agent-select');
                    }
                }
                if (input === 'd') {
                    setOverlay('skill-detail');
                }
                if (input === 'o') {
                    const url = `https://skills.sh/${selectedDiscoverEntryBase.source}/${selectedDiscoverEntryBase.skillId}`;
                    import('node:child_process').then(({ exec }) => {
                        exec(`open "${url}"`);
                    });
                    setStatusMessage(`Opening ${url}`);
                }
                if (input === 'r') {
                    syncSkillsDirectory()
                        .then(result => {
                        setDiscoverState(result);
                        setStatusMessage('Refreshed skills.sh directory');
                    })
                        .catch(err => setStatusMessage(String(err)));
                }
            }
            // Allow operations in list panel for skill mode
            if (sidebarSelection !== 'library:discover' && selectedSkill) {
                if (input === 's') {
                    toggleStar(selectedSkill.name);
                    refreshLocalSkills();
                }
                if (input === 'i') {
                    const action = selectedSkill.isInstalled ? uninstall(selectedSkill) : install(selectedSkill);
                    action.then(() => { refreshLocalSkills(); }).catch(err => setStatusMessage(String(err)));
                }
                if (input === 'H')
                    setOverlay('history');
            }
        }
        if (activePanel === 'detail') {
            if (sidebarSelection === 'library:discover' && selectedDiscoverEntryBase) {
                if (input === 'i') {
                    if (selectedInstalledSkill) {
                        uninstallDiscoverSkill(selectedDiscoverEntryBase, selectedInstalledSkill)
                            .then(() => {
                            refreshLocalSkills();
                            setStatusMessage(`Uninstalled skill: ${selectedDiscoverEntryBase.skillId}`);
                        })
                            .catch(err => setStatusMessage(String(err)));
                    }
                    else {
                        // Open agent selection overlay
                        setOverlay('agent-select');
                    }
                }
                if (input === 'd') {
                    // Open detail overlay with full information
                    setOverlay('skill-detail');
                }
                if (input === 'o') {
                    // Open in browser
                    const url = `https://skills.sh/${selectedDiscoverEntryBase.source}/${selectedDiscoverEntryBase.skillId}`;
                    import('node:child_process').then(({ exec }) => {
                        exec(`open "${url}"`);
                    });
                    setStatusMessage(`Opening ${url}`);
                }
                if (input === 'r') {
                    syncSkillsDirectory()
                        .then(result => {
                        setDiscoverState(result);
                        setStatusMessage('Refreshed skills.sh directory');
                    })
                        .catch(err => setStatusMessage(String(err)));
                }
            }
            else if (selectedSkill) {
                if (input === 's') {
                    toggleStar(selectedSkill.name);
                    refreshLocalSkills();
                }
                if (input === 'i') {
                    const action = selectedSkill.isInstalled ? uninstall(selectedSkill) : install(selectedSkill);
                    action.then(() => { refreshLocalSkills(); }).catch(err => setStatusMessage(String(err)));
                }
                if (input === 'H')
                    setOverlay('history');
            }
        }
    });
    const contentHeight = Math.max(4, terminalRows - 2);
    if (overlay === 'search') {
        return (_jsxs(Box, { flexDirection: "column", height: terminalRows, children: [sidebarSelection === 'library:discover'
                    ? _jsx(SearchOverlay, { mode: "discover", entries: filteredDiscoverEntries, onSelectEntry: entry => {
                            const idx = filteredDiscoverEntries.findIndex(item => item.id === entry.id);
                            if (idx !== -1)
                                setSelectedIndex(idx);
                            setOverlay('none');
                        }, onClose: () => setOverlay('none') })
                    : _jsx(SearchOverlay, { mode: "skills", skills: filteredSkills, onSelectSkill: skill => {
                            const idx = filteredSkills.findIndex(item => item.name === skill.name);
                            if (idx !== -1)
                                setSelectedIndex(idx);
                            setOverlay('none');
                        }, onClose: () => setOverlay('none') }), _jsx(StatusBar, { activePanel: activePanel, overlay: overlay, detailMode: sidebarSelection === 'library:discover' ? 'discover' : 'skill', message: statusMessage })] }));
    }
    if (overlay === 'history' && selectedSkill) {
        return (_jsxs(Box, { flexDirection: "column", height: terminalRows, children: [_jsx(VersionHistoryOverlay, { skill: selectedSkill, onClose: () => { setOverlay('none'); refreshLocalSkills(); } }), _jsx(StatusBar, { activePanel: activePanel, overlay: overlay, detailMode: sidebarSelection === 'library:discover' ? 'discover' : 'skill', message: statusMessage })] }));
    }
    if (overlay === 'agent-select' && selectedDiscoverEntryBase) {
        return (_jsxs(Box, { flexDirection: "column", height: terminalRows, children: [_jsx(AgentSelectOverlay, { agents: agents, onConfirm: selectedAgents => {
                        setOverlay('none');
                        installDiscoverSkill(selectedDiscoverEntryBase, selectedAgents)
                            .then(() => {
                            const { nextSkills } = refreshLocalSkills();
                            const targetIndex = Math.max(0, nextSkills.findIndex(skill => skill.name === selectedDiscoverEntryBase.skillId || skill.name === selectedDiscoverEntryBase.name));
                            setSidebarSelection('library:all');
                            setActivePanel('list');
                            setSelectedIndex(targetIndex === -1 ? 0 : targetIndex);
                            setStatusMessage(`Installed ${selectedDiscoverEntryBase.skillId} to ${selectedAgents.length} agent(s)`);
                        })
                            .catch(err => setStatusMessage(String(err)));
                    }, onCancel: () => setOverlay('none') }), _jsx(StatusBar, { activePanel: activePanel, overlay: overlay, detailMode: sidebarSelection === 'library:discover' ? 'discover' : 'skill', message: statusMessage })] }));
    }
    if (overlay === 'skill-detail' && selectedDiscoverEntryBase) {
        return (_jsxs(Box, { flexDirection: "column", height: terminalRows, children: [_jsx(SkillDetailOverlay, { entry: selectedDiscoverEntryBase, onClose: () => setOverlay('none') }), _jsx(StatusBar, { activePanel: activePanel, overlay: overlay, detailMode: sidebarSelection === 'library:discover' ? 'discover' : 'skill', message: statusMessage })] }));
    }
    return (_jsxs(Box, { flexDirection: "column", height: terminalRows, children: [_jsxs(Box, { flexGrow: 1, children: [_jsx(Sidebar, { selected: sidebarSelection, skills: skills, agents: agents, discoverCount: discoverState.total, isActive: activePanel === 'sidebar', height: contentHeight, onSelect: selection => {
                            setSidebarSelection(selection);
                            setStatusMessage('');
                        } }), sidebarSelection === 'library:discover'
                        ? _jsx(DiscoverList, { entries: filteredDiscoverEntries, selectedIndex: selectedIndex, isActive: activePanel === 'list', height: contentHeight, sourceLabel: discoverSourceLabel, totalCount: discoverState.total })
                        : _jsx(SkillList, { skills: filteredSkills, selectedIndex: selectedIndex, isActive: activePanel === 'list', height: contentHeight }), sidebarSelection === 'library:discover'
                        ? _jsx(DiscoverDetail, { entry: selectedDiscoverEntry, isActive: activePanel === 'detail', sourceLabel: discoverSourceLabel, height: contentHeight })
                        : _jsx(DetailPanel, { skill: selectedSkill, isActive: activePanel === 'detail', height: contentHeight })] }), _jsx(StatusBar, { activePanel: activePanel, overlay: overlay, detailMode: sidebarSelection === 'library:discover' ? 'discover' : 'skill', message: statusMessage })] }));
}

import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState, useEffect } from 'react';
import { Box, useInput, useApp } from 'ink';
import { loadSkills, toggleStar, getInstalledAgents } from './services/SkillStore.js';
import { install, uninstall } from './services/InstallService.js';
import { StatusBar } from './components/StatusBar.js';
import { Sidebar } from './components/Sidebar.js';
import { SkillList } from './components/SkillList.js';
import { DetailPanel } from './components/DetailPanel.js';
import { SearchOverlay } from './components/SearchOverlay.js';
import { VersionHistoryOverlay } from './components/VersionHistoryOverlay.js';
export function App() {
    const { exit } = useApp();
    // Load synchronously so the first render is already full-height
    const [skills, setSkills] = useState(() => loadSkills());
    const [agents, setAgents] = useState(() => getInstalledAgents());
    const [activePanel, setActivePanel] = useState('list');
    const [overlay, setOverlay] = useState('none');
    const [filterState, setFilterState] = useState('all');
    const [agentFilter, setAgentFilter] = useState('all');
    const [selectedIndex, setSelectedIndex] = useState(0);
    const [statusMessage, setStatusMessage] = useState('');
    const [terminalRows, setTerminalRows] = useState(() => process.stdout.rows || 24);
    useEffect(() => {
        import('./services/MarketplaceService.js').then(({ syncMarketplace }) => {
            syncMarketplace().catch(() => { });
        });
    }, []);
    useEffect(() => {
        const onResize = () => setTerminalRows(process.stdout.rows || 24);
        process.stdout.on('resize', onResize);
        return () => { process.stdout.off('resize', onResize); };
    }, []);
    const filteredSkills = skills.filter(s => {
        if (filterState === 'installed' && !s.isInstalled)
            return false;
        if (filterState === 'starred' && !s.isStarred)
            return false;
        if (agentFilter !== 'all' && !s.compatibleAgents.includes(agentFilter))
            return false;
        return true;
    });
    const selectedSkill = filteredSkills[selectedIndex];
    useEffect(() => {
        if (filteredSkills.length === 0) {
            setSelectedIndex(0);
        }
        else if (selectedIndex >= filteredSkills.length) {
            setSelectedIndex(filteredSkills.length - 1);
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [filteredSkills.length]);
    function refresh() {
        setSkills(loadSkills());
        setAgents(getInstalledAgents());
    }
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
        // Panel navigation: h = left, l/Enter = right (yazi-style)
        if (input === 'h') {
            setActivePanel(p => p === 'detail' ? 'list' : p === 'list' ? 'sidebar' : 'sidebar');
            return;
        }
        if (input === 'l' || key.return) {
            if (activePanel === 'sidebar') {
                setActivePanel('list');
            }
            else if (activePanel === 'list') {
                setActivePanel('detail');
            }
            else if (activePanel === 'detail' && selectedSkill?.filePath) {
                // l in detail = open file, like yazi
                import('node:child_process').then(({ execFile }) => {
                    const editor = process.env['EDITOR'];
                    if (editor) {
                        execFile(editor, [selectedSkill.filePath]);
                    }
                    else {
                        execFile('open', [selectedSkill.filePath]);
                    }
                });
            }
            return;
        }
        if (activePanel === 'list') {
            if ((input === 'j' || key.downArrow) && selectedIndex < filteredSkills.length - 1) {
                setSelectedIndex(i => i + 1);
            }
            if ((input === 'k' || key.upArrow) && selectedIndex > 0) {
                setSelectedIndex(i => i - 1);
            }
            if (input === 'g') {
                setSelectedIndex(0);
            }
            if (input === 'G') {
                setSelectedIndex(Math.max(0, filteredSkills.length - 1));
            }
        }
        if (activePanel === 'detail' && selectedSkill) {
            if (input === 's') {
                toggleStar(selectedSkill.name);
                refresh();
            }
            if (input === 'i') {
                if (selectedSkill.isInstalled) {
                    uninstall(selectedSkill).then(refresh).catch(err => setStatusMessage(String(err)));
                }
                else {
                    install(selectedSkill).then(refresh).catch(err => setStatusMessage(String(err)));
                }
            }
            if (input === 'H') {
                setOverlay('history');
            }
        }
    });
    // StatusBar is always exactly 2 rows (top-border + content).
    // statusMessage is routed into StatusBar so the total height never changes.
    const contentHeight = Math.max(4, terminalRows - 2);
    // Use explicit terminalRows (not "100%") so Ink always writes the same number of
    // lines on every render — preventing ghost rows when content height shrinks.
    if (overlay === 'search') {
        return (_jsxs(Box, { flexDirection: "column", height: terminalRows, children: [_jsx(SearchOverlay, { skills: skills, onSelect: (skill) => {
                        const idx = filteredSkills.findIndex(s => s.name === skill.name);
                        if (idx !== -1)
                            setSelectedIndex(idx);
                        setOverlay('none');
                    }, onClose: () => setOverlay('none') }), _jsx(StatusBar, { activePanel: activePanel, overlay: overlay, message: statusMessage })] }));
    }
    if (overlay === 'history' && selectedSkill) {
        return (_jsxs(Box, { flexDirection: "column", height: terminalRows, children: [_jsx(VersionHistoryOverlay, { skill: selectedSkill, onClose: () => { setOverlay('none'); refresh(); } }), _jsx(StatusBar, { activePanel: activePanel, overlay: overlay, message: statusMessage })] }));
    }
    return (_jsxs(Box, { flexDirection: "column", height: terminalRows, children: [_jsxs(Box, { flexGrow: 1, children: [_jsx(Sidebar, { filterState: filterState, agentFilter: agentFilter, skills: skills, agents: agents, isActive: activePanel === 'sidebar', onFilterChange: setFilterState, onAgentChange: setAgentFilter }), _jsx(SkillList, { skills: filteredSkills, selectedIndex: selectedIndex, isActive: activePanel === 'list', height: contentHeight }), _jsx(DetailPanel, { skill: selectedSkill, isActive: activePanel === 'detail', height: contentHeight })] }), _jsx(StatusBar, { activePanel: activePanel, overlay: overlay, message: statusMessage })] }));
}

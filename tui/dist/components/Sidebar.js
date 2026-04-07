import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState, useEffect } from 'react';
import { Box, Text, useInput } from 'ink';
const FILTER_OPTIONS = [
    { key: 'all', label: 'All' },
    { key: 'installed', label: 'Installed' },
    { key: 'starred', label: 'Starred' },
];
export function Sidebar({ filterState, agentFilter, skills, agents, isActive, onFilterChange, onAgentChange }) {
    const [cursorIdx, setCursorIdx] = useState(0);
    const allCount = skills.length;
    const installedCount = skills.filter(s => s.isInstalled).length;
    const starredCount = skills.filter(s => s.isStarred).length;
    const counts = { all: allCount, installed: installedCount, starred: starredCount };
    // Count skills per agent
    const agentCounts = new Map();
    agentCounts.set('all', allCount);
    for (const agent of agents) {
        const count = skills.filter(s => s.compatibleAgents.includes(agent.id)).length;
        agentCounts.set(agent.id, count);
    }
    const borderColor = isActive ? 'blue' : undefined;
    // Build agent options dynamically from installed agents
    const agentOptions = [
        { key: 'all', label: 'All Agents', count: agentCounts.get('all') || 0 },
        ...agents.map(a => ({ key: a.id, label: a.label, count: agentCounts.get(a.id) || 0 })),
    ];
    // All selectable rows: 3 filter + N agent
    const allRows = [
        ...FILTER_OPTIONS.map(f => ({ type: 'filter', key: f.key })),
        ...agentOptions.map(a => ({ type: 'agent', key: a.key })),
    ];
    // Sync cursor with current filter/agent state when they change externally
    useEffect(() => {
        const idx = allRows.findIndex(r => (r.type === 'filter' && r.key === filterState) ||
            (r.type === 'agent' && r.key === agentFilter));
        if (idx !== -1)
            setCursorIdx(idx);
    }, [filterState, agentFilter]);
    useInput((input, key) => {
        if (!isActive)
            return;
        if (key.downArrow || input === 'j') {
            const next = Math.min(cursorIdx + 1, allRows.length - 1);
            setCursorIdx(next);
            const row = allRows[next];
            if (row) {
                if (row.type === 'filter')
                    onFilterChange(row.key);
                else
                    onAgentChange(row.key);
            }
        }
        if (key.upArrow || input === 'k') {
            const prev = Math.max(cursorIdx - 1, 0);
            setCursorIdx(prev);
            const row = allRows[prev];
            if (row) {
                if (row.type === 'filter')
                    onFilterChange(row.key);
                else
                    onAgentChange(row.key);
            }
        }
    });
    return (_jsxs(Box, { flexDirection: "column", width: 20, borderStyle: "round", borderColor: borderColor, paddingX: 1, children: [_jsx(Text, { bold: true, children: "Filter" }), _jsx(Box, { flexDirection: "column", marginTop: 1, children: FILTER_OPTIONS.map(f => (_jsx(FilterRow, { label: f.label, count: counts[f.key], active: filterState === f.key }, f.key))) }), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { bold: true, children: "Agents" }), agentOptions.map(a => (_jsx(FilterRow, { label: a.label, count: a.count, active: agentFilter === a.key }, a.key)))] })] }));
}
function FilterRow({ label, count, active }) {
    return (_jsxs(Box, { children: [_jsxs(Text, { color: active ? 'blue' : undefined, children: [active ? '●' : '○', " "] }), _jsx(Text, { color: active ? 'blue' : undefined, children: label }), count !== undefined && _jsxs(Text, { dimColor: true, children: [" ", count] })] }));
}

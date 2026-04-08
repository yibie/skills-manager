import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useMemo, useState } from 'react';
import { Box, Text, useInput } from 'ink';
export function Sidebar({ selected, skills, agents, discoverCount, isActive, height, onSelect }) {
    const [cursorIdx, setCursorIdx] = useState(0);
    const rows = useMemo(() => {
        const skillAgentMap = new Map();
        for (const skill of skills) {
            for (const agentId of skill.compatibleAgents) {
                if (!skillAgentMap.has(agentId))
                    skillAgentMap.set(agentId, agentId);
            }
        }
        for (const agent of agents)
            skillAgentMap.set(agent.id, agent.label);
        const sortedAgents = Array.from(skillAgentMap.entries())
            .map(([id, fallback]) => ({ id, label: agents.find(agent => agent.id === id)?.label ?? fallback }))
            .sort((a, b) => a.label.localeCompare(b.label));
        const localCount = skills.filter(skill => skill.source === 'local').length;
        const sourceCounts = new Map();
        for (const skill of skills) {
            if (skill.pluginSource)
                sourceCounts.set(skill.pluginSource, (sourceCounts.get(skill.pluginSource) ?? 0) + 1);
        }
        const sourceOptions = Array.from(sourceCounts.entries())
            .map(([id, count]) => ({ id, label: id, count }))
            .sort((a, b) => a.label.localeCompare(b.label));
        return [
            { kind: 'row', key: 'library:discover', label: 'Discover', count: discoverCount },
            { kind: 'row', key: 'library:all', label: 'All', count: skills.length },
            { kind: 'row', key: 'library:installed', label: 'Installed', count: skills.filter(s => s.isInstalled).length },
            { kind: 'row', key: 'library:starred', label: 'Starred', count: skills.filter(s => s.isStarred).length },
            ...sortedAgents.map(agent => ({
                kind: 'row',
                key: `agent:${agent.id}`,
                label: agent.label,
                count: skills.filter(skill => skill.compatibleAgents.includes(agent.id)).length,
            })),
            { kind: 'row', key: 'source:local', label: 'Local', count: localCount },
            ...sourceOptions.map(source => ({
                kind: 'row',
                key: `source:${source.id}`,
                label: source.label,
                count: source.count,
            })),
        ];
    }, [skills, agents, discoverCount]);
    const items = useMemo(() => {
        const libraryRows = rows.filter(row => row.key.startsWith('library:'));
        const agentRows = rows.filter(row => row.key.startsWith('agent:'));
        const sourceRows = rows.filter(row => row.key.startsWith('source:'));
        const result = [];
        if (libraryRows.length > 0)
            result.push({ kind: 'header', title: 'Library' }, ...libraryRows);
        if (agentRows.length > 0)
            result.push({ kind: 'header', title: 'Agents' }, ...agentRows);
        if (sourceRows.length > 0)
            result.push({ kind: 'header', title: 'Sources' }, ...sourceRows);
        return result;
    }, [rows]);
    useEffect(() => {
        const idx = rows.findIndex(row => row.key === selected);
        if (idx !== -1)
            setCursorIdx(idx);
    }, [selected, rows]);
    useInput((input, key) => {
        if (!isActive)
            return;
        if ((key.downArrow || input === 'j') && cursorIdx < rows.length - 1) {
            const next = cursorIdx + 1;
            setCursorIdx(next);
            onSelect(rows[next].key);
            return;
        }
        if ((key.upArrow || input === 'k') && cursorIdx > 0) {
            const prev = cursorIdx - 1;
            setCursorIdx(prev);
            onSelect(rows[prev].key);
        }
    });
    const lineBudget = Math.max(4, height - 2);
    const rowToItemIndex = rows.map(row => items.findIndex(item => item.kind === 'row' && item.key === row.key));
    const selectedItemIndex = rowToItemIndex[cursorIdx] ?? 0;
    const visibleStart = Math.max(0, Math.min(selectedItemIndex - Math.floor(lineBudget / 2), Math.max(0, items.length - lineBudget)));
    const visibleItems = items.slice(visibleStart, visibleStart + lineBudget);
    const showTopMore = visibleStart > 0;
    const showBottomMore = visibleStart + lineBudget < items.length;
    return (_jsxs(Box, { flexDirection: "column", width: 22, borderStyle: "round", borderColor: isActive ? 'blue' : undefined, paddingX: 1, children: [showTopMore && _jsx(Text, { dimColor: true, children: "\u2191 more" }), !showTopMore && _jsx(Text, { dimColor: true, children: " " }), visibleItems.map(item => item.kind === 'header'
                ? _jsx(Text, { bold: true, children: item.title }, `h:${item.title}`)
                : _jsx(Row, { label: item.label, count: item.count, active: item.key === selected }, item.key)), showBottomMore && _jsx(Text, { dimColor: true, children: "\u2193 more" })] }));
}
function Row({ label, count, active }) {
    const countText = String(count);
    const maxLabelWidth = 16 - countText.length;
    const text = label.length > maxLabelWidth ? `${label.slice(0, Math.max(0, maxLabelWidth - 1))}…` : label;
    return (_jsxs(Box, { children: [_jsxs(Text, { color: active ? 'blue' : undefined, children: [active ? '● ' : '○ ', text.padEnd(Math.max(1, maxLabelWidth), ' ')] }), _jsx(Text, { dimColor: true, children: countText })] }));
}

import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { memo } from 'react';
import { Box, Text } from 'ink';
export const DiscoverList = memo(function DiscoverList({ entries, selectedIndex, isActive, height, sourceLabel, totalCount }) {
    const borderColor = isActive ? 'blue' : undefined;
    const visibleRows = Math.max(1, height - 5);
    const scrollStart = Math.max(0, Math.min(selectedIndex - Math.floor(visibleRows / 2), Math.max(0, entries.length - visibleRows)));
    const visibleEntries = entries.slice(scrollStart, scrollStart + visibleRows);
    return (_jsxs(Box, { flexDirection: "column", flexGrow: 1, borderStyle: "round", borderColor: borderColor, paddingX: 1, children: [_jsxs(Box, { children: [_jsx(Text, { bold: true, children: "Discover " }), _jsx(Text, { dimColor: true, children: entries.length > 0 ? `${selectedIndex + 1}/${entries.length}` : '0' })] }), _jsxs(Text, { dimColor: true, children: ["skills.sh \u00B7 top ", entries.length, " / ", totalCount || entries.length, " \u00B7 src: ", sourceLabel] }), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [entries.length === 0 && _jsx(Text, { dimColor: true, children: "No skills found in directory" }), visibleEntries.map((entry, relIdx) => (_jsxs(Box, { children: [_jsxs(Text, { backgroundColor: scrollStart + relIdx === selectedIndex ? 'blue' : undefined, wrap: "truncate-end", children: [scrollStart + relIdx === selectedIndex ? '▶ ' : '  ', entry.name] }), _jsxs(Text, { dimColor: true, children: ["  ", entry.installs] })] }, entry.id)))] })] }));
});

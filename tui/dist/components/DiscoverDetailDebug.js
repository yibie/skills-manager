import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useRef } from 'react';
import { Box, Text } from 'ink';
let renderCount = 0;
export function DiscoverDetailDebug({ entry, isActive, sourceLabel, height }) {
    const renderCountRef = useRef(0);
    renderCountRef.current++;
    renderCount++;
    useEffect(() => {
        console.error(`[DiscoverDetail] Mounted/Updated - Component renders: ${renderCountRef.current}, Global renders: ${renderCount}, Entry ID: ${entry?.id}`);
    });
    const borderColor = isActive ? 'blue' : undefined;
    if (!entry) {
        return (_jsxs(Box, { flexDirection: "column", width: 50, height: height, borderStyle: "round", borderColor: borderColor, paddingX: 1, children: [_jsx(Text, { dimColor: true, children: "Select a skill" }), _jsxs(Text, { dimColor: true, children: ["src: ", sourceLabel] }), _jsxs(Text, { dimColor: true, children: ["Renders: ", renderCountRef.current] })] }));
    }
    return (_jsxs(Box, { flexDirection: "column", width: 50, height: height, borderStyle: "round", borderColor: borderColor, paddingX: 1, children: [_jsx(Text, { bold: true, children: entry.name }), _jsx(Text, { dimColor: true, children: entry.source }), _jsx(Text, { dimColor: true, children: "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" }), _jsxs(Text, { dimColor: true, children: ["Installs: ", entry.installs.toLocaleString()] }), _jsxs(Text, { dimColor: true, wrap: "truncate-end", children: ["Repo: ", entry.repoUrl] }), _jsxs(Text, { color: "yellow", children: ["Component renders: ", renderCountRef.current] }), entry.summary && (_jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { dimColor: true, children: "Summary" }), _jsx(Text, { wrap: "wrap", children: entry.summary })] })), entry.readmeExcerpt && (_jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { dimColor: true, children: "SKILL.md excerpt" }), _jsx(Text, { wrap: "wrap", children: entry.readmeExcerpt.slice(0, 900) })] })), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { dimColor: true, children: "Install" }), _jsx(Text, { wrap: "wrap", children: entry.installCommand }), _jsx(Text, { dimColor: true, children: "Skills Manager lets you choose agents" })] }), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { dimColor: true, children: "[i] install/uninstall  [d] details" }), _jsx(Text, { dimColor: true, children: "[o] open in browser  [r] refresh" }), _jsx(Text, { dimColor: true, children: "[f/F] cycle source  [0] reset" })] })] }));
}

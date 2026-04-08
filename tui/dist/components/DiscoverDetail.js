import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { memo } from 'react';
import { Box, Text } from 'ink';
export const DiscoverDetail = memo(function DiscoverDetail({ entry, isActive, sourceLabel, height }) {
    const borderColor = isActive ? 'blue' : undefined;
    if (!entry) {
        return (_jsxs(Box, { flexDirection: "column", width: 50, height: height, borderStyle: "round", borderColor: borderColor, paddingX: 1, children: [_jsx(Text, { dimColor: true, children: "Select a skill" }), _jsxs(Text, { dimColor: true, children: ["src: ", sourceLabel] })] }));
    }
    return (_jsxs(Box, { flexDirection: "column", width: 50, height: height, borderStyle: "round", borderColor: borderColor, paddingX: 1, children: [_jsx(Text, { bold: true, children: entry.name }), _jsx(Text, { dimColor: true, children: entry.source }), _jsx(Text, { dimColor: true, children: "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" }), _jsxs(Text, { dimColor: true, children: ["Installs: ", entry.installs.toLocaleString()] }), _jsxs(Text, { dimColor: true, wrap: "truncate-end", children: ["Repo: ", entry.repoUrl] }), entry.summary && (_jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { dimColor: true, children: "Summary" }), _jsx(Text, { wrap: "wrap", children: entry.summary })] })), entry.readmeExcerpt && (_jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { dimColor: true, children: "SKILL.md excerpt" }), _jsx(Text, { wrap: "wrap", children: entry.readmeExcerpt.slice(0, 900) })] })), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { dimColor: true, children: "Install command" }), _jsx(Text, { wrap: "wrap", children: entry.installCommand })] })] }));
}, (prevProps, nextProps) => {
    // CRITICAL: Only re-render if these specific props change
    // This prevents re-renders when parent state changes
    if (prevProps.entry?.id !== nextProps.entry?.id)
        return false;
    if (prevProps.isActive !== nextProps.isActive)
        return false;
    if (prevProps.sourceLabel !== nextProps.sourceLabel)
        return false;
    if (prevProps.height !== nextProps.height)
        return false;
    // If entry exists and summary/readmeExcerpt changed, re-render
    if (prevProps.entry && nextProps.entry) {
        if (prevProps.entry.summary !== nextProps.entry.summary)
            return false;
        if (prevProps.entry.readmeExcerpt !== nextProps.entry.readmeExcerpt)
            return false;
    }
    return true; // Skip re-render
});

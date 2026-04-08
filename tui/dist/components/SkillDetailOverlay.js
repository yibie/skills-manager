import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { fetchDiscoverSkillDetail } from '../services/SkillsDirectoryService.js';
export function SkillDetailOverlay({ entry, onClose }) {
    const [detail, setDetail] = useState(entry);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    useEffect(() => {
        setLoading(true);
        setError(null);
        fetchDiscoverSkillDetail(entry)
            .then(result => {
            setDetail(result);
            setLoading(false);
        })
            .catch(err => {
            setError(String(err));
            setLoading(false);
        });
    }, [entry.id]);
    useInput((input, key) => {
        if (input === 'q' || key.escape || key.return) {
            onClose();
        }
    });
    return (_jsxs(Box, { flexDirection: "column", padding: 1, borderStyle: "round", borderColor: "blue", children: [_jsxs(Box, { justifyContent: "space-between", children: [_jsx(Text, { bold: true, children: detail.name }), _jsx(Text, { dimColor: true, children: "[q/esc/enter] close" })] }), _jsx(Text, { dimColor: true, children: detail.source }), _jsx(Text, { dimColor: true, children: "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500" }), loading && _jsx(Text, { dimColor: true, children: "Loading details..." }), error && _jsxs(Text, { color: "red", children: ["Error: ", error] }), !loading && !error && (_jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsxs(Text, { dimColor: true, children: ["Installs: ", detail.installs.toLocaleString()] }), _jsxs(Text, { dimColor: true, wrap: "wrap", children: ["Repo: ", detail.repoUrl] }), detail.summary && (_jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { bold: true, children: "Summary" }), _jsx(Text, { wrap: "wrap", children: detail.summary })] })), detail.readmeExcerpt && (_jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { bold: true, children: "SKILL.md excerpt" }), _jsx(Text, { wrap: "wrap", children: detail.readmeExcerpt })] })), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { bold: true, children: "Install command" }), _jsx(Text, { wrap: "wrap", children: detail.installCommand })] })] }))] }));
}

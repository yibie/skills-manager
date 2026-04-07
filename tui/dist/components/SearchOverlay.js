import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState, useRef, useEffect } from 'react';
import { Box, Text, useInput } from 'ink';
export function SearchOverlay({ skills, onSelect, onClose }) {
    const [query, setQuery] = useState('');
    const [cursor, setCursor] = useState(0);
    const results = query.length === 0 ? [] : skills.filter(s => s.name.toLowerCase().includes(query.toLowerCase()) ||
        s.description.toLowerCase().includes(query.toLowerCase())).slice(0, 8);
    // Refs so useInput always reads current values (avoids stale closure)
    const resultsRef = useRef(results);
    const cursorRef = useRef(cursor);
    useEffect(() => { resultsRef.current = results; }, [results]);
    useEffect(() => { cursorRef.current = cursor; }, [cursor]);
    useInput((input, key) => {
        if (key.escape) {
            onClose();
            return;
        }
        if (key.return) {
            const selected = resultsRef.current[cursorRef.current];
            if (selected)
                onSelect(selected);
            return;
        }
        if (key.downArrow && cursorRef.current < resultsRef.current.length - 1) {
            setCursor(c => c + 1);
            return;
        }
        if (key.upArrow && cursorRef.current > 0) {
            setCursor(c => c - 1);
            return;
        }
        if (key.backspace || key.delete) {
            setQuery(q => q.slice(0, -1));
            setCursor(0);
            return;
        }
        if (input && !key.ctrl && !key.meta) {
            setQuery(q => q + input);
            setCursor(0);
        }
    });
    return (_jsxs(Box, { flexDirection: "column", flexGrow: 1, borderStyle: "round", borderColor: "blue", paddingX: 1, children: [_jsx(Text, { bold: true, children: "Search" }), _jsxs(Box, { marginTop: 1, children: [_jsx(Text, { color: "blue", children: '> ' }), _jsxs(Text, { children: [query, _jsx(Text, { color: "blue", children: "_" })] })] }), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [results.length === 0 && query.length > 0 && (_jsx(Text, { dimColor: true, children: "No results" })), results.map((skill, idx) => (_jsxs(Box, { children: [_jsxs(Text, { backgroundColor: idx === cursor ? 'blue' : undefined, children: [idx === cursor ? '▶ ' : '  ', skill.name] }), skill.isStarred && _jsx(Text, { color: "yellow", children: " \u2605" }), skill.isInstalled && _jsx(Text, { color: "green", children: " \u25CF" }), _jsxs(Text, { dimColor: true, children: ["   ", skill.description.slice(0, 32)] })] }, skill.name)))] })] }));
}

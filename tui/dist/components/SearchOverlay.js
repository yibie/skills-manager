import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState, useRef, useEffect } from 'react';
import { Box, Text, useInput } from 'ink';
export function SearchOverlay(props) {
    const [query, setQuery] = useState('');
    const [cursor, setCursor] = useState(0);
    const skillResults = props.mode === 'skills' && query.length > 0
        ? props.skills.filter(s => s.name.toLowerCase().includes(query.toLowerCase()) ||
            s.description.toLowerCase().includes(query.toLowerCase()) ||
            s.displayName.toLowerCase().includes(query.toLowerCase())).slice(0, 8)
        : [];
    const discoverResults = props.mode === 'discover' && query.length > 0
        ? props.entries.filter(entry => entry.name.toLowerCase().includes(query.toLowerCase()) ||
            entry.skillId.toLowerCase().includes(query.toLowerCase()) ||
            entry.source.toLowerCase().includes(query.toLowerCase()) ||
            (entry.summary?.toLowerCase().includes(query.toLowerCase()) ?? false)).slice(0, 8)
        : [];
    const skillResultsRef = useRef(skillResults);
    const discoverResultsRef = useRef(discoverResults);
    const cursorRef = useRef(cursor);
    useEffect(() => { skillResultsRef.current = skillResults; }, [skillResults]);
    useEffect(() => { discoverResultsRef.current = discoverResults; }, [discoverResults]);
    useEffect(() => { cursorRef.current = cursor; }, [cursor]);
    const resultLength = props.mode === 'skills' ? skillResults.length : discoverResults.length;
    useInput((input, key) => {
        if (key.escape) {
            props.onClose();
            return;
        }
        if (key.return) {
            if (props.mode === 'skills') {
                const selected = skillResultsRef.current[cursorRef.current];
                if (selected)
                    props.onSelectSkill(selected);
            }
            else {
                const selected = discoverResultsRef.current[cursorRef.current];
                if (selected)
                    props.onSelectEntry(selected);
            }
            return;
        }
        if ((key.downArrow || input === 'j') && cursorRef.current < resultLength - 1) {
            setCursor(c => c + 1);
            return;
        }
        if ((key.upArrow || input === 'k') && cursorRef.current > 0) {
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
    return (_jsxs(Box, { flexDirection: "column", flexGrow: 1, borderStyle: "round", borderColor: "blue", paddingX: 1, children: [_jsx(Text, { bold: true, children: props.mode === 'skills' ? 'Search Skills' : 'Search skills.sh' }), _jsxs(Box, { marginTop: 1, children: [_jsxs(Text, { color: "blue", children: ['>', " "] }), _jsxs(Text, { children: [query, _jsx(Text, { color: "blue", children: "_" })] })] }), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [resultLength === 0 && query.length > 0 && _jsx(Text, { dimColor: true, children: "No results" }), props.mode === 'skills' && skillResults.map((skill, idx) => (_jsxs(Box, { children: [_jsxs(Text, { backgroundColor: idx === cursor ? 'blue' : undefined, children: [idx === cursor ? '▶ ' : '  ', skill.name] }), skill.isStarred && _jsx(Text, { color: "yellow", children: " \u2605" }), skill.isInstalled && _jsx(Text, { color: "green", children: " \u25CF" }), _jsxs(Text, { dimColor: true, children: ["   ", skill.description.slice(0, 32)] })] }, skill.name))), props.mode === 'discover' && discoverResults.map((entry, idx) => (_jsxs(Box, { children: [_jsxs(Text, { backgroundColor: idx === cursor ? 'blue' : undefined, children: [idx === cursor ? '▶ ' : '  ', entry.name] }), _jsxs(Text, { dimColor: true, children: ["   ", entry.source, " \u00B7 ", entry.installs] })] }, entry.id)))] })] }));
}

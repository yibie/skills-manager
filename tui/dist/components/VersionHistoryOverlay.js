import { jsxs as _jsxs, jsx as _jsx } from "react/jsx-runtime";
import { useState, useEffect, useRef } from 'react';
import { Box, Text, useInput } from 'ink';
import { getHistory, getDiff, rollback } from '../services/GitService.js';
export function VersionHistoryOverlay({ skill, onClose }) {
    const [commits, setCommits] = useState([]);
    const [cursor, setCursor] = useState(0);
    const [diff, setDiff] = useState('');
    const [status, setStatus] = useState('');
    // Refs so useInput always reads current values (avoids stale closure)
    const commitsRef = useRef(commits);
    const cursorRef = useRef(cursor);
    useEffect(() => { commitsRef.current = commits; }, [commits]);
    useEffect(() => { cursorRef.current = cursor; }, [cursor]);
    useEffect(() => {
        getHistory(skill).then(setCommits);
    }, [skill]);
    useEffect(() => {
        const commit = commitsRef.current[cursorRef.current];
        if (commit) {
            getDiff(skill, commit.hash).then(setDiff);
        }
        else {
            setDiff('');
        }
    }, [cursor, commits, skill]);
    useInput((input, key) => {
        if (key.escape) {
            onClose();
            return;
        }
        if ((key.downArrow || input === 'j') && cursorRef.current < commitsRef.current.length - 1) {
            setCursor(c => c + 1);
            return;
        }
        if ((key.upArrow || input === 'k') && cursorRef.current > 0) {
            setCursor(c => c - 1);
            return;
        }
        if (input === 'r') {
            const commit = commitsRef.current[cursorRef.current];
            if (commit) {
                setStatus('Rolling back…');
                rollback(skill, commit.hash)
                    .then(() => { setStatus('Rolled back successfully'); setTimeout(onClose, 1000); })
                    .catch(e => setStatus(`Error: ${String(e)}`));
            }
        }
    });
    const diffLines = diff.split('\n').slice(0, 12);
    return (_jsxs(Box, { flexDirection: "column", flexGrow: 1, borderStyle: "round", borderColor: "blue", paddingX: 1, children: [_jsxs(Text, { bold: true, children: ["Version History: ", skill.name] }), commits.length === 0 && (_jsx(Text, { dimColor: true, children: "No version history (not tracked by git)" })), _jsx(Box, { flexDirection: "column", marginTop: 1, children: commits.map((commit, idx) => (_jsxs(Box, { children: [_jsxs(Text, { backgroundColor: idx === cursor ? 'blue' : undefined, children: [idx === cursor ? '▶ ' : '  ', commit.date, "  ", commit.message.slice(0, 40)] }), commit.isHead && _jsx(Text, { color: "green", children: " HEAD" })] }, commit.hash))) }), diff && (_jsxs(Box, { flexDirection: "column", marginTop: 1, children: [_jsx(Text, { dimColor: true, children: "\u2500\u2500 Diff \u2500\u2500" }), diffLines.map((line, i) => {
                        const color = line.startsWith('+') ? 'green' : line.startsWith('-') ? 'red' : undefined;
                        return _jsx(Text, { color: color, children: line }, i);
                    })] })), status && _jsx(Text, { color: "yellow", children: status })] }));
}

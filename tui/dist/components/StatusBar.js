import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Box, Text } from 'ink';
export function StatusBar({ activePanel, overlay, message }) {
    // Error message takes priority
    if (message) {
        return (_jsx(Box, { borderStyle: "single", borderTop: true, borderBottom: false, borderLeft: false, borderRight: false, children: _jsx(Text, { color: "red", children: message }) }));
    }
    if (overlay === 'search') {
        return (_jsx(Box, { borderStyle: "single", borderTop: true, borderBottom: false, borderLeft: false, borderRight: false, children: _jsx(Text, { dimColor: true, children: "j/k: move   Enter: select   Esc: cancel" }) }));
    }
    if (overlay === 'history') {
        return (_jsx(Box, { borderStyle: "single", borderTop: true, borderBottom: false, borderLeft: false, borderRight: false, children: _jsx(Text, { dimColor: true, children: "j/k: move   r: rollback   Esc: close" }) }));
    }
    return (_jsxs(Box, { borderStyle: "single", borderTop: true, borderBottom: false, borderLeft: false, borderRight: false, children: [_jsx(Text, { dimColor: true, children: "h/l: panels  j/k: move  g/G: first/last  /: search  q: quit" }), activePanel === 'detail' && (_jsx(Text, { dimColor: true, children: "  \u00B7  i: install  s: star  H: history  l: open" }))] }));
}

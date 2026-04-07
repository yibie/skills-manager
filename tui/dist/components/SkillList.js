import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Box, Text } from 'ink';
export function SkillList({ skills, selectedIndex, isActive, height }) {
    const borderColor = isActive ? 'blue' : undefined;
    // Subtract structural rows: top border(1) + header(1) + marginTop(1) + bottom border(1) = 4
    const visibleRows = Math.max(1, height - 4);
    // Keep selected item centered in the viewport
    const scrollStart = Math.max(0, Math.min(selectedIndex - Math.floor(visibleRows / 2), Math.max(0, skills.length - visibleRows)));
    const visibleSkills = skills.slice(scrollStart, scrollStart + visibleRows);
    return (_jsxs(Box, { flexDirection: "column", flexGrow: 1, borderStyle: "round", borderColor: borderColor, paddingX: 1, children: [_jsxs(Box, { children: [_jsx(Text, { bold: true, children: "Skills " }), _jsx(Text, { dimColor: true, children: skills.length > 0 ? `${selectedIndex + 1}/${skills.length}` : '0' })] }), _jsxs(Box, { flexDirection: "column", marginTop: 1, children: [skills.length === 0 && _jsx(Text, { dimColor: true, children: "No skills found" }), visibleSkills.map((skill, relIdx) => (_jsx(SkillRow, { skill: skill, isSelected: scrollStart + relIdx === selectedIndex }, skill.name)))] })] }));
}
function SkillRow({ skill, isSelected }) {
    return (_jsxs(Box, { children: [_jsxs(Text, { backgroundColor: isSelected ? 'blue' : undefined, wrap: "truncate", children: [isSelected ? '▶ ' : '  ', skill.displayName] }), skill.isStarred && _jsx(Text, { color: "yellow", children: " \u2605" }), skill.isInstalled && _jsx(Text, { color: "green", children: " \u25CF" })] }));
}

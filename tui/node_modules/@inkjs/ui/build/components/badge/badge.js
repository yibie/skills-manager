import { Text } from 'ink';
import React from 'react';
import { useComponentTheme } from '../../theme.js';
export function Badge({ children, color = 'magenta' }) {
    const { styles } = useComponentTheme('Badge');
    let formattedChildren = children;
    if (typeof children === 'string') {
        formattedChildren = children.toUpperCase();
    }
    return (React.createElement(Text, { ...styles.container({ color }) },
        ' ',
        React.createElement(Text, { ...styles.label() }, formattedChildren),
        ' '));
}
//# sourceMappingURL=badge.js.map
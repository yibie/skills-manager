import React from 'react';
import { Box, Text } from 'ink';
import { useComponentTheme } from '../../theme.js';
export function Alert({ children, variant, title }) {
    const { styles, config } = useComponentTheme('Alert');
    return (React.createElement(Box, { ...styles.container({ variant }) },
        React.createElement(Box, { ...styles.iconContainer() },
            React.createElement(Text, { ...styles.icon({ variant }) }, config({ variant }).icon)),
        React.createElement(Box, { ...styles.content() },
            title && React.createElement(Text, { ...styles.title() }, title),
            React.createElement(Text, { ...styles.message() }, children))));
}
//# sourceMappingURL=alert.js.map
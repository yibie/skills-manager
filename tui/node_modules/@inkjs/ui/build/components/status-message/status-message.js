import React from 'react';
import { Box, Text } from 'ink';
import { useComponentTheme } from '../../theme.js';
export function StatusMessage({ children, variant }) {
    const { styles, config } = useComponentTheme('StatusMessage');
    return (React.createElement(Box, { ...styles.container() },
        React.createElement(Box, { ...styles.iconContainer() },
            React.createElement(Text, { ...styles.icon({ variant }) }, config({ variant }).icon)),
        React.createElement(Text, { ...styles.message() }, children)));
}
//# sourceMappingURL=status-message.js.map
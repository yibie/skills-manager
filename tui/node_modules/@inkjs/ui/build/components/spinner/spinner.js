import React from 'react';
import { Box, Text } from 'ink';
import { useComponentTheme } from '../../theme.js';
import { useSpinner } from './use-spinner.js';
export function Spinner({ label, type }) {
    const { frame } = useSpinner({ type });
    const { styles } = useComponentTheme('Spinner');
    return (React.createElement(Box, { ...styles.container() },
        React.createElement(Text, { ...styles.frame() }, frame),
        label && React.createElement(Text, { ...styles.label() }, label)));
}
//# sourceMappingURL=spinner.js.map
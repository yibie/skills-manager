import { Box, Text } from 'ink';
import React, { useContext } from 'react';
import { useComponentTheme } from '../../theme.js';
import { UnorderedListItemContext } from './unordered-list-item-context.js';
export function UnorderedListItem({ children }) {
    const { marker } = useContext(UnorderedListItemContext);
    const { styles } = useComponentTheme('UnorderedList');
    return (React.createElement(Box, { ...styles.listItem() },
        React.createElement(Text, { ...styles.marker() }, marker),
        React.createElement(Box, { ...styles.content() }, children)));
}
//# sourceMappingURL=unordered-list-item.js.map
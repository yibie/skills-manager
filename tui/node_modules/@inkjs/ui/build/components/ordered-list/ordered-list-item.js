import { Box, Text } from 'ink';
import React, { useContext } from 'react';
import { useComponentTheme } from '../../theme.js';
import { OrderedListItemContext } from './ordered-list-item-context.js';
export function OrderedListItem({ children }) {
    const { marker } = useContext(OrderedListItemContext);
    const { styles } = useComponentTheme('OrderedList');
    return (React.createElement(Box, { ...styles.listItem() },
        React.createElement(Text, { ...styles.marker() }, marker),
        React.createElement(Box, { ...styles.content() }, children)));
}
//# sourceMappingURL=ordered-list-item.js.map
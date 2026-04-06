import { Box } from 'ink';
import React, { useContext, isValidElement } from 'react';
import { useComponentTheme } from '../../theme.js';
import { OrderedListItem } from './ordered-list-item.js';
import { OrderedListContext } from './ordered-list-context.js';
import { OrderedListItemContext } from './ordered-list-item-context.js';
export function OrderedList({ children }) {
    const { marker: parentMarker } = useContext(OrderedListContext);
    const { styles } = useComponentTheme('OrderedList');
    let numberOfItems = 0;
    for (const child of React.Children.toArray(children)) {
        if (!isValidElement(child) || child.type !== OrderedListItem) {
            continue;
        }
        numberOfItems++;
    }
    const maxMarkerWidth = String(numberOfItems).length;
    return (React.createElement(Box, { ...styles.list() }, React.Children.map(children, (child, index) => {
        if (!isValidElement(child) || child.type !== OrderedListItem) {
            return child;
        }
        const paddedMarker = `${String(index + 1).padStart(maxMarkerWidth)}.`;
        const marker = `${parentMarker}${paddedMarker}`;
        return (
        // eslint-disable-next-line react/jsx-no-constructed-context-values
        React.createElement(OrderedListContext.Provider, { value: { marker } },
            React.createElement(OrderedListItemContext.Provider, { value: { marker } }, child)));
    })));
}
OrderedList.Item = OrderedListItem;
//# sourceMappingURL=ordered-list.js.map
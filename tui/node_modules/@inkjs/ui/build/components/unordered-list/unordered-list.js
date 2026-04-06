import { Box } from 'ink';
import React, { useMemo, useContext } from 'react';
import { useComponentTheme } from '../../theme.js';
import { UnorderedListItem } from './unordered-list-item.js';
import { UnorderedListContext } from './unordered-list-context.js';
import { UnorderedListItemContext } from './unordered-list-item-context.js';
import { defaultMarker } from './constants.js';
export function UnorderedList({ children }) {
    const { depth } = useContext(UnorderedListContext);
    const { styles, config } = useComponentTheme('UnorderedList');
    const listContext = useMemo(() => ({
        depth: depth + 1,
    }), [depth]);
    const listItemContext = useMemo(() => {
        const { marker } = config();
        if (typeof marker === 'string') {
            return { marker };
        }
        if (Array.isArray(marker)) {
            return {
                marker: marker[depth] ?? marker.at(-1) ?? defaultMarker,
            };
        }
        return {
            marker: defaultMarker,
        };
    }, [config, depth]);
    return (React.createElement(UnorderedListContext.Provider, { value: listContext },
        React.createElement(UnorderedListItemContext.Provider, { value: listItemContext },
            React.createElement(Box, { ...styles.list() }, children))));
}
UnorderedList.Item = UnorderedListItem;
//# sourceMappingURL=unordered-list.js.map
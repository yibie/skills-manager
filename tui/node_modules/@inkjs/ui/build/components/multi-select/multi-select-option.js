import React from 'react';
import { Box, Text } from 'ink';
import figures from 'figures';
import { useComponentTheme } from '../../theme.js';
export function MultiSelectOption({ isFocused, isSelected, children, }) {
    const { styles } = useComponentTheme('MultiSelect');
    return (React.createElement(Box, { ...styles.option({ isFocused }) },
        isFocused && React.createElement(Text, { ...styles.focusIndicator() }, figures.pointer),
        React.createElement(Text, { ...styles.label({ isFocused, isSelected }) }, children),
        isSelected && (React.createElement(Text, { ...styles.selectedIndicator() }, figures.tick))));
}
//# sourceMappingURL=multi-select-option.js.map
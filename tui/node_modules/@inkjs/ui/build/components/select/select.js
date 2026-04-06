import React from 'react';
import { Box, Text } from 'ink';
import { useComponentTheme } from '../../theme.js';
import { SelectOption } from './select-option.js';
import { useSelectState } from './use-select-state.js';
import { useSelect } from './use-select.js';
export function Select({ isDisabled = false, visibleOptionCount = 5, highlightText, options, defaultValue, onChange, }) {
    const state = useSelectState({
        visibleOptionCount,
        options,
        defaultValue,
        onChange,
    });
    useSelect({ isDisabled, state });
    const { styles } = useComponentTheme('Select');
    return (React.createElement(Box, { ...styles.container() }, state.visibleOptions.map(option => {
        // eslint-disable-next-line prefer-destructuring
        let label = option.label;
        if (highlightText && option.label.includes(highlightText)) {
            const index = option.label.indexOf(highlightText);
            label = (React.createElement(React.Fragment, null,
                option.label.slice(0, index),
                React.createElement(Text, { ...styles.highlightedText() }, highlightText),
                option.label.slice(index + highlightText.length)));
        }
        return (React.createElement(SelectOption, { key: option.value, isFocused: !isDisabled && state.focusedValue === option.value, isSelected: state.value === option.value }, label));
    })));
}
//# sourceMappingURL=select.js.map
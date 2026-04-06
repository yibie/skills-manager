import React from 'react';
import { Box, Text } from 'ink';
import { useComponentTheme } from '../../theme.js';
import { MultiSelectOption } from './multi-select-option.js';
import { useMultiSelectState } from './use-multi-select-state.js';
import { useMultiSelect } from './use-multi-select.js';
export function MultiSelect({ isDisabled = false, visibleOptionCount = 5, highlightText, options, defaultValue, onChange, onSubmit, }) {
    const state = useMultiSelectState({
        visibleOptionCount,
        options,
        defaultValue,
        onChange,
        onSubmit,
    });
    useMultiSelect({ isDisabled, state });
    const { styles } = useComponentTheme('MultiSelect');
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
        return (React.createElement(MultiSelectOption, { key: option.value, isFocused: !isDisabled && state.focusedValue === option.value, isSelected: state.value.includes(option.value) }, label));
    })));
}
//# sourceMappingURL=multi-select.js.map
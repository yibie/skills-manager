import React from 'react';
import { Text } from 'ink';
import { useComponentTheme } from '../../theme.js';
import { useTextInputState } from './use-text-input-state.js';
import { useTextInput } from './use-text-input.js';
export function TextInput({ isDisabled = false, defaultValue, placeholder = '', suggestions, onChange, onSubmit, }) {
    const state = useTextInputState({
        defaultValue,
        suggestions,
        onChange,
        onSubmit,
    });
    const { inputValue } = useTextInput({
        isDisabled,
        placeholder,
        state,
    });
    const { styles } = useComponentTheme('TextInput');
    return React.createElement(Text, { ...styles.value() }, inputValue);
}
//# sourceMappingURL=text-input.js.map
import React from 'react';
import { Text } from 'ink';
import { useComponentTheme } from '../../theme.js';
import { usePasswordInputState } from './use-password-input-state.js';
import { usePasswordInput } from './use-password-input.js';
export function PasswordInput({ isDisabled = false, placeholder = '', onChange, onSubmit, }) {
    const state = usePasswordInputState({
        onChange,
        onSubmit,
    });
    const { inputValue } = usePasswordInput({
        isDisabled,
        placeholder,
        state,
    });
    const { styles } = useComponentTheme('PasswordInput');
    return React.createElement(Text, { ...styles.value() }, inputValue);
}
//# sourceMappingURL=password-input.js.map
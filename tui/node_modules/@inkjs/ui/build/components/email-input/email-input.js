import React from 'react';
import { Text } from 'ink';
import { useComponentTheme } from '../../theme.js';
import { useEmailInputState } from './use-email-input-state.js';
import { useEmailInput } from './use-email-input.js';
export function EmailInput({ isDisabled = false, defaultValue, placeholder = '', domains, onChange, onSubmit, }) {
    const state = useEmailInputState({
        defaultValue,
        domains,
        onChange,
        onSubmit,
    });
    const { inputValue } = useEmailInput({
        isDisabled,
        placeholder,
        state,
    });
    const { styles } = useComponentTheme('EmailInput');
    return React.createElement(Text, { ...styles.value() }, inputValue);
}
//# sourceMappingURL=email-input.js.map
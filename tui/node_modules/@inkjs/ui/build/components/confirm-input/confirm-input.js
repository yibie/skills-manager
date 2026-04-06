import React from 'react';
import { Text, useInput } from 'ink';
import { useComponentTheme } from '../../theme.js';
export function ConfirmInput({ isDisabled = false, defaultChoice = 'confirm', submitOnEnter = true, onConfirm, onCancel, }) {
    useInput((input, key) => {
        if (input.toLowerCase() === 'y') {
            onConfirm();
        }
        if (input.toLowerCase() === 'n') {
            onCancel();
        }
        if (key.return && submitOnEnter) {
            if (defaultChoice === 'confirm') {
                onConfirm();
            }
            else {
                onCancel();
            }
        }
    }, { isActive: !isDisabled });
    const { styles } = useComponentTheme('ConfirmInput');
    return (React.createElement(Text, { ...styles.input({ isFocused: !isDisabled }) }, defaultChoice === 'confirm' ? 'Y/n' : 'y/N'));
}
//# sourceMappingURL=confirm-input.js.map
import { useInput } from 'ink';
export const useMultiSelect = ({ isDisabled = false, state, }) => {
    useInput((input, key) => {
        if (key.downArrow) {
            state.focusNextOption();
        }
        if (key.upArrow) {
            state.focusPreviousOption();
        }
        if (input === ' ') {
            state.toggleFocusedOption();
        }
        if (key.return) {
            state.submit();
        }
    }, { isActive: !isDisabled });
};
//# sourceMappingURL=use-multi-select.js.map
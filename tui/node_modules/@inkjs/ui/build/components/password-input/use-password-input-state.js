import { useReducer, useCallback, useEffect } from 'react';
const reducer = (state, action) => {
    switch (action.type) {
        case 'move-cursor-left': {
            return {
                ...state,
                cursorOffset: Math.max(0, state.cursorOffset - 1),
            };
        }
        case 'move-cursor-right': {
            return {
                ...state,
                cursorOffset: Math.min(state.value.length, state.cursorOffset + 1),
            };
        }
        case 'insert': {
            return {
                ...state,
                previousValue: state.value,
                value: state.value.slice(0, state.cursorOffset) +
                    action.text +
                    state.value.slice(state.cursorOffset),
                cursorOffset: state.cursorOffset + action.text.length,
            };
        }
        case 'delete': {
            const newCursorOffset = Math.max(0, state.cursorOffset - 1);
            return {
                ...state,
                previousValue: state.value,
                value: state.value.slice(0, newCursorOffset) +
                    state.value.slice(newCursorOffset + 1),
                cursorOffset: newCursorOffset,
            };
        }
    }
};
export const usePasswordInputState = ({ onChange, onSubmit, }) => {
    const [state, dispatch] = useReducer(reducer, {
        previousValue: '',
        value: '',
        cursorOffset: 0,
    });
    const moveCursorLeft = useCallback(() => {
        dispatch({
            type: 'move-cursor-left',
        });
    }, []);
    const moveCursorRight = useCallback(() => {
        dispatch({
            type: 'move-cursor-right',
        });
    }, []);
    const insert = useCallback((text) => {
        dispatch({
            type: 'insert',
            text,
        });
    }, []);
    const deleteCharacter = useCallback(() => {
        dispatch({
            type: 'delete',
        });
    }, []);
    const submit = useCallback(() => {
        onSubmit?.(state.value);
    }, [state.value, onSubmit]);
    useEffect(() => {
        if (state.value !== state.previousValue) {
            onChange?.(state.value);
        }
    }, [state.previousValue, state.value, onChange]);
    return {
        ...state,
        moveCursorLeft,
        moveCursorRight,
        insert,
        delete: deleteCharacter,
        submit,
    };
};
//# sourceMappingURL=use-password-input-state.js.map
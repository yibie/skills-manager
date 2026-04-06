import { useReducer, useCallback, useEffect, useMemo } from 'react';
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
export const useTextInputState = ({ defaultValue = '', suggestions, onChange, onSubmit, }) => {
    const [state, dispatch] = useReducer(reducer, {
        previousValue: defaultValue,
        value: defaultValue,
        cursorOffset: defaultValue.length,
    });
    const suggestion = useMemo(() => {
        if (state.value.length === 0) {
            return;
        }
        return suggestions
            ?.find(suggestion => suggestion.startsWith(state.value))
            ?.replace(state.value, '');
    }, [state.value, suggestions]);
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
        if (suggestion) {
            insert(suggestion);
            onSubmit?.(state.value + suggestion);
            return;
        }
        onSubmit?.(state.value);
    }, [state.value, suggestion, insert, onSubmit]);
    useEffect(() => {
        if (state.value !== state.previousValue) {
            onChange?.(state.value);
        }
    }, [state.previousValue, state.value, onChange]);
    return {
        ...state,
        suggestion,
        moveCursorLeft,
        moveCursorRight,
        insert,
        delete: deleteCharacter,
        submit,
    };
};
//# sourceMappingURL=use-text-input-state.js.map
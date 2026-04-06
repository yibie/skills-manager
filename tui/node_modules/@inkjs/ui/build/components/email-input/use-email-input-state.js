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
            if (state.value.includes('@') && action.text.includes('@')) {
                return state;
            }
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
export const useEmailInputState = ({ defaultValue = '', domains = [
    'aol.com',
    'gmail.com',
    'yahoo.com',
    'hotmail.com',
    'live.com',
    'outlook.com',
    'icloud.com',
    'hey.com',
], onChange, onSubmit, }) => {
    const [state, dispatch] = useReducer(reducer, {
        previousValue: defaultValue,
        value: defaultValue,
        cursorOffset: defaultValue.length,
    });
    const suggestion = useMemo(() => {
        if (state.value.length === 0 || !state.value.includes('@')) {
            return;
        }
        const atIndex = state.value.indexOf('@');
        const enteredDomain = state.value.slice(atIndex + 1);
        return domains
            ?.find(domain => domain.startsWith(enteredDomain))
            ?.replace(enteredDomain, '');
    }, [state.value, domains]);
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
        if (state.previousValue !== state.value) {
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
//# sourceMappingURL=use-email-input-state.js.map
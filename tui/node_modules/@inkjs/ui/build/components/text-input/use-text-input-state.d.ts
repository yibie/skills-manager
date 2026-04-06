type State = {
    previousValue: string;
    value: string;
    cursorOffset: number;
};
export type UseTextInputStateProps = {
    /**
     * Default input value.
     */
    defaultValue?: string;
    /**
     * Suggestions to autocomplete the input value.
     */
    suggestions?: string[];
    /**
     * Callback when input value changes.
     */
    onChange?: (value: string) => void;
    /**
     * Callback when enter is pressed. First argument is input value.
     */
    onSubmit?: (value: string) => void;
};
export type TextInputState = State & {
    /**
     * Suggested auto completion.
     */
    suggestion: string | undefined;
    /**
     * Move cursor to the left.
     */
    moveCursorLeft: () => void;
    /**
     * Move cursor to the right.
     */
    moveCursorRight: () => void;
    /**
     * Insert text.
     */
    insert: (text: string) => void;
    /**
     * Delete character.
     */
    delete: () => void;
    /**
     * Submit input value.
     */
    submit: () => void;
};
export declare const useTextInputState: ({ defaultValue, suggestions, onChange, onSubmit, }: UseTextInputStateProps) => {
    suggestion: string | undefined;
    moveCursorLeft: () => void;
    moveCursorRight: () => void;
    insert: (text: string) => void;
    delete: () => void;
    submit: () => void;
    previousValue: string;
    value: string;
    cursorOffset: number;
};
export {};

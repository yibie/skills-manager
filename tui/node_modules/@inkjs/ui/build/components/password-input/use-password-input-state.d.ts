type State = {
    previousValue: string;
    value: string;
    cursorOffset: number;
};
export type UseTextInputStateProps = {
    /**
     * Callback when value updates.
     */
    onChange?: (value: string) => void;
    /**
     * Callback when `Enter` is pressed. First argument is a value of the input.
     */
    onSubmit?: (value: string) => void;
};
export type PasswordInputState = State & {
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
export declare const usePasswordInputState: ({ onChange, onSubmit, }: UseTextInputStateProps) => {
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

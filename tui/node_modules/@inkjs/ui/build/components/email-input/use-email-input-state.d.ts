type State = {
    previousValue: string;
    value: string;
    cursorOffset: number;
};
export type UseEmailInputStateProps = {
    /**
     * Initial value to display in a text input.
     */
    defaultValue?: string;
    /**
     * Domains of email providers to auto complete.
     *
     * @default ["aol.com", "gmail.com", "yahoo.com", "hotmail.com", "live.com", "outlook.com", "icloud.com", "hey.com"]
     */
    domains?: string[];
    /**
     * Callback when value updates.
     */
    onChange?: (value: string) => void;
    /**
     * Callback when `Enter` is pressed. First argument is a value of the input.
     */
    onSubmit?: (value: string) => void;
};
export type EmailInputState = State & {
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
export declare const useEmailInputState: ({ defaultValue, domains, onChange, onSubmit, }: UseEmailInputStateProps) => {
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

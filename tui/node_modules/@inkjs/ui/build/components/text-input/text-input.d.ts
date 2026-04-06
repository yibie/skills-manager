import React from 'react';
export type TextInputProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    readonly isDisabled?: boolean;
    /**
     * Text to display when input is empty.
     */
    readonly placeholder?: string;
    /**
     * Default input value.
     */
    readonly defaultValue?: string;
    /**
     * Suggestions to autocomplete the input value.
     */
    readonly suggestions?: string[];
    /**
     * Callback when input value changes.
     */
    readonly onChange?: (value: string) => void;
    /**
     * Callback when enter is pressed. First argument is input value.
     */
    readonly onSubmit?: (value: string) => void;
};
export declare function TextInput({ isDisabled, defaultValue, placeholder, suggestions, onChange, onSubmit, }: TextInputProps): React.JSX.Element;

import React from 'react';
export type EmailInputProps = {
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
     * Domains of email providers to autocomplete.
     *
     * @default ["aol.com", "gmail.com", "yahoo.com", "hotmail.com", "live.com", "outlook.com", "icloud.com", "hey.com"]
     */
    readonly domains?: string[];
    /**
     * Callback when input value changes.
     */
    readonly onChange?: (value: string) => void;
    /**
     * Callback when enter is pressed. First argument is input value.
     */
    readonly onSubmit?: (value: string) => void;
};
export declare function EmailInput({ isDisabled, defaultValue, placeholder, domains, onChange, onSubmit, }: EmailInputProps): React.JSX.Element;

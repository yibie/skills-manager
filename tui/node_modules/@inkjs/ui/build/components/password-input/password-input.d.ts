import React from 'react';
export type PasswordInputProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    readonly isDisabled?: boolean;
    /**
     * Text to display when `value` is empty.
     */
    readonly placeholder?: string;
    /**
     * Callback when value updates.
     */
    readonly onChange?: (value: string) => void;
    /**
     * Callback when `Enter` is pressed. First argument is a value of the input.
     */
    readonly onSubmit?: (value: string) => void;
};
export declare function PasswordInput({ isDisabled, placeholder, onChange, onSubmit, }: PasswordInputProps): React.JSX.Element;

import { type PasswordInputState } from './use-password-input-state.js';
export type UsePasswordInputProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    isDisabled?: boolean;
    /**
     * Password input state.
     */
    state: PasswordInputState;
    /**
     * Text to display when `value` is empty.
     *
     * @default ""
     */
    placeholder?: string;
};
export type UsePasswordInputResult = {
    /**
     * Value to render inside the input.
     */
    inputValue: string;
};
export declare const usePasswordInput: ({ isDisabled, state, placeholder, }: UsePasswordInputProps) => UsePasswordInputResult;

import { type EmailInputState } from './use-email-input-state.js';
export type UseEmailInputProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    isDisabled?: boolean;
    /**
     * Text input state.
     */
    state: EmailInputState;
    /**
     * Text to display when `value` is empty.
     *
     * @default ""
     */
    placeholder?: string;
};
export type UseTextInputResult = {
    /**
     * Value to render inside the input.
     */
    inputValue: string;
};
export declare const useEmailInput: ({ isDisabled, state, placeholder, }: UseEmailInputProps) => UseTextInputResult;

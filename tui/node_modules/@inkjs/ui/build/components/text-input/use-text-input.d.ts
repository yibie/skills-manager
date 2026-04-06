import { type TextInputState } from './use-text-input-state.js';
export type UseTextInputProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    isDisabled?: boolean;
    /**
     * Text input state.
     */
    state: TextInputState;
    /**
     * Text to display when input is empty.
     */
    placeholder?: string;
};
export type UseTextInputResult = {
    /**
     * Input value.
     */
    inputValue: string;
};
export declare const useTextInput: ({ isDisabled, state, placeholder, }: UseTextInputProps) => UseTextInputResult;

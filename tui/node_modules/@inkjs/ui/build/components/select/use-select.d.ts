import { type SelectState } from './use-select-state.js';
export type UseSelectProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    isDisabled?: boolean;
    /**
     * Select state.
     */
    state: SelectState;
};
export declare const useSelect: ({ isDisabled, state }: UseSelectProps) => void;

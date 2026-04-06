import { type MultiSelectState } from './use-multi-select-state.js';
export type UseMultiSelectProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    isDisabled?: boolean;
    /**
     * Select state.
     */
    state: MultiSelectState;
};
export declare const useMultiSelect: ({ isDisabled, state, }: UseMultiSelectProps) => void;

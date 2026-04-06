import OptionMap from '../../lib/option-map.js';
import { type Option } from '../../types.js';
type State = {
    /**
     * Map where key is option's value and value is option's index.
     */
    optionMap: OptionMap;
    /**
     * Number of visible options.
     */
    visibleOptionCount: number;
    /**
     * Value of the currently focused option.
     */
    focusedValue: string | undefined;
    /**
     * Index of the first visible option.
     */
    visibleFromIndex: number;
    /**
     * Index of the last visible option.
     */
    visibleToIndex: number;
    /**
     * Values of previously selected options.
     */
    previousValue: string[];
    /**
     * Indexes of selected options.
     */
    value: string[];
};
export type UseMultiSelectStateProps = {
    /**
     * Number of visible options.
     *
     * @default 5
     */
    visibleOptionCount?: number;
    /**
     * Options.
     */
    options: Option[];
    /**
     * Initially selected option values.
     */
    defaultValue?: string[];
    /**
     * Callback for selecting options.
     */
    onChange?: (value: string[]) => void;
    /**
     * Callback when user presses enter.
     * First argument is an array of selected option values.
     */
    onSubmit?: (value: string[]) => void;
};
export type MultiSelectState = Pick<State, 'focusedValue' | 'visibleFromIndex' | 'visibleToIndex' | 'value'> & {
    /**
     * Visible options.
     */
    visibleOptions: Array<Option & {
        index: number;
    }>;
    /**
     * Focus next option and scroll the list down, if needed.
     */
    focusNextOption: () => void;
    /**
     * Focus previous option and scroll the list up, if needed.
     */
    focusPreviousOption: () => void;
    /**
     * Select currently focused option.
     */
    toggleFocusedOption: () => void;
    /**
     * Trigger `onSubmit` callback.
     */
    submit: () => void;
};
export declare const useMultiSelectState: ({ visibleOptionCount, options, defaultValue, onChange, onSubmit, }: UseMultiSelectStateProps) => {
    focusedValue: string | undefined;
    visibleFromIndex: number;
    visibleToIndex: number;
    value: string[];
    visibleOptions: {
        index: number;
        label: string;
        value: string;
    }[];
    focusNextOption: () => void;
    focusPreviousOption: () => void;
    toggleFocusedOption: () => void;
    submit: () => void;
};
export {};

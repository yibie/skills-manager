import { type Option } from '../../types.js';
import OptionMap from '../../lib/option-map.js';
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
     * Value of the previously selected option.
     */
    previousValue: string | undefined;
    /**
     * Value of the selected option.
     */
    value: string | undefined;
};
export type UseSelectStateProps = {
    /**
     * Number of items to display.
     *
     * @default 5
     */
    visibleOptionCount?: number;
    /**
     * Options.
     */
    options: Option[];
    /**
     * Initially selected option's value.
     */
    defaultValue?: string;
    /**
     * Callback for selecting an option.
     */
    onChange?: (value: string) => void;
};
export type SelectState = Pick<State, 'focusedValue' | 'visibleFromIndex' | 'visibleToIndex' | 'value'> & {
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
    selectFocusedOption: () => void;
};
export declare const useSelectState: ({ visibleOptionCount, options, defaultValue, onChange, }: UseSelectStateProps) => {
    focusedValue: string | undefined;
    visibleFromIndex: number;
    visibleToIndex: number;
    value: string | undefined;
    visibleOptions: {
        index: number;
        label: string;
        value: string;
    }[];
    focusNextOption: () => void;
    focusPreviousOption: () => void;
    selectFocusedOption: () => void;
};
export {};

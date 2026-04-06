import React from 'react';
import { type Option } from '../../types.js';
export type MultiSelectProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    readonly isDisabled?: boolean;
    /**
     * Number of visible options.
     *
     * @default 5
     */
    readonly visibleOptionCount?: number;
    /**
     * Highlight text in option labels.
     * Useful for filtering options.
     */
    readonly highlightText?: string;
    /**
     * Options.
     */
    readonly options: Option[];
    /**
     * Initially selected option values.
     */
    readonly defaultValue?: string[];
    /**
     * Callback for selecting options.
     */
    readonly onChange?: (value: string[]) => void;
    /**
     * Callback when user presses enter.
     * First argument is an array of selected option values.
     */
    readonly onSubmit?: (value: string[]) => void;
};
export declare function MultiSelect({ isDisabled, visibleOptionCount, highlightText, options, defaultValue, onChange, onSubmit, }: MultiSelectProps): React.JSX.Element;

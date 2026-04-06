import React from 'react';
import { type Option } from '../../types.js';
export type SelectProps = {
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
     */
    readonly highlightText?: string;
    /**
     * Options.
     */
    readonly options: Option[];
    /**
     * Default value.
     */
    readonly defaultValue?: string;
    /**
     * Callback when selected option changes.
     */
    readonly onChange?: (value: string) => void;
};
export declare function Select({ isDisabled, visibleOptionCount, highlightText, options, defaultValue, onChange, }: SelectProps): React.JSX.Element;

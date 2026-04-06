import React, { type ReactNode } from 'react';
export type MultiSelectOptionProps = {
    /**
     * Determines if option is focused.
     */
    readonly isFocused: boolean;
    /**
     * Determines if option is selected.
     */
    readonly isSelected: boolean;
    /**
     * Option label.
     */
    readonly children: ReactNode;
};
export declare function MultiSelectOption({ isFocused, isSelected, children, }: MultiSelectOptionProps): React.JSX.Element;

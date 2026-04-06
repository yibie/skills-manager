import React, { type ReactNode } from 'react';
export type SelectOptionProps = {
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
export declare function SelectOption({ isFocused, isSelected, children, }: SelectOptionProps): React.JSX.Element;

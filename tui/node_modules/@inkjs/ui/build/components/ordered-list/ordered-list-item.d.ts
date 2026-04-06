import React, { type ReactNode } from 'react';
export type OrderedListItemProps = {
    /**
     * List item content.
     */
    readonly children: ReactNode;
};
export declare function OrderedListItem({ children }: OrderedListItemProps): React.JSX.Element;

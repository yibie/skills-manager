import React, { type ReactNode } from 'react';
import { OrderedListItem } from './ordered-list-item.js';
export type OrderedListProps = {
    /**
     * List items.
     */
    readonly children: ReactNode;
};
export declare function OrderedList({ children }: OrderedListProps): React.JSX.Element;
export declare namespace OrderedList {
    var Item: typeof OrderedListItem;
}

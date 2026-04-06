import React, { type ReactNode } from 'react';
import { UnorderedListItem } from './unordered-list-item.js';
export type UnorderedListProps = {
    /**
     * List items.
     */
    readonly children: ReactNode;
};
export declare function UnorderedList({ children }: UnorderedListProps): React.JSX.Element;
export declare namespace UnorderedList {
    var Item: typeof UnorderedListItem;
}

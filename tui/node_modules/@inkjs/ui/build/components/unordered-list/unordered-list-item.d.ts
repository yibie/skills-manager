import React, { type ReactNode } from 'react';
export type UnorderedListItemProps = {
    /**
     * List item content.
     */
    readonly children: ReactNode;
};
export declare function UnorderedListItem({ children }: UnorderedListItemProps): React.JSX.Element;

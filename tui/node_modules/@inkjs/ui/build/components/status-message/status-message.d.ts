import React, { type ReactNode } from 'react';
import { type StatusMessageVariant } from './types.js';
export type StatusMessageProps = {
    /**
     * Message.
     */
    readonly children: ReactNode;
    /**
     * Variant, which determines the color used in the status message.
     */
    readonly variant: StatusMessageVariant;
};
export declare function StatusMessage({ children, variant }: StatusMessageProps): React.JSX.Element;

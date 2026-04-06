import React, { type ReactNode } from 'react';
export type AlertProps = {
    /**
     * Message.
     */
    readonly children: ReactNode;
    /**
     * Variant, which determines the color of the alert.
     */
    readonly variant: 'info' | 'success' | 'error' | 'warning';
    /**
     * Title to show above the message.
     */
    readonly title?: string;
};
export declare function Alert({ children, variant, title }: AlertProps): React.JSX.Element;

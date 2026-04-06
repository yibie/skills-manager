import { type TextProps } from 'ink';
import React, { type ReactNode } from 'react';
export type BadgeProps = {
    /**
     * Label.
     */
    readonly children: ReactNode;
    /**
     * Color.
     *
     * @default "magenta"
     */
    readonly color?: TextProps['color'];
};
export declare function Badge({ children, color }: BadgeProps): React.JSX.Element;

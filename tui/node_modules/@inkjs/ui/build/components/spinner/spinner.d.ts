import React from 'react';
import { type UseSpinnerProps } from './use-spinner.js';
export type SpinnerProps = UseSpinnerProps & {
    /**
     * Label to show near the spinner.
     */
    readonly label?: string;
};
export declare function Spinner({ label, type }: SpinnerProps): React.JSX.Element;

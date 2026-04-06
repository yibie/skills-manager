import React from 'react';
export type ProgressBarProps = {
    /**
     * Progress.
     * Must be between 0 and 100.
     *
     * @default 0
     */
    readonly value: number;
};
export declare function ProgressBar({ value }: ProgressBarProps): React.JSX.Element;

import React from 'react';
export type ConfirmInputProps = {
    /**
     * When disabled, user input is ignored.
     *
     * @default false
     */
    readonly isDisabled?: boolean;
    /**
     * Default choice.
     *
     * @default "confirm"
     */
    readonly defaultChoice?: 'confirm' | 'cancel';
    /**
     * Confirm or cancel when user presses enter, depending on the `defaultChoice` value.
     * Can be useful to disable when an explicit confirmation is required, such as pressing "Y" key.
     *
     * @default true
     */
    readonly submitOnEnter?: boolean;
    /**
     * Callback to trigger on confirmation.
     */
    readonly onConfirm: () => void;
    /**
     * Callback to trigger on cancellation.
     */
    readonly onCancel: () => void;
};
export declare function ConfirmInput({ isDisabled, defaultChoice, submitOnEnter, onConfirm, onCancel, }: ConfirmInputProps): React.JSX.Element;

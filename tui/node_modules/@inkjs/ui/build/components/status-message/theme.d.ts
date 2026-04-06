import { type BoxProps, type TextProps } from 'ink';
import { type StatusMessageVariant } from './types.js';
declare const theme: {
    styles: {
        container: () => BoxProps;
        iconContainer: () => BoxProps;
        icon: ({ variant }: {
            variant: StatusMessageVariant;
        }) => TextProps;
        message: () => TextProps;
    };
    config: ({ variant }: {
        variant: StatusMessageVariant;
    }) => {
        icon: string;
    };
};
export default theme;
export type Theme = typeof theme;

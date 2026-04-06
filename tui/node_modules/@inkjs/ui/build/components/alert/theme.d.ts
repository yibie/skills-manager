import { type BoxProps, type TextProps } from 'ink';
declare const theme: {
    styles: {
        container: ({ variant }: any) => BoxProps;
        iconContainer: () => BoxProps;
        icon: ({ variant }: any) => TextProps;
        content: () => BoxProps;
        title: () => TextProps;
        message: () => TextProps;
    };
    config({ variant }: any): {
        icon: string | undefined;
    };
};
export default theme;
export type Theme = typeof theme;

import { type BoxProps, type TextProps } from 'ink';
declare const theme: {
    styles: {
        container: () => BoxProps;
        frame: () => TextProps;
        label: () => TextProps;
    };
};
export default theme;
export type Theme = typeof theme;

import { type BoxProps, type TextProps } from 'ink';
declare const theme: {
    styles: {
        list: () => BoxProps;
        listItem: () => BoxProps;
        marker: () => TextProps;
        content: () => BoxProps;
    };
};
export default theme;
export type Theme = typeof theme;

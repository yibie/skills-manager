import { type BoxProps, type TextProps } from 'ink';
type Config = {
    marker: string | string[];
};
declare const theme: {
    styles: {
        list: () => BoxProps;
        listItem: () => BoxProps;
        marker: () => TextProps;
        content: () => BoxProps;
    };
    config: () => Config;
};
export default theme;
export type Theme = typeof theme;

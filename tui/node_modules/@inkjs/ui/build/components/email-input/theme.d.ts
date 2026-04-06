import { type TextProps } from 'ink';
declare const theme: {
    styles: {
        value: () => TextProps;
    };
};
export default theme;
export type Theme = typeof theme;

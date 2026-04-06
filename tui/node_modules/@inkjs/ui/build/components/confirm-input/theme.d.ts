import { type TextProps } from 'ink';
declare const theme: {
    styles: {
        input: ({ isFocused }: any) => TextProps;
    };
};
export default theme;
export type Theme = typeof theme;

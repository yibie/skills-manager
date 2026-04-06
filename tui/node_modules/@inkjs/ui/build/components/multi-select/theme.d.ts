import { type BoxProps, type TextProps } from 'ink';
declare const theme: {
    styles: {
        container: () => BoxProps;
        option: ({ isFocused }: any) => BoxProps;
        selectedIndicator: () => TextProps;
        focusIndicator: () => TextProps;
        label({ isFocused, isSelected }: any): TextProps;
        highlightedText: () => TextProps;
    };
};
export default theme;
export type Theme = typeof theme;

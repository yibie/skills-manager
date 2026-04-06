import { type TextProps } from 'ink';
declare const theme: {
    styles: {
        container: ({ color }: Pick<TextProps, 'color'>) => TextProps;
        label: () => TextProps;
    };
};
export default theme;
export type Theme = typeof theme;

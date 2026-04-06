import { type BoxProps, type TextProps } from 'ink';
declare const theme: {
    styles: {
        container: () => BoxProps;
        completed: () => TextProps;
        remaining: () => TextProps;
    };
    config: () => {
        completedCharacter: string;
        remainingCharacter: string;
    };
};
export default theme;
export type Theme = typeof theme;

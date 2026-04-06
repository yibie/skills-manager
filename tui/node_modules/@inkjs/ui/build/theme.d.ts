import React, { type ReactNode } from 'react';
export type Theme = {
    components: Record<string, ComponentTheme>;
};
export type ComponentTheme = {
    styles?: Record<string, (props?: any) => ComponentStyles>;
    config?: (props?: any) => Record<string, unknown>;
};
export type ComponentStyles = Record<string, unknown>;
export declare const defaultTheme: Theme;
export declare const ThemeContext: React.Context<Theme>;
export type ThemeProviderProps = {
    readonly children: ReactNode;
    readonly theme: Theme;
};
export declare function ThemeProvider({ children, theme }: ThemeProviderProps): React.JSX.Element;
export declare const extendTheme: (originalTheme: Theme, newTheme: Theme) => {
    components: Record<string, ComponentTheme>;
};
export declare const useComponentTheme: <Theme extends ComponentTheme>(component: string) => Theme;

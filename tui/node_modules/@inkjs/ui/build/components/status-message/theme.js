import figures from 'figures';
const colorByVariant = {
    success: 'green',
    error: 'red',
    warning: 'yellow',
    info: 'blue',
};
const iconByVariant = {
    success: figures.tick,
    error: figures.cross,
    warning: figures.warning,
    info: figures.info,
};
const theme = {
    styles: {
        container: () => ({
            gap: 1,
        }),
        iconContainer: () => ({
            flexShrink: 0,
        }),
        icon: ({ variant }) => ({
            color: colorByVariant[variant],
        }),
        message: () => ({}),
    },
    config: ({ variant }) => ({
        icon: iconByVariant[variant],
    }),
};
export default theme;
//# sourceMappingURL=theme.js.map
import figures from 'figures';
const colorByVariant = {
    info: 'blue',
    success: 'green',
    error: 'red',
    warning: 'yellow',
};
const theme = {
    styles: {
        container: ({ variant }) => ({
            flexGrow: 1,
            borderStyle: 'round',
            borderColor: colorByVariant[variant],
            gap: 1,
            paddingX: 1,
        }),
        iconContainer: () => ({
            flexShrink: 0,
        }),
        icon: ({ variant }) => ({
            color: colorByVariant[variant],
        }),
        content: () => ({
            flexShrink: 1,
            flexGrow: 1,
            minWidth: 0,
            flexDirection: 'column',
            gap: 1,
        }),
        title: () => ({
            bold: true,
        }),
        message: () => ({}),
    },
    config({ variant }) {
        let icon;
        if (variant === 'info') {
            icon = figures.info;
        }
        if (variant === 'success') {
            icon = figures.tick;
        }
        if (variant === 'error') {
            icon = figures.cross;
        }
        if (variant === 'warning') {
            icon = figures.warning;
        }
        return { icon };
    },
};
export default theme;
//# sourceMappingURL=theme.js.map
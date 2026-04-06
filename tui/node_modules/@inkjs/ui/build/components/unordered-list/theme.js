import figures from 'figures';
const theme = {
    styles: {
        list: () => ({
            flexDirection: 'column',
        }),
        listItem: () => ({
            gap: 1,
        }),
        marker: () => ({
            dimColor: true,
        }),
        content: () => ({
            flexDirection: 'column',
        }),
    },
    config: () => ({
        marker: figures.line,
    }),
};
export default theme;
//# sourceMappingURL=theme.js.map
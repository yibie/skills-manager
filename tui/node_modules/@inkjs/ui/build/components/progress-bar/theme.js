import figures from 'figures';
const theme = {
    styles: {
        container: () => ({
            flexGrow: 1,
            minWidth: 0,
        }),
        completed: () => ({
            color: 'magenta',
        }),
        remaining: () => ({
            dimColor: true,
        }),
    },
    config: () => ({
        // Character for rendering a completed bar
        completedCharacter: figures.square,
        // Character for rendering a remaining bar
        remainingCharacter: figures.squareLightShade,
    }),
};
export default theme;
//# sourceMappingURL=theme.js.map
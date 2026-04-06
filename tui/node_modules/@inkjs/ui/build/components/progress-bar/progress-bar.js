import React, { useState } from 'react';
import { Box, Text, measureElement } from 'ink';
import { useComponentTheme } from '../../theme.js';
export function ProgressBar({ value }) {
    const [width, setWidth] = useState(0);
    // eslint-disable-next-line @typescript-eslint/ban-types
    const [ref, setRef] = useState(null);
    if (ref) {
        const dimensions = measureElement(ref);
        if (dimensions.width !== width) {
            setWidth(dimensions.width);
        }
    }
    const progress = Math.min(100, Math.max(0, value));
    const complete = Math.round((progress / 100) * width);
    const remaining = width - complete;
    const { styles, config } = useComponentTheme('ProgressBar');
    return (React.createElement(Box, { ref: setRef, ...styles.container() },
        complete > 0 && (React.createElement(Text, { ...styles.completed() }, config().completedCharacter.repeat(complete))),
        remaining > 0 && (React.createElement(Text, { ...styles.remaining() }, config().remainingCharacter.repeat(remaining)))));
}
//# sourceMappingURL=progress-bar.js.map
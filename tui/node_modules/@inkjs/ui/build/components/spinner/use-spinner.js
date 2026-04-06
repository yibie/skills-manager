import { useEffect, useState } from 'react';
import spinners from 'cli-spinners';
export function useSpinner({ type = 'dots' }) {
    const [frame, setFrame] = useState(0);
    const spinner = spinners[type];
    useEffect(() => {
        const timer = setInterval(() => {
            setFrame(previousFrame => {
                const isLastFrame = previousFrame === spinner.frames.length - 1;
                return isLastFrame ? 0 : previousFrame + 1;
            });
        }, spinner.interval);
        return () => {
            clearInterval(timer);
        };
    }, [spinner]);
    return {
        frame: spinner.frames[frame] ?? '',
    };
}
//# sourceMappingURL=use-spinner.js.map
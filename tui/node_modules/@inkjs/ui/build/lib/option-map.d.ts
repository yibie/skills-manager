import { type Option } from '../types.js';
type OptionMapItem = Option & {
    previous: OptionMapItem | undefined;
    next: OptionMapItem | undefined;
    index: number;
};
export default class OptionMap extends Map<string, OptionMapItem> {
    readonly first: OptionMapItem | undefined;
    constructor(options: Option[]);
}
export {};

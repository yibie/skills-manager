import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { uninstall } from './InstallService.js';
const exec = promisify(execFile);
export async function installDiscoverSkill(entry, agents) {
    for (const agent of agents) {
        await exec('npx', [
            '-y',
            'skills',
            'add',
            `https://github.com/${entry.source}`,
            '--skill',
            entry.skillId,
            '--yes',
            '--global',
            '--agent',
            agent,
        ]);
    }
}
export async function uninstallDiscoverSkill(entry, installedSkill) {
    if (!installedSkill)
        return;
    await uninstall(installedSkill);
}

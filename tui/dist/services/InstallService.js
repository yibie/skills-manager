import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const exec = promisify(execFile);
const INSTALL_DIR = path.join(os.homedir(), '.claude', 'skills');
// mac 端 Skills Manager App 的 canonical 库;指向这里的 symlink 是受管挂载,
// TUI 不得替换或删除,否则会把受管挂载静默变成失管副本(App 冲突页要检测的分歧)。
const MANAGED_CANONICAL_ROOTS = [
    path.join(os.homedir(), '.config', 'agents', 'skills'),
    path.join(os.homedir(), '.agents', 'skills'),
];
const FALLBACK_TRASH_DIR = path.join(os.homedir(), '.skills-manager', 'trash');
const MAX_COPY_DEPTH = 32;
function ensureInstallDir() {
    if (!fs.existsSync(INSTALL_DIR)) {
        fs.mkdirSync(INSTALL_DIR, { recursive: true });
    }
}
function sourcePath(skill) {
    return skill.directoryPath ?? skill.filePath;
}
function destinationPath(skill) {
    if (skill.directoryPath)
        return path.join(INSTALL_DIR, skill.name);
    const ext = path.extname(skill.filePath) || '.md';
    return path.join(INSTALL_DIR, `${skill.name}${ext}`);
}
function lstatIfExists(target) {
    try {
        return fs.lstatSync(target);
    }
    catch {
        return null;
    }
}
function linkDestination(target) {
    try {
        const raw = fs.readlinkSync(target);
        const abs = path.isAbsolute(raw) ? raw : path.resolve(path.dirname(target), raw);
        try {
            return fs.realpathSync(abs);
        }
        catch {
            return path.normalize(abs);
        }
    }
    catch {
        return null;
    }
}
function isManagedMountLink(target) {
    const dest = linkDestination(target);
    if (!dest)
        return false;
    return MANAGED_CANONICAL_ROOTS.some(root => dest === root || dest.startsWith(root + path.sep));
}
// 真实文件/目录一律进废纸篓,永不 rm;跨卷 rename 失败时退回备用废纸篓目录。
function moveToTrash(target) {
    const roots = process.platform === 'darwin'
        ? [path.join(os.homedir(), '.Trash'), FALLBACK_TRASH_DIR]
        : [FALLBACK_TRASH_DIR];
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    let lastError;
    for (const root of roots) {
        try {
            fs.mkdirSync(root, { recursive: true });
            const dest = path.join(root, `${stamp}-${path.basename(target)}`);
            fs.renameSync(target, dest);
            return dest;
        }
        catch (error) {
            lastError = error;
        }
    }
    throw new Error(`Could not move ${target} to trash: ${String(lastError)}`);
}
// 清空安装目标:受管挂载拒绝;普通 symlink 只删链接本身;实体进废纸篓。
function clearInstallTarget(target) {
    const stat = lstatIfExists(target);
    if (!stat)
        return;
    if (stat.isSymbolicLink()) {
        if (isManagedMountLink(target)) {
            throw new Error(`${path.basename(target)} is a mount managed by the Skills Manager app. Unmount it in the app instead.`);
        }
        fs.unlinkSync(target);
        return;
    }
    moveToTrash(target);
}
function copyRecursive(src, dest, depth = 0) {
    if (depth > MAX_COPY_DEPTH) {
        throw new Error(`Skill package is nested too deeply (possible symlink cycle): ${src}`);
    }
    const stat = fs.lstatSync(src);
    if (stat.isSymbolicLink()) {
        // 复制链接本身而不跟随:循环链接不会无限递归,外部内容也不被实体化
        const raw = fs.readlinkSync(src);
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.symlinkSync(raw, dest);
        return;
    }
    if (stat.isDirectory()) {
        fs.mkdirSync(dest, { recursive: true });
        for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
            copyRecursive(path.join(src, entry.name), path.join(dest, entry.name), depth + 1);
        }
        return;
    }
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
}
async function commitAll(message) {
    const gitDir = path.join(INSTALL_DIR, '.git');
    if (!fs.existsSync(gitDir)) {
        await exec('git', ['-C', INSTALL_DIR, 'init']);
    }
    await exec('git', ['-C', INSTALL_DIR, 'add', '-A']);
    const { stdout } = await exec('git', ['-C', INSTALL_DIR, 'status', '--porcelain']);
    if (!stdout.trim())
        return;
    await exec('git', ['-C', INSTALL_DIR, 'commit', '-m', message]);
}
export async function install(skill) {
    ensureInstallDir();
    const src = sourcePath(skill);
    const dest = destinationPath(skill);
    if (!fs.existsSync(src)) {
        throw new Error(`Skill source not found: ${src}`);
    }
    clearInstallTarget(dest);
    copyRecursive(src, dest);
    try {
        await commitAll(`install: ${skill.name}`);
    }
    catch (err) {
        throw new Error(`Git tracking failed for ${skill.name}: ${String(err)}`);
    }
}
export async function uninstall(skill) {
    ensureInstallDir();
    const target = destinationPath(skill);
    const stat = lstatIfExists(target);
    if (!stat)
        return;
    if (stat.isSymbolicLink()) {
        if (isManagedMountLink(target)) {
            throw new Error(`${skill.name} is a mount managed by the Skills Manager app. Unmount it in the app instead.`);
        }
        fs.unlinkSync(target);
    }
    else {
        moveToTrash(target);
    }
    const gitDir = path.join(INSTALL_DIR, '.git');
    if (!fs.existsSync(gitDir))
        return;
    try {
        await commitAll(`uninstall: ${skill.name}`);
    }
    catch (err) {
        throw new Error(`Git tracking failed for ${skill.name}: ${String(err)}`);
    }
}

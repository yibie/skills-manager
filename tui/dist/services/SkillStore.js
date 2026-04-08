import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import matter from 'gray-matter';
const HOME = os.homedir();
const CLAUDE_SKILLS_DIR = path.join(HOME, '.claude', 'skills');
const PI_AGENT_DIR = path.join(HOME, '.pi', 'agent');
const PI_PROJECT_DIR = path.join(process.cwd(), '.pi');
const STATE_FILE = path.join(HOME, '.skills-manager', 'tui-state.json');
const PLUGIN_CACHE_ROOTS = [
    { agentId: 'claude-code', cacheDir: path.join(HOME, '.claude', 'plugins', 'cache') },
    { agentId: 'codex', cacheDir: path.join(HOME, '.codex', 'plugins', 'cache') },
];
const PI_GLOBAL_SETTINGS = path.join(PI_AGENT_DIR, 'settings.json');
const PI_PROJECT_SETTINGS = path.join(PI_PROJECT_DIR, 'settings.json');
const PI_GLOBAL_EXTENSIONS_DIR = path.join(PI_AGENT_DIR, 'extensions');
const PI_PROJECT_EXTENSIONS_DIR = path.join(PI_PROJECT_DIR, 'extensions');
const PI_GLOBAL_GIT_DIR = path.join(PI_AGENT_DIR, 'git');
const PI_PROJECT_GIT_DIR = path.join(PI_PROJECT_DIR, 'git');
const AGENT_DEFINITIONS = [
    { id: 'claude-code', label: 'Claude Code', detectPath: path.join(HOME, '.claude'), skillsDir: path.join(HOME, '.claude', 'skills') },
    { id: 'codex', label: 'Codex', detectPath: path.join(HOME, '.codex'), skillsDir: path.join(HOME, '.codex', 'skills') },
    { id: 'pi', label: 'Pi', detectPath: PI_AGENT_DIR, skillsDir: path.join(PI_AGENT_DIR, 'skills') },
    { id: 'gemini-cli', label: 'Gemini CLI', detectPath: path.join(HOME, '.gemini'), skillsDir: path.join(HOME, '.gemini', 'skills') },
    { id: 'copilot', label: 'Copilot', detectPath: path.join(HOME, '.copilot'), skillsDir: path.join(HOME, '.copilot', 'skills') },
    { id: 'roo', label: 'Roo', detectPath: path.join(HOME, '.roo'), skillsDir: path.join(HOME, '.roo', 'skills') },
    { id: 'continue', label: 'Continue', detectPath: path.join(HOME, '.continue'), skillsDir: path.join(HOME, '.continue', 'skills') },
    { id: 'augment', label: 'Augment', detectPath: path.join(HOME, '.augment'), skillsDir: path.join(HOME, '.augment', 'skills') },
    { id: 'commandcode', label: 'CommandCode', detectPath: path.join(HOME, '.commandcode'), skillsDir: path.join(HOME, '.commandcode', 'skills') },
    { id: 'hermes', label: 'Hermes', detectPath: path.join(HOME, '.hermes'), skillsDir: path.join(HOME, '.hermes', 'skills') },
    { id: 'iflow', label: 'iFlow', detectPath: path.join(HOME, '.iflow'), skillsDir: path.join(HOME, '.iflow', 'skills') },
    { id: 'kilocode', label: 'KiloCode', detectPath: path.join(HOME, '.kilocode'), skillsDir: path.join(HOME, '.kilocode', 'skills') },
    { id: 'kiro', label: 'Kiro', detectPath: path.join(HOME, '.kiro'), skillsDir: path.join(HOME, '.kiro', 'skills') },
    { id: 'mcpjam', label: 'MCPJam', detectPath: path.join(HOME, '.mcpjam'), skillsDir: path.join(HOME, '.mcpjam', 'skills') },
    { id: 'mux', label: 'Mux', detectPath: path.join(HOME, '.mux'), skillsDir: path.join(HOME, '.mux', 'skills') },
    { id: 'neovate', label: 'Neovate', detectPath: path.join(HOME, '.neovate'), skillsDir: path.join(HOME, '.neovate', 'skills') },
    { id: 'openhands', label: 'OpenHands', detectPath: path.join(HOME, '.openhands'), skillsDir: path.join(HOME, '.openhands', 'skills') },
    { id: 'openwukong', label: 'OpenWukong', detectPath: path.join(HOME, '.openwukong'), skillsDir: path.join(HOME, '.openwukong', 'skills') },
    { id: 'qwen', label: 'Qwen', detectPath: path.join(HOME, '.qwen'), skillsDir: path.join(HOME, '.qwen', 'skills') },
    { id: 'stepfun', label: 'StepFun', detectPath: path.join(HOME, '.stepfun'), skillsDir: path.join(HOME, '.stepfun', 'skills') },
];
function readState() {
    try {
        const parsed = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
        if (typeof parsed === 'object' && parsed !== null &&
            'starred' in parsed &&
            Array.isArray(parsed['starred'])) {
            return parsed;
        }
        return { starred: [] };
    }
    catch {
        return { starred: [] };
    }
}
function writeState(state) {
    try {
        const dir = path.dirname(STATE_FILE);
        if (!fs.existsSync(dir))
            fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    }
    catch {
        // Silent: star state is best-effort, never crash the TUI
    }
}
export function getInstalledAgents() {
    return AGENT_DEFINITIONS.filter(agent => {
        try {
            return fs.existsSync(agent.detectPath);
        }
        catch {
            return false;
        }
    });
}
function expandHome(p) {
    if (p === '~')
        return HOME;
    if (p.startsWith('~/'))
        return path.join(HOME, p.slice(2));
    return p;
}
/** Resolve a symlink to its real path; return original path if not a symlink. */
function resolveSymlink(p) {
    try {
        const dest = fs.readlinkSync(p);
        return dest.startsWith('/') ? dest : path.resolve(path.dirname(p), dest);
    }
    catch {
        return p;
    }
}
/** Recursively resolve symlinks until we reach a real file/directory. */
function resolveSymlinkFully(p) {
    try {
        return fs.realpathSync(p);
    }
    catch {
        return p;
    }
}
/** Return the lexicographically highest subdirectory (latest version) inside a plugin dir. */
function latestVersion(pluginDir) {
    try {
        const entries = fs.readdirSync(pluginDir, { withFileTypes: true })
            .filter(e => e.isDirectory())
            .map(e => e.name)
            .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
        return entries.length > 0 ? path.join(pluginDir, entries[entries.length - 1]) : null;
    }
    catch {
        return null;
    }
}
function parseSkillFile(filePath, starredNames, overrides = {}) {
    try {
        const raw = fs.readFileSync(filePath, 'utf8');
        const { data, content } = matter(raw);
        const name = overrides.name ?? path.basename(path.dirname(filePath));
        return {
            name,
            displayName: data['name'] ?? name,
            description: data['description'] ?? content.trimStart().slice(0, 100).trim(),
            filePath,
            source: 'local',
            resourceType: 'skill',
            compatibleAgents: data['agents'] ?? ['claude-code'],
            isStarred: starredNames.includes(name),
            isInstalled: false,
            version: data['version'],
            ...overrides,
        };
    }
    catch {
        return null;
    }
}
function inferExtensionName(filePath) {
    const base = path.basename(filePath);
    if (base === 'index.ts' || base === 'index.js') {
        return path.basename(path.dirname(filePath));
    }
    return base.replace(/\.[^.]+$/, '');
}
function inferExtensionDescription(raw, fallbackName) {
    const lines = raw.split('\n').map(line => line.trim());
    for (const line of lines.slice(0, 16)) {
        if (!line)
            continue;
        if (line.startsWith('//'))
            return line.replace(/^\/\/\s*/, '');
        if (line.startsWith('/*'))
            return line.replace(/^\/\*+\s*/, '').replace(/\*\/$/, '').trim();
        if (line.startsWith('*'))
            return line.replace(/^\*\s*/, '');
    }
    return `Pi extension: ${fallbackName}`;
}
function parseExtensionFile(filePath, starredNames, overrides = {}) {
    try {
        const raw = fs.readFileSync(filePath, 'utf8');
        const name = overrides.name ?? inferExtensionName(filePath);
        return {
            name,
            displayName: overrides.displayName ?? name,
            description: overrides.description ?? inferExtensionDescription(raw, name),
            filePath,
            source: overrides.source ?? 'local',
            resourceType: 'extension',
            compatibleAgents: overrides.compatibleAgents ?? ['pi'],
            isStarred: starredNames.includes(name),
            isInstalled: overrides.isInstalled ?? true,
            version: overrides.version,
            pluginSource: overrides.pluginSource,
            pluginName: overrides.pluginName,
            extensionScope: overrides.extensionScope ?? 'global',
            directoryPath: overrides.directoryPath,
        };
    }
    catch {
        return null;
    }
}
function scanSkillDirectory(skillsDir, starredNames, agentId) {
    if (!fs.existsSync(skillsDir))
        return [];
    const skills = [];
    for (const entry of fs.readdirSync(skillsDir, { withFileTypes: true })) {
        const entryPath = path.join(skillsDir, entry.name);
        const resolved = resolveSymlink(entryPath);
        let isDir = false;
        try {
            isDir = fs.statSync(resolved).isDirectory();
        }
        catch {
            continue;
        }
        if (isDir) {
            const skillFile = path.join(resolved, 'SKILL.md');
            if (!fs.existsSync(skillFile))
                continue;
            const skill = parseSkillFile(skillFile, starredNames, {
                name: entry.name,
                source: 'local',
                resourceType: 'skill',
                isInstalled: true,
                compatibleAgents: [agentId],
                directoryPath: resolved,
            });
            if (skill)
                skills.push(skill);
        }
        else if (entry.name.endsWith('.md')) {
            const name = entry.name.replace(/\.md$/, '');
            const skill = parseSkillFile(resolved, starredNames, {
                name,
                source: 'local',
                resourceType: 'skill',
                isInstalled: true,
                compatibleAgents: [agentId],
            });
            if (skill)
                skills.push(skill);
        }
    }
    return skills;
}
function scanPluginCacheSkills(cacheDir, starredNames, installedIds, agentId) {
    if (!fs.existsSync(cacheDir))
        return [];
    const skills = [];
    for (const pluginSourceEntry of fs.readdirSync(cacheDir, { withFileTypes: true })) {
        if (!pluginSourceEntry.isDirectory())
            continue;
        const pluginSource = pluginSourceEntry.name;
        const pluginSourceDir = path.join(cacheDir, pluginSource);
        for (const pluginEntry of fs.readdirSync(pluginSourceDir, { withFileTypes: true })) {
            if (!pluginEntry.isDirectory())
                continue;
            const pluginName = pluginEntry.name;
            const pluginDir = path.join(pluginSourceDir, pluginName);
            const versionDir = latestVersion(pluginDir);
            if (!versionDir)
                continue;
            const skillsDir = path.join(versionDir, 'skills');
            if (!fs.existsSync(skillsDir))
                continue;
            for (const skillEntry of fs.readdirSync(skillsDir, { withFileTypes: true })) {
                const skillEntryPath = path.join(skillsDir, skillEntry.name);
                const resolved = resolveSymlink(skillEntryPath);
                let isDir = false;
                try {
                    isDir = fs.statSync(resolved).isDirectory();
                }
                catch {
                    continue;
                }
                const skillName = skillEntry.name.replace(/\.md$/, '');
                const isInstalled = installedIds.has(skillName);
                if (isDir) {
                    const skillFile = path.join(resolved, 'SKILL.md');
                    if (!fs.existsSync(skillFile))
                        continue;
                    const skill = parseSkillFile(skillFile, starredNames, {
                        name: skillName,
                        source: 'plugin',
                        resourceType: 'skill',
                        pluginSource,
                        pluginName,
                        isInstalled,
                        compatibleAgents: [agentId],
                        directoryPath: resolved,
                    });
                    if (skill)
                        skills.push(skill);
                }
                else if (skillEntry.name.endsWith('.md')) {
                    const skill = parseSkillFile(resolved, starredNames, {
                        name: skillName,
                        source: 'plugin',
                        resourceType: 'skill',
                        pluginSource,
                        pluginName,
                        isInstalled,
                        compatibleAgents: [agentId],
                    });
                    if (skill)
                        skills.push(skill);
                }
            }
        }
    }
    return skills;
}
function readPiSettings(settingsPath) {
    try {
        return JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    }
    catch {
        return null;
    }
}
function resolveSettingsPath(settingsPath, rawPath) {
    const expanded = expandHome(rawPath);
    if (path.isAbsolute(expanded))
        return expanded;
    return path.resolve(path.dirname(settingsPath), expanded);
}
function scanExtensionEntrypoints(dirPath, starredNames, overrides) {
    if (!fs.existsSync(dirPath))
        return [];
    const skills = [];
    for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
        const entryPath = path.join(dirPath, entry.name);
        if (entry.isFile() && /\.(ts|js)$/.test(entry.name)) {
            const extension = parseExtensionFile(entryPath, starredNames, overrides);
            if (extension)
                skills.push(extension);
            continue;
        }
        if (entry.isDirectory()) {
            const tsIndex = path.join(entryPath, 'index.ts');
            const jsIndex = path.join(entryPath, 'index.js');
            const indexFile = fs.existsSync(tsIndex) ? tsIndex : fs.existsSync(jsIndex) ? jsIndex : null;
            if (!indexFile)
                continue;
            const extension = parseExtensionFile(indexFile, starredNames, {
                ...overrides,
                name: entry.name,
                displayName: entry.name,
            });
            if (extension)
                skills.push(extension);
        }
    }
    return skills;
}
function readPackageManifest(packageRoot) {
    try {
        return JSON.parse(fs.readFileSync(path.join(packageRoot, 'package.json'), 'utf8'));
    }
    catch {
        return null;
    }
}
function resolveManifestPaths(packageRoot, entries, conventionalDir) {
    if (Array.isArray(entries) && entries.length > 0) {
        return entries
            .filter(entry => typeof entry === 'string' && !/[!*?{}\[\]]/.test(entry))
            .map(entry => path.resolve(packageRoot, entry));
    }
    const fallback = path.join(packageRoot, conventionalDir);
    return fs.existsSync(fallback) ? [fallback] : [];
}
function collectPackageSkillFiles(rootPath) {
    const files = [];
    if (!fs.existsSync(rootPath))
        return files;
    const stat = fs.statSync(rootPath);
    if (stat.isFile()) {
        if (rootPath.endsWith('.md'))
            files.push(rootPath);
        return files;
    }
    const walk = (currentPath, allowBareMd) => {
        for (const entry of fs.readdirSync(currentPath, { withFileTypes: true })) {
            const entryPath = path.join(currentPath, entry.name);
            if (entry.isDirectory()) {
                const skillFile = path.join(entryPath, 'SKILL.md');
                if (fs.existsSync(skillFile)) {
                    files.push(skillFile);
                    continue;
                }
                walk(entryPath, false);
            }
            else if (allowBareMd && entry.name.endsWith('.md')) {
                files.push(entryPath);
            }
        }
    };
    walk(rootPath, true);
    return files;
}
function scanPiPackageRoot(packageRoot, starredNames) {
    const manifest = readPackageManifest(packageRoot);
    const packageName = manifest?.name ?? path.basename(packageRoot);
    const packageDescription = manifest?.description;
    const resources = [];
    const skillRoots = resolveManifestPaths(packageRoot, manifest?.pi?.skills, 'skills');
    for (const skillRoot of skillRoots) {
        for (const skillFile of collectPackageSkillFiles(skillRoot)) {
            const skillName = skillFile.endsWith('SKILL.md')
                ? path.basename(path.dirname(skillFile))
                : path.basename(skillFile, path.extname(skillFile));
            const skill = parseSkillFile(skillFile, starredNames, {
                name: skillName,
                source: 'plugin',
                resourceType: 'skill',
                pluginSource: 'pi-package',
                pluginName: packageName,
                isInstalled: true,
                compatibleAgents: ['pi'],
                directoryPath: skillFile.endsWith('SKILL.md') ? path.dirname(skillFile) : undefined,
            });
            if (skill)
                resources.push(skill);
        }
    }
    const extensionRoots = resolveManifestPaths(packageRoot, manifest?.pi?.extensions, 'extensions');
    for (const extensionRoot of extensionRoots) {
        const extensions = scanExtensionEntrypoints(extensionRoot, starredNames, {
            source: 'plugin',
            resourceType: 'extension',
            pluginSource: 'pi-package',
            pluginName: packageName,
            compatibleAgents: ['pi'],
            isInstalled: true,
            extensionScope: 'package',
            description: packageDescription,
        });
        resources.push(...extensions);
    }
    return resources;
}
function findPackageRoots(baseDir) {
    if (!fs.existsSync(baseDir))
        return [];
    const roots = [];
    const visited = new Set();
    const walk = (currentPath, depth) => {
        if (depth > 6)
            return;
        let entries;
        try {
            entries = fs.readdirSync(currentPath, { withFileTypes: true });
        }
        catch {
            return;
        }
        if (entries.some(entry => entry.isFile() && entry.name === 'package.json')) {
            const real = resolveSymlinkFully(currentPath);
            if (!visited.has(real)) {
                visited.add(real);
                roots.push(currentPath);
            }
            return;
        }
        for (const entry of entries) {
            if (!entry.isDirectory())
                continue;
            if (entry.name === 'node_modules' || entry.name === '.git')
                continue;
            walk(path.join(currentPath, entry.name), depth + 1);
        }
    };
    walk(baseDir, 0);
    return roots;
}
function scanPiExtensionsFromSettings(settingsPath, starredNames, scope) {
    if (!fs.existsSync(settingsPath))
        return [];
    const settings = readPiSettings(settingsPath);
    if (!settings || !Array.isArray(settings.extensions))
        return [];
    const resources = [];
    for (const entry of settings.extensions) {
        if (typeof entry !== 'string')
            continue;
        const resolvedPath = resolveSettingsPath(settingsPath, entry);
        if (!fs.existsSync(resolvedPath))
            continue;
        const stat = fs.statSync(resolvedPath);
        if (stat.isFile() && /\.(ts|js)$/.test(resolvedPath)) {
            const extension = parseExtensionFile(resolvedPath, starredNames, {
                source: 'local',
                resourceType: 'extension',
                compatibleAgents: ['pi'],
                isInstalled: true,
                extensionScope: scope,
            });
            if (extension)
                resources.push(extension);
            continue;
        }
        if (stat.isDirectory()) {
            resources.push(...scanExtensionEntrypoints(resolvedPath, starredNames, {
                source: 'local',
                resourceType: 'extension',
                compatibleAgents: ['pi'],
                isInstalled: true,
                extensionScope: scope,
            }));
        }
    }
    return resources;
}
function scanPiResources(starredNames) {
    const resources = [];
    resources.push(...scanExtensionEntrypoints(PI_GLOBAL_EXTENSIONS_DIR, starredNames, {
        source: 'local',
        resourceType: 'extension',
        compatibleAgents: ['pi'],
        isInstalled: true,
        extensionScope: 'global',
    }));
    resources.push(...scanExtensionEntrypoints(PI_PROJECT_EXTENSIONS_DIR, starredNames, {
        source: 'local',
        resourceType: 'extension',
        compatibleAgents: ['pi'],
        isInstalled: true,
        extensionScope: 'project',
    }));
    resources.push(...scanPiExtensionsFromSettings(PI_GLOBAL_SETTINGS, starredNames, 'settings'));
    resources.push(...scanPiExtensionsFromSettings(PI_PROJECT_SETTINGS, starredNames, 'settings'));
    for (const packageRoot of findPackageRoots(PI_GLOBAL_GIT_DIR)) {
        resources.push(...scanPiPackageRoot(packageRoot, starredNames));
    }
    for (const packageRoot of findPackageRoots(PI_PROJECT_GIT_DIR)) {
        resources.push(...scanPiPackageRoot(packageRoot, starredNames));
    }
    return resources;
}
function mergeSkill(target, incoming) {
    target.compatibleAgents = [...new Set([...target.compatibleAgents, ...incoming.compatibleAgents])];
    target.isInstalled = target.isInstalled || incoming.isInstalled;
    target.isStarred = target.isStarred || incoming.isStarred;
    if (target.source === 'plugin' && incoming.source === 'local') {
        target.source = incoming.source;
    }
    return target;
}
export function loadSkills() {
    const { starred } = readState();
    const installedAgents = getInstalledAgents();
    const directResources = [];
    const installedNamesByAgent = new Map();
    for (const agent of installedAgents) {
        const agentSkills = scanSkillDirectory(agent.skillsDir, starred, agent.id);
        directResources.push(...agentSkills);
        installedNamesByAgent.set(agent.id, new Set(agentSkills.map(skill => skill.name)));
    }
    if (installedAgents.some(agent => agent.id === 'pi')) {
        directResources.push(...scanPiResources(starred));
    }
    const directMap = new Map();
    for (const resource of directResources) {
        const key = `${resource.resourceType}:${resolveSymlinkFully(resource.filePath)}`;
        const existing = directMap.get(key);
        if (existing)
            mergeSkill(existing, resource);
        else
            directMap.set(key, resource);
    }
    const pluginResources = [];
    for (const { agentId, cacheDir } of PLUGIN_CACHE_ROOTS) {
        const installedIds = installedNamesByAgent.get(agentId) ?? new Set();
        pluginResources.push(...scanPluginCacheSkills(cacheDir, starred, installedIds, agentId));
    }
    const merged = new Map();
    for (const resource of [...directMap.values(), ...pluginResources]) {
        const key = `${resource.resourceType}:${resolveSymlinkFully(resource.filePath)}`;
        const existing = merged.get(key);
        if (existing)
            mergeSkill(existing, resource);
        else
            merged.set(key, resource);
    }
    return Array.from(merged.values());
}
export function toggleStar(skillName) {
    const state = readState();
    const idx = state.starred.indexOf(skillName);
    if (idx === -1) {
        state.starred.push(skillName);
    }
    else {
        state.starred.splice(idx, 1);
    }
    writeState(state);
}

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
const CACHE_DIR = path.join(os.homedir(), '.skills-manager', 'cache');
const CACHE_FILE = path.join(CACHE_DIR, 'skills-directory.json');
const CACHE_TTL_MS = 30 * 60 * 1000;
const DIRECTORY_URL = 'https://skills.sh/';
function readCache() {
    try {
        const parsed = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
        if (Date.now() - parsed.fetchedAt > CACHE_TTL_MS)
            return null;
        return parsed;
    }
    catch {
        return null;
    }
}
function writeCache(value) {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    fs.writeFileSync(CACHE_FILE, JSON.stringify(value, null, 2));
}
function decodeHtmlEntities(text) {
    return text
        .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(Number.parseInt(hex, 16)))
        .replace(/&#(\d+);/g, (_, decimal) => String.fromCodePoint(Number.parseInt(decimal, 10)))
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'")
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&nbsp;/g, ' ');
}
function stripTags(html) {
    return decodeHtmlEntities(html
        .replace(/<script[\s\S]*?<\/script>/gi, '')
        .replace(/<style[\s\S]*?<\/style>/gi, '')
        .replace(/<[^>]+>/g, ' '))
        .replace(/\s+/g, ' ')
        .trim();
}
function findBalancedSection(input, startIndex, opening, closing) {
    let depth = 0;
    for (let index = startIndex; index < input.length; index += 1) {
        const character = input[index];
        if (character === opening)
            depth += 1;
        else if (character === closing) {
            depth -= 1;
            if (depth === 0)
                return input.slice(startIndex, index + 1);
        }
    }
    return null;
}
function extractEscapedJSONArray(html, key) {
    const marker = `\\"${key}\\":`;
    const markerIndex = html.indexOf(marker);
    if (markerIndex === -1)
        return null;
    const arrayStart = html.indexOf('[', markerIndex + marker.length);
    if (arrayStart === -1)
        return null;
    return findBalancedSection(html, arrayStart, '[', ']');
}
function extractTotal(html) {
    const match = html.match(/\\"totalSkills\\":(\d+)/) ?? html.match(/"totalSkills":(\d+)/);
    if (!match?.[1])
        return null;
    return Number(match[1]);
}
function buildDiscoverEntries(payloads) {
    const seen = new Set();
    const entries = [];
    for (const payload of payloads) {
        const source = payload.source?.trim() ?? '';
        const skillId = payload.skillId?.trim() ?? '';
        if (!source || !skillId)
            continue;
        const id = `${source}:${skillId}`;
        if (seen.has(id))
            continue;
        seen.add(id);
        entries.push({
            id,
            source,
            skillId,
            name: payload.name?.trim() || skillId,
            installs: Number(payload.installs ?? 0),
            repoUrl: `https://github.com/${source}`,
            installCommand: `npx skills add https://github.com/${source} --skill ${skillId}`,
        });
    }
    return entries;
}
function parseDirectoryViaPayload(html) {
    const rawArray = extractEscapedJSONArray(html, 'initialSkills');
    if (!rawArray)
        return null;
    try {
        const payloads = JSON.parse(rawArray.replace(/\\"/g, '"'));
        const entries = buildDiscoverEntries(payloads);
        return { entries, total: extractTotal(html) ?? entries.length };
    }
    catch {
        return null;
    }
}
function parseDirectoryViaRegex(html) {
    const patterns = [
        /\{\\"source\\":\\"([^\\]+)\\",\\"skillId\\":\\"([^\\]+)\\",\\"name\\":\\"([^\\]+)\\",\\"installs\\":(\d+)\}/g,
        /\{"source":"([^"]+)","skillId":"([^"]+)","name":"([^"]+)","installs":(\d+)\}/g,
    ];
    const payloads = [];
    for (const pattern of patterns) {
        let match;
        while ((match = pattern.exec(html)) !== null) {
            payloads.push({
                source: match[1],
                skillId: match[2],
                name: match[3],
                installs: Number(match[4] ?? '0'),
            });
        }
    }
    const entries = buildDiscoverEntries(payloads);
    return { entries, total: extractTotal(html) ?? entries.length };
}
function parseDirectory(html) {
    return parseDirectoryViaPayload(html) ?? parseDirectoryViaRegex(html);
}
function extractFirstParagraph(html) {
    if (!html)
        return undefined;
    const match = html.match(/<p>([\s\S]*?)<\/p>/i);
    const text = stripTags(match?.[1] ?? '');
    return text || undefined;
}
export async function syncSkillsDirectory() {
    const res = await fetch(DIRECTORY_URL, { headers: { 'User-Agent': 'skills-manager-tui' } });
    if (!res.ok)
        throw new Error(`skills.sh fetch failed: ${res.status}`);
    const html = await res.text();
    const parsed = parseDirectory(html);
    writeCache({ fetchedAt: Date.now(), ...parsed });
    return parsed;
}
export function loadSkillsDirectory() {
    const cached = readCache();
    if (cached)
        return { entries: cached.entries, total: cached.total };
    try {
        const raw = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
        return { entries: raw.entries, total: raw.total };
    }
    catch {
        return { entries: [], total: 0 };
    }
}
export async function fetchDiscoverSkillDetail(entry) {
    const url = `https://skills.sh/${entry.source}/${entry.skillId}`;
    const res = await fetch(url, { headers: { 'User-Agent': 'skills-manager-tui' } });
    if (!res.ok)
        return entry;
    const html = await res.text();
    const installMatch = html.match(/<code[^>]*>\s*(?:<span[^>]*>\$<\/span>\s*(?:<!-- -->)?\s*)?(npx skills add https:\/\/github\.com\/[^<\s]+ --skill [^<\s]+)\s*<\/code>/i);
    const summaryBlock = html.match(/<div class="prose[^"]*">([\s\S]*?)<\/div><\/div><\/div><div class="bg-background"><div class="flex items-center[^>]*"><span>SKILL\.md<\/span>/i);
    const readmeBlock = html.match(/<span>SKILL\.md<\/span><\/div><div class="prose[^"]*">([\s\S]*?)<\/div><\/div><\/div>/i);
    return {
        ...entry,
        installCommand: installMatch?.[1] ?? entry.installCommand,
        summary: summaryBlock ? stripTags(summaryBlock[1]).slice(0, 900) : (extractFirstParagraph(readmeBlock?.[1]) ?? entry.summary),
        readmeExcerpt: readmeBlock ? stripTags(readmeBlock[1]).slice(0, 1200) : entry.readmeExcerpt,
    };
}

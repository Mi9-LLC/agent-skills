#!/usr/bin/env node
/**
 * Run a project's own quality gates (typecheck / lint / test / dead-code /
 * shell lint), parse their output, score each category 0-10, and print one
 * JSON document to stdout.
 *
 * This is the metrics ENGINE for the `health` skill: every number a health
 * narrative reports must come from here, never from model guesswork. The
 * JSON is intentionally self-describing (stable key names, booleans always
 * present) so a model can read it cold and write an accurate narrative.
 *
 * Zero npm dependencies. Tool availability is probed by hand (node:fs plus a
 * PATH/PATHEXT lookup) before anything is run: on Windows a missing binary
 * invoked under shell:true exits 9009/127, indistinguishable from "ran and
 * found problems", which would silently score an uninstalled tool instead of
 * skipping it. Every category is probed this way before it is ever spawned.
 *
 * The only disk write this script ever performs is the optional --save
 * history append; it never writes a config file and never touches git state
 * beyond reading it (repo root, branch, working-tree cleanliness).
 */

import { spawnSync } from 'node:child_process';
import { readFileSync, appendFileSync, mkdirSync, existsSync, readdirSync, statSync } from 'node:fs';
import * as nodeUtil from 'node:util';
import { resolve, join, delimiter, sep } from 'node:path';

if (typeof nodeUtil.parseArgs !== 'function') {
    console.error('Error: requires Node 18.3+ (util.parseArgs not found).');
    process.exit(1);
}
const { parseArgs } = nodeUtil;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const CATEGORY_NAMES = ['typecheck', 'lint', 'test', 'deadcode', 'shell'];

const DEFAULT_WEIGHTS = { typecheck: 25, lint: 20, test: 30, deadcode: 15, shell: 10 };

const DEFAULT_TIMEOUT_SECONDS = 300;

const DEFAULT_CONFIG_RELPATH = '.claude/health.json';
const DEFAULT_HISTORY_DIRNAME = 'docs/health';

// Config commands must be a plain executable + args so a confirmed
// .claude/health.json can never smuggle a chained shell command.
const SHELL_METACHAR_RE = /[&|;<>`\r\n]/;
const COMMAND_SUBSTITUTION_RE = /\$\(/;

// Directories a bounded shell-script walk (and the dotnet-project probe)
// never descends into.
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'build', 'coverage', 'vendor', 'target']);
const MAX_WALK_DEPTH = 6;

// The constants below logically belong with the sections further down that
// use them (detection, probing, execution, parsing) and stay documented
// there; they are declared here ONLY because `await main()` a few lines
// below reaches them almost immediately through hoisted function calls. A
// `const` is not initialized until its own declaration line actually runs
// -- unlike a `function` declaration, which hoists fully -- so one declared
// after `await main()` would throw "Cannot access before initialization"
// the moment a hoisted function tried to read it.
const ESLINT_CONFIG_NAMES = [
    'eslint.config.js', 'eslint.config.mjs', 'eslint.config.cjs', 'eslint.config.ts',
    '.eslintrc', '.eslintrc.js', '.eslintrc.cjs', '.eslintrc.json', '.eslintrc.yml', '.eslintrc.yaml',
];
const WIN32 = process.platform === 'win32';
const PM_NAMES = ['npm', 'pnpm', 'yarn', 'bun'];
const ANSI_CSI_RE = /\x1b\[[0-9;]*[A-Za-z]/g;
const MAX_TAIL_LINES = 50;
const MAX_TAIL_LINE_CHARS = 400;
const DOTNET_NEW_RE = /Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),\s*Total:\s*(\d+)/;
const DOTNET_OLD_RE = /Total tests:\s*(\d+)\.\s*Passed:\s*(\d+)\.\s*Failed:\s*(\d+)\./;
const DOTNET_DETECT_RE = /Failed:\s*\d+,\s*Passed:\s*\d+|Total tests:\s*\d+\.\s*Passed:\s*\d+\.\s*Failed:\s*\d+\./;

/**
 * detectRe sniffs raw OUTPUT (used only when the command string gave no
 * hint); parse does the real extraction. Registry keys double as parser
 * names referenced from CATEGORY_PARSERS and COMMAND_HINTS. The parseXxx
 * functions are hoisted function declarations defined later in this file,
 * so referencing them here (before their own textual definition) is safe.
 */
const PARSERS = {
    tsc: { detectRe: /error TS\d+/, parse: parseTsc },
    eslint: { detectRe: /\d+\s+problems?\s+\(\d+\s+errors?,\s+\d+\s+warnings?\)/, parse: parseEslint },
    biome: { detectRe: /Checked \d+ files?|Found \d+ (?:errors?|warnings?)\./, parse: parseBiome },
    ruff: { detectRe: /All checks passed!|Found \d+ errors?/, parse: parseRuff },
    vitest: { detectRe: /Tests\s+(?:\d+\s+failed\s*\|\s*)?\d+\s+passed/, parse: parseVitest },
    jest: { detectRe: /Tests:\s+.*total/, parse: parseJest },
    pytest: { detectRe: /\d+ (?:passed|failed) in [\d.]+s/, parse: parsePytest },
    cargo: { detectRe: /test result: (?:ok|FAILED)\./, parse: parseCargoTest },
    go: { detectRe: /^(ok|FAIL)\s+\S+/m, parse: parseGoTest },
    dotnet: { detectRe: DOTNET_DETECT_RE, parse: parseDotnetTest },
    knip: { detectRe: /^(?:Unused|Unlisted|Unresolved|Duplicate)[a-z A-Z]*\(\d+\)/m, parse: parseKnip },
    shellcheck: { detectRe: /^In .+ line \d+:/m, parse: parseShellcheck },
};

/** Category -> candidate parsers, tried in this order once no command-string hint applies. */
const CATEGORY_PARSERS = {
    typecheck: ['tsc'],
    lint: ['eslint', 'biome', 'ruff'],
    test: ['vitest', 'jest', 'pytest', 'cargo', 'go', 'dotnet'],
    deadcode: ['knip'],
    shell: ['shellcheck'],
};

/** A known tool name appearing literally in the configured command string. */
const COMMAND_HINTS = [
    { re: /\btsc\b/, parser: 'tsc' },
    { re: /\beslint\b/, parser: 'eslint' },
    { re: /\bbiome\b/, parser: 'biome' },
    { re: /\bruff\b/, parser: 'ruff' },
    { re: /\bvitest\b/, parser: 'vitest' },
    { re: /\bjest\b/, parser: 'jest' },
    { re: /\bpytest\b/, parser: 'pytest' },
    { re: /\bcargo\b/, parser: 'cargo' },
    { re: /\bgo\s+test\b/, parser: 'go' },
    { re: /\bdotnet\b/, parser: 'dotnet' },
    { re: /\bknip\b/, parser: 'knip' },
    { re: /\bshellcheck\b/, parser: 'shellcheck' },
];

/**
 * Signals an expected, user-facing failure (bad flag, bad config, bad
 * --only choice). Carried via exception rather than process.exit() so we
 * always unwind through main()'s catch and set process.exitCode -- calling
 * process.exit() while a spawned tool's pipe could still be draining risks a
 * Windows hang.
 */
class CliError extends Error {
    constructor(message, exitCode = 2) {
        super(message);
        this.exitCode = exitCode;
    }
}

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

const USAGE = 'Usage: node check-health.mjs [--detect-only] [--config <path>] [--only <cat1,cat2>] [--save [dir]] [-h|--help]';

/**
 * parseArgs has no concept of an option with an optional value, and --save
 * needs exactly that (bare --save, or --save <dir>). We pull it out of argv
 * by hand before handing the rest to parseArgs so parseArgs never sees it.
 */
function extractSaveOption(argv) {
    const idx = argv.indexOf('--save');
    if (idx === -1) {
        return { save: false, saveDir: null, rest: argv };
    }
    const rest = [...argv];
    rest.splice(idx, 1);
    let saveDir = null;
    if (rest[idx] !== undefined && !rest[idx].startsWith('-')) {
        saveDir = rest[idx];
        rest.splice(idx, 1);
    }
    return { save: true, saveDir, rest };
}

/** Wraps parseArgs so an unknown flag becomes a friendly CliError (exit 2) instead of a stack trace. */
function parseCliArgs(argv) {
    try {
        const { values } = parseArgs({
            args: argv,
            options: {
                'detect-only': { type: 'boolean', default: false },
                config: { type: 'string' },
                only: { type: 'string' },
                help: { type: 'boolean', short: 'h', default: false },
            },
            strict: true,
            allowPositionals: false,
        });
        return values;
    } catch (err) {
        throw new CliError(`${err.message}\n${USAGE}`, 2);
    }
}

const { save: doSave, saveDir, rest: argvForParse } = extractSaveOption(process.argv.slice(2));

await main();

async function main() {
    try {
        const opts = parseCliArgs(argvForParse);
        if (opts.help) {
            printHelp();
            return;
        }

        const startedAt = Date.now();
        const generatedAt = new Date();
        const { repoRoot, branch, dirtyWorkingTree, notGitRepo } = detectRepo();

        if (opts['detect-only']) {
            runDetectOnly(repoRoot);
            return;
        }

        const { categories: rawCategories, configSource, configPath } = loadConfig(repoRoot, opts.config);
        const { categories: filteredCategories, only } = applyOnlyFilter(rawCategories, opts.only);
        const packageJson = readPackageJson(repoRoot);
        const categoryDefs = buildCategoryList(filteredCategories);

        const results = [];
        for (const category of categoryDefs) {
            results.push(processCategory(repoRoot, category, packageJson));
        }

        const ranCategories = results.filter((c) => c.status === 'ran');
        const sumRunWeights = sum(ranCategories, (c) => c.weight);
        for (const c of results) {
            if (c.status === 'ran') {
                c.weightPct = sumRunWeights > 0 ? round1((c.weight / sumRunWeights) * 100) : null;
            }
        }

        const composite = sumRunWeights > 0 ? round1(sum(ranCategories, (c) => c.score * c.weight) / sumRunWeights) : null;
        const compositeLabel = composite === null ? null : labelFor(composite);
        const recommendations = buildRecommendations(ranCategories);

        const historyDir = resolve(repoRoot, saveDir ?? DEFAULT_HISTORY_DIRNAME);
        const historyFile = join(historyDir, 'history.jsonl');
        const { entries } = loadHistory(historyFile);
        const trend = buildTrend(historyFile, entries, composite, results);

        let saved = null;
        if (doSave) {
            if (ranCategories.length === 0) {
                saved = { appended: false, reason: 'no categories ran' };
            } else {
                const entry = {
                    ts: toLocalIso(generatedAt),
                    branch,
                    composite,
                    categories: Object.fromEntries(ranCategories.map((c) => [c.name, c.score])),
                    durationS: round1((Date.now() - startedAt) / 1000),
                };
                mkdirSync(historyDir, { recursive: true });
                appendFileSync(historyFile, `${JSON.stringify(entry)}\n`);
                saved = { file: historyFile, appended: true };
            }
        }

        const output = {
            schema: 'health/v1',
            generatedAt: toLocalIso(generatedAt),
            repoRoot,
            branch,
            configSource,
            configPath,
            only,
            categories: results,
            composite,
            compositeLabel,
            recommendations,
            history: trend,
            saved,
            guards: {
                noToolsDetected: ranCategories.length === 0,
                notGitRepo,
                dirtyWorkingTree,
                anyTimeout: results.some((c) => c.timedOut),
                anyParseFallback: results.some((c) => c.status === 'ran' && !c.parsed),
                firstRun: entries.length === 0,
            },
            durationS: round1((Date.now() - startedAt) / 1000),
        };

        console.log(JSON.stringify(output, null, 2));
    } catch (err) {
        if (err instanceof CliError) {
            console.error(`Error: ${err.message}`);
            process.exitCode = err.exitCode;
            return;
        }
        throw err;
    }
}

// ---------------------------------------------------------------------------
// Repo / git state
// ---------------------------------------------------------------------------

/** Every git invocation goes through here: argument array via spawnSync, never a shell string. */
function git(args) {
    const res = spawnSync('git', args, { encoding: 'utf8', shell: false });
    if (res.error || res.status !== 0) {
        return null;
    }
    return res.stdout.trim();
}

function detectRepo() {
    const repoRoot = git(['rev-parse', '--show-toplevel']);
    if (repoRoot === null) {
        return { repoRoot: process.cwd(), branch: null, dirtyWorkingTree: false, notGitRepo: true };
    }
    const branch = git(['rev-parse', '--abbrev-ref', 'HEAD']);
    const status = git(['status', '--porcelain']);
    return { repoRoot, branch, dirtyWorkingTree: status !== null && status !== '', notGitRepo: false };
}

// ---------------------------------------------------------------------------
// Small generic helpers
// ---------------------------------------------------------------------------

function round1(n) {
    return Math.round(n * 10) / 10;
}

function round2(n) {
    return Math.round(n * 100) / 100;
}

function sum(items, fn) {
    return items.reduce((total, item) => total + fn(item), 0);
}

function pad2(n) {
    return String(n).padStart(2, '0');
}

function localDateString(date) {
    return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

/** Local wall-clock string WITH an explicit UTC offset, for JSON output. */
function toLocalIso(date) {
    const offMinutes = -date.getTimezoneOffset();
    const sign = offMinutes >= 0 ? '+' : '-';
    const abs = Math.abs(offMinutes);
    const time = `${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
    return `${localDateString(date)}T${time}${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)}`;
}

function readJsonSafe(path) {
    try {
        return JSON.parse(readFileSync(path, 'utf8'));
    } catch {
        return null;
    }
}

function readTextSafe(path) {
    try {
        return readFileSync(path, 'utf8');
    } catch {
        return null;
    }
}

function readPackageJson(repoRoot) {
    return readJsonSafe(join(repoRoot, 'package.json'));
}

// ---------------------------------------------------------------------------
// Config loading + validation
// ---------------------------------------------------------------------------

/**
 * Resolves the config: an explicit --config path must exist (else CliError);
 * the default path not existing is normal and falls back to detection. All
 * failures here are friendly CliErrors, never a stack trace -- this is the
 * one file a user hand-edits, so a typo should read like a compiler error,
 * not a crash.
 */
function loadConfig(repoRoot, configArg) {
    const explicit = configArg !== undefined;
    const configPath = resolve(repoRoot, explicit ? configArg : DEFAULT_CONFIG_RELPATH);

    if (!existsSync(configPath)) {
        if (explicit) {
            throw new CliError(`Config file not found: ${configPath}`, 2);
        }
        return { categories: detectCategories(repoRoot), configSource: 'detected', configPath: null };
    }

    let raw;
    try {
        raw = readFileSync(configPath, 'utf8');
    } catch (err) {
        throw new CliError(`Could not read config file ${configPath}: ${err.message}`, 2);
    }

    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (err) {
        throw new CliError(`Config file ${configPath} is not valid JSON: ${err.message}`, 2);
    }

    return { categories: validateConfig(parsed, configPath), configSource: 'file', configPath };
}

function isPlainObject(v) {
    return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function validateConfig(parsed, configPath) {
    if (!isPlainObject(parsed) || !isPlainObject(parsed.categories)) {
        throw new CliError(`Config file ${configPath} must be a JSON object with a "categories" object.`, 2);
    }

    const result = {};
    for (const [name, def] of Object.entries(parsed.categories)) {
        if (!CATEGORY_NAMES.includes(name)) {
            throw new CliError(
                `Config file ${configPath} has unknown category "${name}". Valid categories: ${CATEGORY_NAMES.join(', ')}.`,
                2,
            );
        }
        if (!isPlainObject(def)) {
            throw new CliError(`Config file ${configPath}: category "${name}" must be an object with "command" and "weight".`, 2);
        }

        const { command, weight, timeoutSeconds } = def;
        if (typeof command !== 'string' || command.trim() === '') {
            throw new CliError(`Config file ${configPath}: category "${name}" must have a non-empty string "command".`, 2);
        }
        if (SHELL_METACHAR_RE.test(command) || COMMAND_SUBSTITUTION_RE.test(command)) {
            throw new CliError(
                `Config file ${configPath}: category "${name}" command must be a plain executable and arguments ` +
                    '(no shell operators such as &, |, ;, <, >, backticks, or $(...)).',
                2,
            );
        }
        if (typeof weight !== 'number' || !Number.isFinite(weight) || weight <= 0) {
            throw new CliError(`Config file ${configPath}: category "${name}" must have a numeric "weight" greater than 0.`, 2);
        }

        let timeout = DEFAULT_TIMEOUT_SECONDS;
        if (timeoutSeconds !== undefined) {
            if (typeof timeoutSeconds !== 'number' || !Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
                throw new CliError(
                    `Config file ${configPath}: category "${name}" has an invalid "timeoutSeconds" (must be a number > 0).`,
                    2,
                );
            }
            timeout = timeoutSeconds;
        }

        result[name] = { command: command.trim(), weight, timeoutSeconds: timeout };
    }
    return result;
}

/**
 * --only is validated against the categories that actually made it into the
 * resolved config (file or detected) -- not just the five known names -- so
 * "not present in this project's config" and "not a real category" produce
 * the same clear error naming what IS available.
 */
function applyOnlyFilter(categories, onlyArg) {
    if (onlyArg === undefined) {
        return { categories, only: null };
    }
    const requested = onlyArg.split(',').map((s) => s.trim()).filter(Boolean);
    const validNames = Object.keys(categories);
    for (const name of requested) {
        if (!validNames.includes(name)) {
            const choices = validNames.length > 0 ? validNames.join(', ') : '(none configured)';
            throw new CliError(`Unknown --only category "${name}". Valid choices: ${choices}.`, 2);
        }
    }
    const filtered = {};
    for (const name of requested) {
        filtered[name] = categories[name];
    }
    return { categories: filtered, only: requested };
}

function buildCategoryList(categories) {
    return Object.entries(categories).map(([name, def]) => ({
        name,
        command: def.command,
        weight: def.weight,
        timeoutSeconds: def.timeoutSeconds ?? DEFAULT_TIMEOUT_SECONDS,
    }));
}

// ---------------------------------------------------------------------------
// Detection (used for --detect-only and config-less runs)
// ---------------------------------------------------------------------------

function detectPmRunPrefix(repoRoot, packageJson) {
    if (existsSync(join(repoRoot, 'package-lock.json'))) return 'npm run';
    if (existsSync(join(repoRoot, 'pnpm-lock.yaml'))) return 'pnpm run';
    if (existsSync(join(repoRoot, 'yarn.lock'))) return 'yarn run';
    if (existsSync(join(repoRoot, 'bun.lockb')) || existsSync(join(repoRoot, 'bun.lock'))) return 'bun run';
    if (packageJson) return 'npm run';
    return null;
}

function detectTypecheck(repoRoot, packageJson, pmPrefix) {
    if (packageJson?.scripts?.typecheck !== undefined) {
        return { command: `${pmPrefix ?? 'npm run'} typecheck` };
    }
    if (existsSync(join(repoRoot, 'tsconfig.json'))) {
        return { command: 'npx tsc --noEmit' };
    }
    return null;
}

function hasEslintConfig(repoRoot) {
    return ESLINT_CONFIG_NAMES.some((name) => existsSync(join(repoRoot, name)));
}

function pyprojectMentions(repoRoot, re) {
    const raw = readTextSafe(join(repoRoot, 'pyproject.toml'));
    return raw !== null && re.test(raw);
}

function detectLint(repoRoot, packageJson, pmPrefix) {
    if (packageJson?.scripts?.lint !== undefined) {
        return { command: `${pmPrefix ?? 'npm run'} lint` };
    }
    if (existsSync(join(repoRoot, 'biome.json')) || existsSync(join(repoRoot, 'biome.jsonc'))) {
        return { command: 'npx biome check .' };
    }
    if (hasEslintConfig(repoRoot)) {
        return { command: 'npx eslint .' };
    }
    if (pyprojectMentions(repoRoot, /\[tool\.ruff\]|\bruff\b/)) {
        return { command: 'ruff check .' };
    }
    return null;
}

function hasPytestConfig(repoRoot) {
    if (pyprojectMentions(repoRoot, /\bpytest\b/)) {
        return true;
    }
    if (existsSync(join(repoRoot, 'pytest.ini'))) {
        return true;
    }
    const setupCfg = readTextSafe(join(repoRoot, 'setup.cfg'));
    return setupCfg !== null && /\[tool:pytest]/.test(setupCfg);
}

function safeReadDir(dir) {
    try {
        return readdirSync(dir);
    } catch {
        return [];
    }
}

function isDirectorySafe(p) {
    try {
        return statSync(p).isDirectory();
    } catch {
        return false;
    }
}

/** *.sln or *.csproj at repoRoot, or exactly one directory below it. */
function hasDotnetProject(repoRoot) {
    const dotnetRe = /\.(sln|csproj)$/i;
    if (safeReadDir(repoRoot).some((name) => dotnetRe.test(name))) {
        return true;
    }
    for (const entry of safeReadDir(repoRoot)) {
        const full = join(repoRoot, entry);
        if (!SKIP_DIRS.has(entry) && isDirectorySafe(full) && safeReadDir(full).some((name) => dotnetRe.test(name))) {
            return true;
        }
    }
    return false;
}

function detectTest(repoRoot, packageJson, pmPrefix) {
    const testScript = packageJson?.scripts?.test;
    if (testScript !== undefined && !/no test specified/i.test(testScript)) {
        return { command: `${pmPrefix ?? 'npm run'} test` };
    }
    if (hasPytestConfig(repoRoot)) {
        return { command: 'pytest' };
    }
    if (existsSync(join(repoRoot, 'Cargo.toml'))) {
        return { command: 'cargo test' };
    }
    if (existsSync(join(repoRoot, 'go.mod'))) {
        return { command: 'go test ./...' };
    }
    if (hasDotnetProject(repoRoot)) {
        return { command: 'dotnet test' };
    }
    return null;
}

function detectDeadcode(repoRoot, packageJson) {
    const hasKnipDep = Boolean(packageJson?.devDependencies?.knip || packageJson?.dependencies?.knip);
    const hasKnipConfig = ['knip.json', 'knip.jsonc', '.knip.json'].some((name) => existsSync(join(repoRoot, name)));
    if (hasKnipDep || hasKnipConfig) {
        return { command: 'npx knip' };
    }
    return null;
}

/** Bounded recursive walk (max depth 6) collecting *.sh files as repo-relative POSIX paths. */
function findShellScripts(repoRoot) {
    const found = [];
    walkForShellScripts(repoRoot, repoRoot, 0, found);
    return found;
}

function walkForShellScripts(repoRoot, dir, depth, found) {
    if (depth > MAX_WALK_DEPTH) {
        return;
    }
    for (const entry of safeReadDir(dir)) {
        if (SKIP_DIRS.has(entry)) {
            continue;
        }
        const full = join(dir, entry);
        if (isDirectorySafe(full)) {
            walkForShellScripts(repoRoot, full, depth + 1, found);
        } else if (entry.endsWith('.sh')) {
            found.push(full.slice(repoRoot.length + 1).split(sep).join('/'));
        }
    }
}

function detectShell(repoRoot) {
    if (!resolveExecutable(repoRoot, 'shellcheck')) {
        return null;
    }
    const files = findShellScripts(repoRoot);
    if (files.length === 0) {
        return null;
    }
    const quoted = files.map((f) => (f.includes(' ') ? `"${f}"` : f));
    return { command: `shellcheck ${quoted.join(' ')}` };
}

/**
 * Every proposal is re-checked against resolveCommandAvailability so only
 * actually-runnable commands are ever proposed -- the same guarantee a
 * pre-run probe gives a configured category. Nothing detected at all is a
 * valid, honest result: an empty categories object.
 */
function detectCategories(repoRoot) {
    const packageJson = readPackageJson(repoRoot);
    const pmPrefix = detectPmRunPrefix(repoRoot, packageJson);

    const proposals = {
        typecheck: detectTypecheck(repoRoot, packageJson, pmPrefix),
        lint: detectLint(repoRoot, packageJson, pmPrefix),
        test: detectTest(repoRoot, packageJson, pmPrefix),
        deadcode: detectDeadcode(repoRoot, packageJson),
        shell: detectShell(repoRoot),
    };

    const categories = {};
    for (const name of CATEGORY_NAMES) {
        const proposal = proposals[name];
        if (!proposal) {
            continue;
        }
        if (resolveCommandAvailability(repoRoot, proposal.command, packageJson).available) {
            categories[name] = { command: proposal.command, weight: DEFAULT_WEIGHTS[name] };
        }
    }
    return categories;
}

function runDetectOnly(repoRoot) {
    const categories = detectCategories(repoRoot);
    for (const name of CATEGORY_NAMES) {
        console.error(categories[name] ? `${name}: detected -- ${categories[name].command}` : `${name}: not detected`);
    }
    console.log(JSON.stringify({ categories }, null, 2));
}

// ---------------------------------------------------------------------------
// Command availability probing (shared by detection and pre-run checks)
//
// A missing tool must become status:"skipped" here, BEFORE anything is
// spawned -- on Windows a missing binary run under shell:true exits with
// 9009/127, indistinguishable from "ran and found errors", which would
// silently score an uninstalled tool instead of skipping it. Skipped is
// never scored; it is a different outcome from failed.
// ---------------------------------------------------------------------------

function lookupDirs(repoRoot) {
    const dirs = [join(repoRoot, 'node_modules', '.bin')];
    const pathEnv = process.env.PATH ?? process.env.Path ?? '';
    for (const dir of pathEnv.split(delimiter)) {
        if (dir) {
            dirs.push(dir);
        }
    }
    return dirs;
}

function existsFile(p) {
    try {
        return statSync(p).isFile();
    } catch {
        return false;
    }
}

/**
 * Resolve a bare command name against node_modules/.bin then PATH. Windows
 * filesystems are case-insensitive by default, so no manual casing logic is
 * needed for either the name or its PATHEXT suffix.
 */
function resolveExecutable(repoRoot, name) {
    const dirs = lookupDirs(repoRoot);
    if (WIN32) {
        const pathext = (process.env.PATHEXT ?? '.COM;.EXE;.BAT;.CMD').split(';').filter(Boolean);
        const suffixes = ['', ...pathext, '.ps1'];
        return dirs.some((dir) => suffixes.some((suffix) => existsFile(join(dir, `${name}${suffix}`))));
    }
    return dirs.some((dir) => existsFile(join(dir, name)));
}

/**
 * Decide whether a category's command can actually run, WITHOUT running it.
 * Returns { available, reason }; reason is null when available.
 */
function resolveCommandAvailability(repoRoot, command, packageJson) {
    const tokens = command.split(/\s+/).filter(Boolean);
    const [first, ...restTokens] = tokens;

    if (first === 'npx') {
        if (!resolveExecutable(repoRoot, 'npx')) {
            return { available: false, reason: 'command not found: npx' };
        }
        const target = restTokens.find((t) => !t.startsWith('-'));
        if (!target || !resolveExecutable(repoRoot, target)) {
            return { available: false, reason: `command not found: ${target ?? 'npx'}` };
        }
        return { available: true, reason: null };
    }

    if (PM_NAMES.includes(first)) {
        if (!resolveExecutable(repoRoot, first)) {
            return { available: false, reason: `command not found: ${first}` };
        }
        const runIdx = restTokens.indexOf('run');
        const script = runIdx !== -1 ? restTokens[runIdx + 1] : restTokens[0];
        if (!script || !packageJson?.scripts || !(script in packageJson.scripts)) {
            return { available: false, reason: `npm script not found: ${script ?? '(none)'}` };
        }
        return { available: true, reason: null };
    }

    if (!resolveExecutable(repoRoot, first)) {
        return { available: false, reason: `command not found: ${first}` };
    }
    return { available: true, reason: null };
}

// ---------------------------------------------------------------------------
// Execution (only for categories that passed the probe)
// ---------------------------------------------------------------------------

function stripAnsi(s) {
    return s.replace(ANSI_CSI_RE, '');
}

function computeOutputTail(strippedOutput) {
    return strippedOutput
        .split('\n')
        .slice(-MAX_TAIL_LINES)
        .map((line) => (line.length > MAX_TAIL_LINE_CHARS ? line.slice(0, MAX_TAIL_LINE_CHARS) : line));
}

/**
 * On Windows process.env's real key is usually `Path`; assigning a second
 * `PATH` property alongside it would hand the child two case-colliding
 * entries with undefined precedence, so the node_modules/.bin prepend reuses
 * whatever PATH-cased key already exists. CI=1 forces test runners into
 * single-run mode (no watch, no snapshot rewrites); FORCE_COLOR/NO_COLOR
 * keep output parseable.
 */
function childEnv(nodeModulesBin) {
    const env = { ...process.env, FORCE_COLOR: '0', NO_COLOR: '1', CI: '1' };
    const pathKey = Object.keys(env).find((k) => k.toUpperCase() === 'PATH') ?? 'PATH';
    env[pathKey] = `${nodeModulesBin}${delimiter}${env[pathKey] ?? ''}`;
    return env;
}

/**
 * Sequential by design: tools share caches/lockfiles (e.g. two test runners
 * writing the same coverage dir), so categories are never run in parallel.
 */
function runCategory(repoRoot, category) {
    const startedAt = Date.now();
    const nodeModulesBin = join(repoRoot, 'node_modules', '.bin');

    const res = spawnSync(category.command, {
        // Kept ONLY because Windows .cmd shims (npm/npx/pnpm/yarn) cannot be
        // spawned directly since Node's EINVAL hardening; safe given the
        // availability probe plus the command-shape validation in
        // validateConfig (no shell operators, no $(...)).
        shell: true,
        cwd: repoRoot,
        timeout: category.timeoutSeconds * 1000,
        encoding: 'utf8',
        maxBuffer: 64 * 1024 * 1024,
        stdio: ['ignore', 'pipe', 'pipe'],
        windowsHide: true,
        env: childEnv(nodeModulesBin),
    });

    const durationS = round1((Date.now() - startedAt) / 1000);
    // Concatenated in JS, never via a `2>&1` on the command string -- cmd.exe
    // does not share sh's redirection syntax.
    const output = (res.stdout ?? '') + (res.stderr ? `\n${res.stderr}` : '');

    // ENOBUFS must be classified BEFORE the signal check: spawnSync kills a
    // child that overflows maxBuffer with SIGTERM too, so signal-first would
    // misreport a buffer overflow as a hung gate (timedOut / anyTimeout).
    if (res.error?.code === 'ENOBUFS') {
        return { durationS, timedOut: false, outputTruncated: true, exitCode: null, output };
    }
    if (res.signal !== null || res.error?.code === 'ETIMEDOUT') {
        return { durationS, timedOut: true, outputTruncated: false, exitCode: null, output };
    }
    return { durationS, timedOut: false, outputTruncated: false, exitCode: res.status, output };
}

// ---------------------------------------------------------------------------
// Parsers -- the parser drives the score; exit code is ONLY the fallback.
//
// eslint/biome exit 0 on warnings-only runs; exit-code scoring would grade a
// warny run 10 instead of its real band. Whenever a parser matches, its
// counts feed the rubric regardless of exit status.
// ---------------------------------------------------------------------------

function sumMatches(matches) {
    return matches.reduce((total, m) => total + parseInt(m[1], 10), 0);
}

function parseTsc(output) {
    return { errors: (output.match(/error TS\d+/g) ?? []).length };
}

function parseEslint(output) {
    const m = /[✖x]?\s*(\d+)\s+problems?\s+\((\d+)\s+errors?,\s+(\d+)\s+warnings?\)/.exec(output);
    if (m) {
        return { problems: parseInt(m[1], 10), errors: parseInt(m[2], 10), warnings: parseInt(m[3], 10) };
    }
    // Only reachable for a hinted eslint whose output was blank (tryParse
    // rejects non-blank unrecognized output first): a clean run prints
    // nothing at all, so zero findings is the right reading.
    return { problems: 0, errors: 0, warnings: 0 };
}

function parseBiome(output) {
    const errors = sumMatches([...output.matchAll(/Found (\d+) errors?\./g)]);
    const warnings = sumMatches([...output.matchAll(/Found (\d+) warnings?\./g)]);
    return { errors, warnings };
}

function parseRuff(output) {
    if (/All checks passed!/.test(output)) {
        return { errors: 0 };
    }
    const m = /Found (\d+) errors?/.exec(output);
    return { errors: m ? parseInt(m[1], 10) : 0 };
}

function parseVitest(output) {
    // The trailing (?:\|\s*\d+\s+\w+)* tolerates any "| N skipped"/"| N todo"
    // segments vitest appends between the passed count and the total.
    const m = /Tests\s+(?:(\d+)\s+failed\s*\|\s*)?(\d+)\s+passed(?:\s*\|\s*\d+\s+\w+)*\s*\((\d+)\)/.exec(output);
    if (!m) {
        return null;
    }
    return { failed: m[1] ? parseInt(m[1], 10) : 0, passed: parseInt(m[2], 10), total: parseInt(m[3], 10) };
}

function parseJest(output) {
    const m = /Tests:\s+(?:(\d+)\s+failed,\s*)?(?:\d+\s+skipped,\s*)?(?:(\d+)\s+passed,\s*)?(\d+)\s+total/.exec(output);
    if (!m) {
        return null;
    }
    return { failed: m[1] ? parseInt(m[1], 10) : 0, passed: m[2] ? parseInt(m[2], 10) : 0, total: parseInt(m[3], 10) };
}

/** Final pytest summary line, e.g. "2 failed, 8 passed, 1 error in 3.14s". */
function parsePytest(output) {
    const lines = output.split('\n');
    const summaryLine = [...lines].reverse().find((l) => /in [\d.]+s/.test(l) && /passed|failed|error/i.test(l));
    if (!summaryLine) {
        return null;
    }
    const failedM = /(\d+) failed/.exec(summaryLine);
    const passedM = /(\d+) passed/.exec(summaryLine);
    const errorsM = /(\d+) errors?/.exec(summaryLine);
    const failed = (failedM ? parseInt(failedM[1], 10) : 0) + (errorsM ? parseInt(errorsM[1], 10) : 0);
    const passed = passedM ? parseInt(passedM[1], 10) : 0;
    return { failed, passed, total: failed + passed };
}

/** Sums every `test result: ok|FAILED. N passed; M failed;` line, one per test binary. */
function parseCargoTest(output) {
    const matches = [...output.matchAll(/test result: (?:ok|FAILED)\.\s+(\d+) passed;\s+(\d+) failed;/g)];
    if (matches.length === 0) {
        return null;
    }
    let passed = 0;
    let failed = 0;
    for (const m of matches) {
        passed += parseInt(m[1], 10);
        failed += parseInt(m[2], 10);
    }
    return { passed, failed, total: passed + failed };
}

/** passed is only countable in verbose (-v) output; non-verbose leaves total unknown. */
function parseGoTest(output) {
    if (!/^(ok|FAIL)\s+\S+/m.test(output)) {
        return null;
    }
    const failed = (output.match(/^--- FAIL:/gm) ?? []).length;
    const passed = (output.match(/^--- PASS:/gm) ?? []).length;
    const result = { failed, passed };
    if (passed > 0) {
        result.total = failed + passed;
    }
    return result;
}

function parseDotnetTest(output) {
    const m1 = DOTNET_NEW_RE.exec(output);
    if (m1) {
        return { failed: parseInt(m1[1], 10), passed: parseInt(m1[2], 10), skipped: parseInt(m1[3], 10), total: parseInt(m1[4], 10) };
    }
    const m2 = DOTNET_OLD_RE.exec(output);
    if (m2) {
        return { total: parseInt(m2[1], 10), passed: parseInt(m2[2], 10), failed: parseInt(m2[3], 10) };
    }
    return null;
}

function parseKnip(output) {
    const matches = [...output.matchAll(/^(?:Unused|Unlisted|Unresolved|Duplicate)[a-z A-Z]*\((\d+)\)/gm)];
    return matches.length === 0 ? null : { findings: sumMatches(matches) };
}

function parseShellcheck(output) {
    return { findings: (output.match(/^In .+ line \d+:/gm) ?? []).length };
}

function countsToFindings(name, counts) {
    switch (name) {
        case 'tsc':
            return counts.errors;
        case 'eslint':
            return counts.problems;
        case 'biome':
            return counts.errors + counts.warnings;
        case 'ruff':
            return counts.errors;
        case 'knip':
        case 'shellcheck':
            return counts.findings;
        default:
            return counts.failed ?? 0; // test-family: vitest/jest/pytest/cargo/go/dotnet
    }
}

/**
 * hinted=true (the command string named the tool): a BLANK output may still
 * parse -- a clean run of eslint/tsc/shellcheck prints nothing at all, so
 * the hint is the only signal that zero findings is the right reading. But
 * NON-blank output the detect-regex does not recognize means a different
 * formatter/reporter is in play (eslint -f json, a custom test reporter):
 * claim nothing and let exit-code fallback plus the anyParseFallback guard
 * take over rather than mistaking hidden findings for a clean run.
 * hinted=false: only attempt the parser when its own detect-regex matches
 * the output, so an unrelated tool's incidental text can't be mistaken for it.
 */
function tryParse(name, output, hinted) {
    const def = PARSERS[name];
    if (!def.detectRe.test(output)) {
        if (!hinted || output.trim() !== '') {
            return null;
        }
    }
    const counts = def.parse(output);
    if (counts === null) {
        return null;
    }
    return { parsed: true, parser: name, counts, findings: countsToFindings(name, counts) };
}

function parseOutput(category, output) {
    const candidateNames = CATEGORY_PARSERS[category.name] ?? [];
    const hint = COMMAND_HINTS.find((h) => h.re.test(category.command) && candidateNames.includes(h.parser));

    if (hint) {
        const result = tryParse(hint.parser, output, true);
        if (result) {
            return result;
        }
    }
    for (const name of candidateNames) {
        if (hint && name === hint.parser) {
            continue;
        }
        const result = tryParse(name, output, false);
        if (result) {
            return result;
        }
    }
    return { parsed: false, parser: null, counts: {}, findings: null };
}

// ---------------------------------------------------------------------------
// Scoring rubric
// ---------------------------------------------------------------------------

/** 0 findings -> 10; below lo -> 7; below hi -> 4; at or above hi -> 0. */
function bandScore(count, lo, hi) {
    if (count === 0) return 10;
    if (count < lo) return 7;
    if (count < hi) return 4;
    return 0;
}

/** shellcheck findings never zero out the score -- it floors at 4, unlike the other count-based bands. */
function scoreShell(findings) {
    if (findings === 0) return 10;
    if (findings < 5) return 7;
    return 4;
}

/**
 * passRate uses the parser's own `passed`/`total`, never total-minus-failed
 * -- skipped tests can make those differ (e.g. vitest's "2 failed | 18
 * passed | 3 skipped (23)" has passed+failed = 20, not the total of 23).
 */
function scoreTest(counts) {
    const failed = counts.failed ?? 0;
    if (failed === 0) {
        return 10;
    }
    const total = counts.total;
    if (!total) {
        return 4; // failed > 0 but total unknown (e.g. go test without -v)
    }
    const passRate = ((counts.passed ?? 0) / total) * 100;
    if (passRate > 95) return 7;
    if (passRate > 80) return 4;
    return 0;
}

function scoreCategory(categoryName, findings, counts) {
    switch (categoryName) {
        case 'typecheck':
            return bandScore(findings, 10, 50);
        case 'lint':
            return bandScore(findings, 5, 20);
        case 'deadcode':
            return bandScore(findings, 5, 20);
        case 'shell':
            return scoreShell(findings);
        case 'test':
            return scoreTest(counts);
        default:
            return 4;
    }
}

function labelFor(score) {
    if (score >= 10) return 'CLEAN';
    if (score >= 7) return 'WARNING';
    if (score >= 4) return 'NEEDS WORK';
    return 'CRITICAL';
}

/**
 * A parsed test result whose total is a definite 0 (not "unknown") means the
 * parser matched noise rather than a real test run -- e.g. a header line
 * with no tests underneath. Treat it as unparsed so exit-code fallback
 * scoring takes over instead of reporting a false-clean 10.
 */
function isDegenerateTestParse(categoryName, counts) {
    return categoryName === 'test' && counts.total === 0;
}

// ---------------------------------------------------------------------------
// Per-category orchestration
// ---------------------------------------------------------------------------

function skippedCategoryResult(category, skippedReason) {
    return {
        name: category.name,
        command: category.command,
        weight: category.weight,
        weightPct: null,
        status: 'skipped',
        skippedReason,
        exitCode: null,
        timedOut: false,
        durationS: 0,
        parsed: false,
        parser: null,
        findings: null,
        counts: {},
        score: null,
        label: null,
        outputTail: [],
        outputTruncated: false,
    };
}

function processCategory(repoRoot, category, packageJson) {
    const skippedReason = resolveCommandAvailability(repoRoot, category.command, packageJson).reason;
    if (skippedReason) {
        return skippedCategoryResult(category, skippedReason);
    }

    const runResult = runCategory(repoRoot, category);
    const stripped = stripAnsi(runResult.output);
    const outputTail = computeOutputTail(stripped);

    let score;
    let parseResult = { parsed: false, parser: null, counts: {}, findings: null };

    if (runResult.timedOut) {
        score = 0;
    } else {
        parseResult = parseOutput(category, stripped);
        if (parseResult.parsed && isDegenerateTestParse(category.name, parseResult.counts)) {
            parseResult = { parsed: false, parser: null, counts: {}, findings: null };
        }
        // A parse claiming ZERO findings cannot explain a nonzero exit (an
        // eslint config crash prints no problems line; a test runner can fail
        // in teardown after every test passed). Trust the contradiction, not
        // the parse: fall back to exit-code scoring so a crashed gate can
        // never read as a clean 10.
        if (parseResult.parsed && runResult.exitCode !== 0) {
            const zeroFindings = category.name === 'test'
                ? (parseResult.counts.failed ?? 0) === 0
                : parseResult.findings === 0;
            if (zeroFindings) {
                parseResult = { parsed: false, parser: null, counts: {}, findings: null };
            }
        }
        if (parseResult.parsed) {
            score = scoreCategory(category.name, parseResult.findings, parseResult.counts);
        } else {
            score = runResult.exitCode === 0 ? 10 : 4;
        }
    }

    return {
        name: category.name,
        command: category.command,
        weight: category.weight,
        weightPct: null, // filled in once the sum of RUN weights is known
        status: 'ran',
        skippedReason: null,
        exitCode: runResult.exitCode,
        timedOut: runResult.timedOut,
        durationS: runResult.durationS,
        parsed: parseResult.parsed,
        parser: parseResult.parser,
        findings: parseResult.findings,
        counts: parseResult.counts,
        score,
        label: labelFor(score),
        outputTail,
        outputTruncated: runResult.outputTruncated,
    };
}

// ---------------------------------------------------------------------------
// Recommendations
// ---------------------------------------------------------------------------

function buildRecommendations(ranCategories) {
    return ranCategories
        .filter((c) => c.score < 10)
        .map((c) => {
            const impact = round2((c.weightPct / 100) * (10 - c.score));
            const priority = impact >= 1.0 ? 'HIGH' : impact >= 0.4 ? 'MED' : 'LOW';
            return { category: c.name, score: c.score, weightPct: c.weightPct, impact, priority };
        })
        .sort((a, b) => b.impact - a.impact);
}

// ---------------------------------------------------------------------------
// History / trend
// ---------------------------------------------------------------------------

/** History is read for the trend on every run, whether or not --save was passed; unparsable lines are skipped silently. */
function loadHistory(historyFile) {
    const raw = readTextSafe(historyFile);
    if (raw === null) {
        return { entries: [] };
    }
    const entries = [];
    for (const line of raw.split('\n')) {
        const trimmed = line.trim();
        if (!trimmed) {
            continue;
        }
        try {
            entries.push(JSON.parse(trimmed));
        } catch {
            // skip unparsable lines silently
        }
    }
    return { entries };
}

function buildTrend(historyFile, entries, currentComposite, currentCategories) {
    if (entries.length === 0) {
        return null;
    }
    const prev = entries[entries.length - 1];
    const prevComposite = typeof prev.composite === 'number' ? prev.composite : null;
    const delta = currentComposite !== null && prevComposite !== null ? round1(currentComposite - prevComposite) : null;
    const direction = delta === null ? null : delta > 0 ? 'improving' : delta < 0 ? 'slipping' : 'flat';

    const regressions = [];
    if (isPlainObject(prev.categories)) {
        for (const c of currentCategories) {
            const prevScore = prev.categories[c.name];
            if (typeof prevScore === 'number' && typeof c.score === 'number' && prevScore > c.score) {
                regressions.push({ category: c.name, prev: prevScore, now: c.score });
            }
        }
    }

    const last10 = entries.slice(-10).map((e) => ({ ts: e.ts, composite: e.composite }));
    return { file: historyFile, entries: entries.length, prev, delta, direction, regressions, last10 };
}

// ---------------------------------------------------------------------------
// Help
// ---------------------------------------------------------------------------

function printHelp() {
    console.log(`Run this project's quality gates and print a scored health report as JSON.

${USAGE}

Options:
  --detect-only     Probe the project and print the proposed .claude/health.json
                    config to stdout, with one human-readable note per category
                    on stderr. Runs no tools.
  --config <path>   Config file path (default: <repoRoot>/.claude/health.json).
                    An explicitly passed path that does not exist is an error;
                    the default path not existing just falls back to detection.
  --only <list>     Comma-separated subset of category names to run (typecheck,
                    lint, test, deadcode, shell). Categories left out are
                    omitted from the report entirely, not marked skipped.
  --save [dir]      Append one JSONL line to <dir>/history.jsonl (default:
                    <repoRoot>/docs/health/) after the run. History is read for
                    the trend on every run regardless of --save.
  -h, --help        Show this help.

Examples:
  # Detect this project's gates and run them all
  node check-health.mjs

  # See what would be detected without running anything
  node check-health.mjs --detect-only

  # Run only typecheck and lint, using a specific config
  node check-health.mjs --config .claude/health.json --only typecheck,lint

  # Run everything and record a snapshot for trend tracking
  node check-health.mjs --save
`);
}

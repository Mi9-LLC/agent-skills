#!/usr/bin/env node
/**
 * Compute engineering-retrospective metrics from git history and print a
 * single pretty-printed JSON document to stdout.
 *
 * This is the metrics ENGINE for the `retro` skill: every number a retro
 * narrative reports must come from here, never from model guesswork. The
 * JSON is intentionally self-describing (stable key names, booleans always
 * present) so a model can read it cold and write an accurate narrative.
 *
 * Zero npm dependencies: git is invoked via execFileSync with an argument
 * array (never a shell string), so it behaves identically on Windows,
 * macOS and Linux and never risks shell-interpolation of a commit subject.
 *
 * Everything here is read-only against git state except for one thing:
 * --save writes the computed JSON to a snapshot file. There is no other
 * disk write and no other network call; --no-fetch skips the one there is.
 */

import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { resolve, join } from 'node:path';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// A busy repo's full-history log can be tens of MB of text.
const GIT_MAX_BUFFER = 256 * 1024 * 1024;

const SESSION_GAP_MINUTES = 45;
const DEEP_SESSION_MIN = 50;
const MEDIUM_SESSION_MIN = 20;

// A path counts as "test" for testVsProd / hotspots / focus purposes.
const TEST_PATH_RE = /(^|\/)(tests?|__tests__|spec)\/|\.(test|spec)\./;

// Conventional-commit prefix; anything else buckets into "other".
const COMMIT_TYPE_RE = /^(feat|fix|refactor|test|chore|docs|style|perf|build|ci|revert)(\(.+?\))?!?:/;
const COMMIT_TYPES = ['feat', 'fix', 'refactor', 'test', 'chore', 'docs', 'style', 'perf', 'build', 'ci', 'revert', 'other'];

// GitHub/GitLab PR or MR reference: #123 or !123.
const PR_REF_RE = /[#!]\d+/;
// GitHub's default squash-merge subject convention: "Title (#123)".
const SQUASH_PR_RE = /\(#\d+\)/;

// Co-Authored-By trailer values that mark a commit as AI-assisted.
const AI_CO_AUTHOR_RE = /anthropic|claude|copilot|openclaw|github-actions|\[bot\]/i;

// Cap on `git diff --shortstat <merge>^1..<merge>` calls for PR sizing — each
// is a real subprocess spawn, so a repo with thousands of merges in-window
// must not turn a retro into a full-history diff sweep.
const MAX_RANGE_DIFFS = 50;

/**
 * Signals an expected, user-facing failure (not a git repo, bad --window).
 * Carried via exception rather than process.exit() so we always unwind
 * through main()'s catch and set process.exitCode — calling process.exit()
 * while a git subprocess pipe could still be draining risks a Windows hang.
 */
class CliError extends Error {
    constructor(message, exitCode = 1) {
        super(message);
        this.exitCode = exitCode;
    }
}

// ---------------------------------------------------------------------------
// CLI parsing
// ---------------------------------------------------------------------------

const USAGE = 'Usage: node git-retro.mjs [--window 7d|24h|Nd|Nh|Nw] [--compare] [--save [dir]] [--base <ref>] [--no-fetch] [-h]';

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

const { save: doSave, saveDir, rest: argvForParse } = extractSaveOption(process.argv.slice(2));

const { values: opts } = parseArgs({
    args: argvForParse,
    options: {
        window: { type: 'string', default: '7d' },
        compare: { type: 'boolean', default: false },
        base: { type: 'string' },
        'no-fetch': { type: 'boolean', default: false },
        help: { type: 'boolean', short: 'h', default: false },
    },
});

if (opts.help) {
    printHelp();
    process.exit(0);
}

await main();

async function main() {
    try {
        const now = new Date();
        const repoRoot = detectRepoRoot();
        process.chdir(repoRoot);

        const windowSpec = parseWindowSpec(opts.window);
        if (!windowSpec) {
            throw new CliError(`Invalid --window value "${opts.window}". Expected Nd, Nh, or Nw (e.g. 7d, 24h, 2w).\n${USAGE}`, 2);
        }

        const { base, noRemote } = opts.base ? { base: opts.base, noRemote: false } : detectBaseRef();
        const fetchResult = maybeFetch(base, opts['no-fetch']);
        const currentUser = getCurrentUser();
        const globalGuards = {
            fetchFailed: fetchResult.attempted && !fetchResult.ok,
            noRemote,
            detachedHead: isDetachedHead(),
            shallowClone: isShallowClone(),
        };

        const newestCommitDate = getNewestCommitDate(base);
        const windowStart = computeSince(now, windowSpec);

        const currentMetrics = buildWindowMetrics({ base, since: windowStart, until: null, currentUser, includeStreaks: true });
        currentMetrics.guards = {
            ...globalGuards,
            zeroCommits: currentMetrics.totals.commits === 0,
            staleBase: newestCommitDate !== null && newestCommitDate < windowStart,
        };

        const meta = {
            repoRoot,
            base,
            window: opts.window,
            windowStart: toLocalIso(windowStart),
            windowEnd: toLocalIso(now),
            fetchOk: fetchResult.ok,
            currentUser: currentUser ? { name: currentUser.name, email: currentUser.email } : null,
            generatedAt: toLocalIso(now),
        };

        let output;
        if (opts.compare) {
            const priorStart = computePriorStart(now, windowSpec, windowStart);
            const priorMetrics = buildWindowMetrics({ base, since: priorStart, until: windowStart, currentUser, includeStreaks: false });
            priorMetrics.guards = {
                ...globalGuards,
                zeroCommits: priorMetrics.totals.commits === 0,
                staleBase: newestCommitDate !== null && newestCommitDate < priorStart,
            };
            currentMetrics.windowStart = toLocalIso(windowStart);
            currentMetrics.windowEnd = toLocalIso(now);
            priorMetrics.windowStart = toLocalIso(priorStart);
            priorMetrics.windowEnd = toLocalIso(windowStart);

            output = { meta, current: currentMetrics, prior: priorMetrics, deltas: computeDeltas(priorMetrics, currentMetrics) };
        } else {
            const { guards, ...metricGroups } = currentMetrics;
            output = { meta, guards, ...metricGroups };
        }

        const json = JSON.stringify(output, null, 2);
        console.log(json);

        if (doSave) {
            const dir = resolve(repoRoot, saveDir ?? 'docs/retros');
            mkdirSync(dir, { recursive: true });
            const filePath = uniqueSnapshotPath(dir, now);
            writeFileSync(filePath, json);
            console.error(`Saved snapshot to ${filePath}`);
        }
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
// Repo / base-ref / fetch / identity
// ---------------------------------------------------------------------------

function detectRepoRoot() {
    try {
        return git(['rev-parse', '--show-toplevel']);
    } catch {
        throw new CliError('Not a git repository (or any parent up to the mount point). Run this from inside a git repo.', 1);
    }
}

/**
 * origin/<default-branch> when we can find one, else a probe of the two
 * conventional default-branch names, else HEAD (flagged via noRemote).
 */
function detectBaseRef() {
    try {
        const ref = git(['symbolic-ref', 'refs/remotes/origin/HEAD']);
        return { base: `origin/${ref.split('/').pop()}`, noRemote: false };
    } catch {
        // fall through to the probe below
    }
    for (const candidate of ['origin/main', 'origin/master']) {
        try {
            git(['rev-parse', '--verify', candidate]);
            return { base: candidate, noRemote: false };
        } catch {
            // try the next candidate
        }
    }
    return { base: 'HEAD', noRemote: true };
}

/**
 * Best-effort `git fetch origin <branch>`; only attempted when base is
 * shaped like origin/<branch> and --no-fetch was not passed. Failure is
 * never fatal — the caller turns it into the fetchFailed guard.
 */
function maybeFetch(base, noFetchFlag) {
    const m = /^origin\/(.+)$/.exec(base);
    if (noFetchFlag || !m) {
        return { ok: false, attempted: false };
    }
    try {
        execFileSync('git', ['fetch', 'origin', m[1], '--quiet'], { encoding: 'utf8', maxBuffer: GIT_MAX_BUFFER });
        return { ok: true, attempted: true };
    } catch {
        return { ok: false, attempted: true };
    }
}

/**
 * currentUser is null unless BOTH user.name and user.email are configured —
 * a partial identity is too ambiguous to safely match commits against.
 */
function getCurrentUser() {
    const name = gitOrNull(['config', 'user.name']);
    const email = gitOrNull(['config', 'user.email']);
    return name && email ? { name, email } : null;
}

function isDetachedHead() {
    try {
        git(['symbolic-ref', '--quiet', 'HEAD']);
        return false;
    } catch {
        return true;
    }
}

function isShallowClone() {
    return gitOrNull(['rev-parse', '--is-shallow-repository']) === 'true';
}

/** Newest commit instant reachable from base, across all of history (for staleBase). */
function getNewestCommitDate(base) {
    const iso = gitOrNull(['log', base, '-1', '--format=%aI']);
    return iso ? new Date(iso) : null;
}

// ---------------------------------------------------------------------------
// Window / date math
// ---------------------------------------------------------------------------

function pad2(n) {
    return String(n).padStart(2, '0');
}

function localDateString(date) {
    return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

/**
 * Local wall-clock string with NO offset, for git --since/--until. Git parses
 * an offset-less "YYYY-MM-DDTHH:MM:SS" in the machine's local timezone, which
 * is exactly what we want — never build this via toISOString(), which
 * converts to UTC and silently shifts the window.
 */
function toGitWallClock(date) {
    return `${localDateString(date)}T${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
}

/** Local wall-clock string WITH an explicit UTC offset, for JSON output. */
function toLocalIso(date) {
    const offMinutes = -date.getTimezoneOffset();
    const sign = offMinutes >= 0 ? '+' : '-';
    const abs = Math.abs(offMinutes);
    const time = `${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}`;
    return `${localDateString(date)}T${time}${sign}${pad2(Math.floor(abs / 60))}:${pad2(abs % 60)}`;
}

function parseWindowSpec(spec) {
    const m = /^(\d+)([dhw])$/i.exec(spec ?? '');
    return m ? { amount: parseInt(m[1], 10), unit: m[2].toLowerCase() } : null;
}

/**
 * d/w windows start at local midnight N (or N*7) days back, built with Date
 * field arithmetic (not millisecond math) so the JS Date engine — not us —
 * absorbs any DST transition inside the window. h windows are an exact
 * duration, so millisecond math is correct and simplest there.
 */
function computeSince(now, windowSpec) {
    if (windowSpec.unit === 'h') {
        return new Date(now.getTime() - windowSpec.amount * 3600000);
    }
    const days = windowSpec.unit === 'w' ? windowSpec.amount * 7 : windowSpec.amount;
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() - days, 0, 0, 0, 0);
}

/**
 * The prior (immediately-preceding) window's start, for --compare. For d/w
 * windows this is recomputed via calendar arithmetic on `now` (2x the day
 * count back) rather than subtracting milliseconds from windowStart, so a
 * DST transition inside either window can't drift it off local midnight.
 */
function computePriorStart(now, windowSpec, windowStart) {
    if (windowSpec.unit === 'h') {
        return new Date(windowStart.getTime() - windowSpec.amount * 3600000);
    }
    const days = windowSpec.unit === 'w' ? windowSpec.amount * 7 : windowSpec.amount;
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() - days * 2, 0, 0, 0, 0);
}

// ---------------------------------------------------------------------------
// git primitive + two-pass data collection
// ---------------------------------------------------------------------------

/** Every git invocation goes through here: argument array, never a shell string. */
function git(args) {
    return execFileSync('git', args, { encoding: 'utf8', maxBuffer: GIT_MAX_BUFFER }).trim();
}

function gitOrNull(args) {
    try {
        const out = git(args);
        return out === '' ? null : out;
    } catch {
        return null;
    }
}

function sinceUntilArgs(since, until) {
    const args = [`--since=${toGitWallClock(since)}`];
    if (until) {
        args.push(`--until=${toGitWallClock(until)}`);
    }
    return args;
}

/**
 * Pass 1: one git-log invocation returns both commit headers and per-file
 * numstat. Records are NUL-delimited (a byte that cannot appear in any git
 * field); header fields within a record are delimited by \x1f. Lines after
 * the header, up to the next NUL, are numstat lines for that commit — merges
 * normally have none.
 */
function collectCommits(base, since, until) {
    const raw = git(['log', base, ...sinceUntilArgs(since, until), '--format=%x00%H%x1f%aN%x1f%ae%x1f%aI%x1f%P%x1f%s', '--numstat']);
    const commits = [];
    for (const record of raw.split('\x00')) {
        if (record === '') {
            continue;
        }
        const lines = record.split('\n');
        const [hash, authorName, authorEmail, authorDate, parentsRaw, subject] = lines[0].split('\x1f');
        const parents = parentsRaw ? parentsRaw.split(' ').filter(Boolean) : [];
        const files = [];
        let insertions = 0;
        let deletions = 0;
        for (const line of lines.slice(1)) {
            if (line === '') {
                continue;
            }
            const [insRaw, delRaw, path] = line.split('\t');
            const ins = insRaw === '-' ? 0 : parseInt(insRaw, 10);
            const del = delRaw === '-' ? 0 : parseInt(delRaw, 10);
            insertions += ins;
            deletions += del;
            files.push({ path, insertions: ins, deletions: del, binary: insRaw === '-' });
        }
        commits.push({ hash, authorName, authorEmail, authorDate, isMerge: parents.length >= 2, subject, insertions, deletions, files });
    }
    return commits;
}

/**
 * Pass 2: Co-Authored-By trailers, one commit per line (hash \x1f
 * co-author-list, co-authors joined by \x02). On a git old enough to lack
 * %(trailers:...) support this throws; the caller degrades to
 * aiAssisted.available = false rather than treating it as fatal.
 */
function collectCoAuthors(base, since, until) {
    const raw = git(['log', base, ...sinceUntilArgs(since, until), '--format=%H%x1f%(trailers:key=Co-Authored-By,valueonly,separator=%x02)']);
    const map = new Map();
    for (const line of raw.split('\n')) {
        if (line === '') {
            continue;
        }
        const sep = line.indexOf('\x1f');
        const hash = line.slice(0, sep);
        const rest = line.slice(sep + 1);
        map.set(hash, rest ? rest.split('\x02').filter(Boolean) : []);
    }
    return map;
}

/** Unique local commit dates reachable from base, full history (no --since) — for streak counting. */
function collectCommitDates(base, authorFilter) {
    const args = ['log', base, '--date=format:%Y-%m-%d', '--format=%ad'];
    if (authorFilter) {
        // --fixed-strings: emails like 12345+user@users.noreply.github.com must match
        // literally under any grep.patternType (in default BRE a backslash-escaped \+
        // is itself a quantifier, so escaping is not a safe alternative).
        args.splice(2, 0, '--fixed-strings', `--author=${authorFilter}`);
    }
    const raw = gitOrNull(args);
    return new Set(raw ? raw.split('\n').filter(Boolean) : []);
}

function diffShortstat(hash) {
    const out = gitOrNull(['diff', '--shortstat', `${hash}^1..${hash}`]);
    if (out === null) {
        return null;
    }
    const insMatch = /(\d+) insertions?\(\+\)/.exec(out);
    const delMatch = /(\d+) deletions?\(-\)/.exec(out);
    return {
        insertions: insMatch ? parseInt(insMatch[1], 10) : 0,
        deletions: delMatch ? parseInt(delMatch[1], 10) : 0,
    };
}

// ---------------------------------------------------------------------------
// Small generic helpers
// ---------------------------------------------------------------------------

function round1(n) {
    return Math.round(n * 10) / 10;
}

function round3(n) {
    return Math.round(n * 1000) / 1000;
}

function sum(items, fn) {
    return items.reduce((total, item) => total + fn(item), 0);
}

function groupBy(items, keyFn) {
    const map = new Map();
    for (const item of items) {
        const key = keyFn(item);
        if (!map.has(key)) {
            map.set(key, []);
        }
        map.get(key).push(item);
    }
    return map;
}

function maxBy(items, fn) {
    let best = items[0];
    let bestValue = fn(items[0]);
    for (const item of items) {
        const value = fn(item);
        if (value > bestValue) {
            best = item;
            bestValue = value;
        }
    }
    return best;
}

/** Top-level directory a repo-relative path lives under; root files bucket into "(root)". */
function topDir(path) {
    const idx = path.indexOf('/');
    return idx === -1 ? '(root)' : path.slice(0, idx);
}

// ---------------------------------------------------------------------------
// Metric computations — volume, sessions, commit-type mix, hotspots
// ---------------------------------------------------------------------------

function computeTotals(commits) {
    const insertions = sum(commits, (c) => c.insertions);
    const deletions = sum(commits, (c) => c.deletions);
    const files = new Set();
    for (const c of commits) {
        for (const f of c.files) {
            files.add(f.path);
        }
    }
    return {
        commits: commits.length,
        mergeCommits: commits.filter((c) => c.isMerge).length,
        contributors: new Set(commits.map((c) => c.authorName)).size,
        insertions,
        deletions,
        netLoc: insertions - deletions,
        filesTouched: files.size,
        activeDays: new Set(commits.map((c) => localDateString(new Date(c.authorDate)))).size,
    };
}

function computeTestVsProd(commits) {
    let testInsertions = 0;
    let prodInsertions = 0;
    const testFiles = new Set();
    for (const c of commits) {
        for (const f of c.files) {
            if (TEST_PATH_RE.test(f.path)) {
                testInsertions += f.insertions;
                testFiles.add(f.path);
            } else {
                prodInsertions += f.insertions;
            }
        }
    }
    const denom = testInsertions + prodInsertions;
    return {
        testInsertions,
        prodInsertions,
        testRatio: denom > 0 ? round3(testInsertions / denom) : null,
        testFilesChanged: testFiles.size,
    };
}

function computeHourly(commits) {
    const histogram = new Array(24).fill(0);
    for (const c of commits) {
        histogram[new Date(c.authorDate).getHours()]++;
    }
    let peakHour = null;
    let max = 0;
    for (let h = 0; h < 24; h++) {
        if (histogram[h] > max) {
            max = histogram[h];
            peakHour = h;
        }
    }
    return { histogram, peakHour };
}

/**
 * Per-author session detection: sort each author's own commits by time and
 * start a new session whenever the gap to the previous commit exceeds 45
 * minutes. Grouping by author first is what keeps interleaved commits from
 * two people working at the same time from merging into one session.
 */
function detectSessionsByAuthor(commits) {
    const byAuthor = groupBy(commits, (c) => c.authorName);
    const result = new Map();
    for (const [author, authorCommits] of byAuthor) {
        const sorted = [...authorCommits].sort((a, b) => new Date(a.authorDate) - new Date(b.authorDate));
        const sessions = [];
        let current = null;
        for (const c of sorted) {
            const t = new Date(c.authorDate).getTime();
            if (current && t - current.lastTime <= SESSION_GAP_MINUTES * 60000) {
                current.commits.push(c);
                current.lastTime = t;
            } else {
                if (current) {
                    sessions.push(current);
                }
                current = { commits: [c], firstTime: t, lastTime: t };
            }
        }
        if (current) {
            sessions.push(current);
        }
        result.set(author, sessions.map(finalizeSession));
    }
    return result;
}

function finalizeSession(s) {
    const durationMinutes = s.commits.length <= 1 ? 0 : Math.round((s.lastTime - s.firstTime) / 60000);
    const kind = durationMinutes >= DEEP_SESSION_MIN ? 'deep' : durationMinutes >= MEDIUM_SESSION_MIN ? 'medium' : 'micro';
    return { start: toLocalIso(new Date(s.firstTime)), end: toLocalIso(new Date(s.lastTime)), durationMinutes, commits: s.commits.length, kind };
}

function summarizeSessions(sessions) {
    let deep = 0;
    let medium = 0;
    let micro = 0;
    let totalActiveMinutes = 0;
    for (const s of sessions) {
        totalActiveMinutes += s.durationMinutes;
        if (s.kind === 'deep') {
            deep++;
        } else if (s.kind === 'medium') {
            medium++;
        } else {
            micro++;
        }
    }
    return { count: sessions.length, deep, medium, micro, totalActiveMinutes };
}

/** Team-wide session rollup plus locPerSessionHour, the one cross-cutting rate metric. */
function computeSessions(commits, perAuthorSessions) {
    let totalSessions = 0;
    let deep = 0;
    let medium = 0;
    let micro = 0;
    let totalActiveMinutes = 0;
    for (const sessions of perAuthorSessions.values()) {
        const s = summarizeSessions(sessions);
        totalSessions += s.count;
        deep += s.deep;
        medium += s.medium;
        micro += s.micro;
        totalActiveMinutes += s.totalActiveMinutes;
    }
    const avgSessionMinutes = totalSessions > 0 ? Math.round(totalActiveMinutes / totalSessions) : null;
    const totalLoc = sum(commits, (c) => c.insertions + c.deletions);
    const locPerSessionHour = totalActiveMinutes >= 30 ? Math.round(totalLoc / (totalActiveMinutes / 60) / 50) * 50 : null;
    return { totalSessions, deep, medium, micro, totalActiveMinutes, avgSessionMinutes, locPerSessionHour };
}

/** Conventional-commit type mix, excluding merges. All 12 keys always present (0 when absent) for a stable schema. */
function computeCommitTypes(nonMergeCommits) {
    const counts = Object.fromEntries(COMMIT_TYPES.map((t) => [t, 0]));
    for (const c of nonMergeCommits) {
        const m = COMMIT_TYPE_RE.exec(c.subject);
        counts[m ? m[1] : 'other']++;
    }
    const total = nonMergeCommits.length;
    const percentages = Object.fromEntries(COMMIT_TYPES.map((t) => [t, total > 0 ? round1((counts[t] / total) * 100) : 0]));
    return { total, counts, percentages, fixRatioHigh: total > 0 && counts.fix / total > 0.5 };
}

/** Top 10 files by number of DISTINCT commits touching them (not by LOC). */
function computeHotspots(commits) {
    const counts = new Map();
    for (const c of commits) {
        const pathsInCommit = new Set(c.files.map((f) => f.path));
        for (const path of pathsInCommit) {
            counts.set(path, (counts.get(path) ?? 0) + 1);
        }
    }
    return [...counts.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10)
        .map(([path, changes]) => ({ path, changes, churn: changes >= 5, isTest: TEST_PATH_RE.test(path) }));
}

// ---------------------------------------------------------------------------
// Metric computations — PRs, focus, ship, per-author, AI assist, streaks
// ---------------------------------------------------------------------------

/**
 * PR count: unique #/! reference numbers across ALL commit subjects (covers
 * squash-merge subjects that carry the number on an otherwise-plain commit),
 * plus one per merge commit whose own subject carries no such reference
 * (a non-squash merge with a generic "Merge branch 'x'" message).
 *
 * Sizing (the whole block is marked approx: true): a squash-style commit is
 * sized from its own numstat; a true merge commit is sized via a
 * first-parent range diff, capped at MAX_RANGE_DIFFS invocations since each
 * is a subprocess spawn.
 */
function computePrs(commits) {
    const refNumbers = new Set();
    let mergeCommitsNoRef = 0;
    for (const c of commits) {
        const m = PR_REF_RE.exec(c.subject);
        if (m) {
            refNumbers.add(m[0].slice(1));
        } else if (c.isMerge) {
            mergeCommitsNoRef++;
        }
    }

    const sizedEntries = [];
    let diffInvocations = 0;
    let skipped = 0;
    for (const c of commits) {
        if (!c.isMerge && SQUASH_PR_RE.test(c.subject)) {
            const refMatch = /\((#\d+)\)/.exec(c.subject);
            sizedEntries.push({ hash: c.hash, ref: refMatch?.[1], subject: c.subject, author: c.authorName, loc: c.insertions + c.deletions });
        } else if (c.isMerge) {
            if (diffInvocations >= MAX_RANGE_DIFFS) {
                skipped++;
                continue;
            }
            diffInvocations++;
            const stat = diffShortstat(c.hash);
            if (stat) {
                const refMatch = PR_REF_RE.exec(c.subject);
                sizedEntries.push({ hash: c.hash, ref: refMatch?.[0], subject: c.subject, author: c.authorName, loc: stat.insertions + stat.deletions });
            }
        }
    }

    const buckets = { S: 0, M: 0, L: 0, XL: 0 };
    for (const e of sizedEntries) {
        if (e.loc < 100) {
            buckets.S++;
        } else if (e.loc < 500) {
            buckets.M++;
        } else if (e.loc < 1500) {
            buckets.L++;
        } else {
            buckets.XL++;
        }
    }

    const largest = sizedEntries.length > 0 ? maxBy(sizedEntries, (e) => e.loc) : null;
    const result = {
        count: refNumbers.size + mergeCommitsNoRef,
        approx: true,
        buckets,
        sized: sizedEntries.length,
        largest: largest ? { ref: largest.ref ?? null, subject: largest.subject, loc: largest.loc } : null,
    };
    if (skipped > 0) {
        result.diffCapped = true;
        result.skipped = skipped;
    }
    return { result, sizedEntries };
}

/** % of non-merge commits touching the single most-touched top-level dir, plus the top 8 dirs. */
function computeFocus(nonMergeCommits) {
    const dirTouches = new Map();
    for (const c of nonMergeCommits) {
        const dirsInCommit = new Set(c.files.map((f) => topDir(f.path)));
        for (const dir of dirsInCommit) {
            dirTouches.set(dir, (dirTouches.get(dir) ?? 0) + 1);
        }
    }
    let modalDir = null;
    let modalCount = 0;
    for (const [dir, count] of dirTouches) {
        if (count > modalCount) {
            modalDir = dir;
            modalCount = count;
        }
    }
    const top8 = [...dirTouches.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
    return {
        score: nonMergeCommits.length > 0 ? round1((modalCount / nonMergeCommits.length) * 100) : 0,
        dir: modalDir,
        dirTouches: Object.fromEntries(top8),
    };
}

/** Highest-LOC sized PR; falls back to the highest-LOC single commit when there are no PRs at all. */
function computeShip(sizedEntries, nonMergeCommits) {
    if (sizedEntries.length > 0) {
        const biggest = maxBy(sizedEntries, (e) => e.loc);
        return { kind: 'pr', ref: biggest.ref ?? null, subject: biggest.subject, author: biggest.author, loc: biggest.loc };
    }
    if (nonMergeCommits.length === 0) {
        return null;
    }
    const biggest = maxBy(nonMergeCommits, (c) => c.insertions + c.deletions);
    return { kind: 'commit', hash: biggest.hash.slice(0, 7), subject: biggest.subject, author: biggest.authorName, loc: biggest.insertions + biggest.deletions };
}

function peakHourOf(commits) {
    if (commits.length === 0) {
        return null;
    }
    const histogram = new Array(24).fill(0);
    for (const c of commits) {
        histogram[new Date(c.authorDate).getHours()]++;
    }
    let peak = 0;
    for (let h = 1; h < 24; h++) {
        if (histogram[h] > histogram[peak]) {
            peak = h;
        }
    }
    return peak;
}

/** One row per author, non-merge commits only, current user pinned first when known. */
function computeAuthors(nonMergeCommits, perAuthorSessions, currentUser) {
    const byAuthor = groupBy(nonMergeCommits, (c) => c.authorName);
    const authors = [];
    for (const [name, cs] of byAuthor) {
        const insertions = sum(cs, (c) => c.insertions);
        const deletions = sum(cs, (c) => c.deletions);
        let testIns = 0;
        let prodIns = 0;
        const dirTouches = new Map();
        for (const c of cs) {
            const dirsInCommit = new Set();
            for (const f of c.files) {
                if (TEST_PATH_RE.test(f.path)) {
                    testIns += f.insertions;
                } else {
                    prodIns += f.insertions;
                }
                dirsInCommit.add(topDir(f.path));
            }
            for (const dir of dirsInCommit) {
                dirTouches.set(dir, (dirTouches.get(dir) ?? 0) + 1);
            }
        }
        const topAreas = [...dirTouches.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([dir]) => dir);
        const biggest = maxBy(cs, (c) => c.insertions + c.deletions);
        const sessions = summarizeSessions(perAuthorSessions.get(name) ?? []);
        authors.push({
            name,
            isCurrentUser: currentUser !== null && name === currentUser.name,
            commits: cs.length,
            insertions,
            deletions,
            netLoc: insertions - deletions,
            testRatio: testIns + prodIns > 0 ? round3(testIns / (testIns + prodIns)) : null,
            topAreas,
            peakHour: peakHourOf(cs),
            biggestCommit: { hash7: biggest.hash.slice(0, 7), subject: biggest.subject, loc: biggest.insertions + biggest.deletions },
            sessions,
        });
    }
    authors.sort((a, b) => b.commits - a.commits);
    if (currentUser) {
        const idx = authors.findIndex((a) => a.isCurrentUser);
        if (idx > 0) {
            authors.unshift(authors.splice(idx, 1)[0]);
        }
    }
    return authors;
}

/**
 * A commit is AI-assisted when any Co-Authored-By trailer value matches
 * AI_CO_AUTHOR_RE. Co-authors never appear in totals.contributors or
 * authors[] because those are built from the commit AUTHOR field, never
 * from trailer text, so no separate exclusion step is needed here.
 */
function computeAiAssisted(nonMergeCommits, coAuthorMap, available) {
    if (!available) {
        return { available: false };
    }
    let count = 0;
    const matched = new Set();
    for (const c of nonMergeCommits) {
        const coAuthors = coAuthorMap.get(c.hash) ?? [];
        const aiOnes = coAuthors.filter((ca) => AI_CO_AUTHOR_RE.test(ca));
        if (aiOnes.length > 0) {
            count++;
            aiOnes.forEach((ca) => matched.add(ca));
        }
    }
    return {
        available: true,
        commits: count,
        pct: nonMergeCommits.length > 0 ? round1((count / nonMergeCommits.length) * 100) : 0,
        coAuthors: [...matched],
    };
}

function streakFromDates(dateSet) {
    if (dateSet.size === 0) {
        return 0;
    }
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    let cursor;
    if (dateSet.has(localDateString(today))) {
        cursor = today;
    } else if (dateSet.has(localDateString(yesterday))) {
        cursor = yesterday;
    } else {
        return 0;
    }
    let streak = 0;
    while (dateSet.has(localDateString(cursor))) {
        streak++;
        cursor.setDate(cursor.getDate() - 1);
    }
    return streak;
}

/** Full-history (no --since) consecutive-day counts; a grace day covers "haven't committed yet today". */
function computeStreaks(base, currentUser) {
    const teamStreakDays = streakFromDates(collectCommitDates(base, null));
    const yourStreakDays = currentUser ? streakFromDates(collectCommitDates(base, currentUser.email)) : null;
    return { teamStreakDays, yourStreakDays };
}

// ---------------------------------------------------------------------------
// Per-window orchestration
// ---------------------------------------------------------------------------

/**
 * Runs the full collection + computation pipeline for one since/until pair
 * and returns every metric group EXCEPT guards/windowStart/windowEnd, which
 * main() attaches afterward (they depend on repo-wide state, not just this
 * window's commits).
 */
function buildWindowMetrics({ base, since, until, currentUser, includeStreaks }) {
    const commits = collectCommits(base, since, until);
    const nonMergeCommits = commits.filter((c) => !c.isMerge);

    let coAuthorMap = new Map();
    let coAuthorsAvailable = true;
    try {
        coAuthorMap = collectCoAuthors(base, since, until);
    } catch {
        coAuthorsAvailable = false;
    }

    const perAuthorSessions = detectSessionsByAuthor(commits);
    const { result: prs, sizedEntries } = computePrs(commits);

    const metrics = {
        totals: computeTotals(commits),
        testVsProd: computeTestVsProd(commits),
        hourly: computeHourly(commits),
        sessions: computeSessions(commits, perAuthorSessions),
        commitTypes: computeCommitTypes(nonMergeCommits),
        hotspots: computeHotspots(commits),
        prs,
        focus: computeFocus(nonMergeCommits),
        ship: computeShip(sizedEntries, nonMergeCommits),
        authors: computeAuthors(nonMergeCommits, perAuthorSessions, currentUser),
        aiAssisted: computeAiAssisted(nonMergeCommits, coAuthorMap, coAuthorsAvailable),
    };
    if (includeStreaks) {
        metrics.streaks = computeStreaks(base, currentUser);
    }
    return metrics;
}

// ---------------------------------------------------------------------------
// Compare-mode deltas
// ---------------------------------------------------------------------------

/** The scalar metrics --compare tracks deltas for, pulled out of the full metric-group shape. */
function scalarView(m) {
    return {
        commits: m.totals.commits,
        contributors: m.totals.contributors,
        insertions: m.totals.insertions,
        deletions: m.totals.deletions,
        netLoc: m.totals.netLoc,
        activeDays: m.totals.activeDays,
        testRatio: m.testVsProd.testRatio,
        totalSessions: m.sessions.totalSessions,
        deepSessions: m.sessions.deep,
        avgSessionMinutes: m.sessions.avgSessionMinutes,
        locPerSessionHour: m.sessions.locPerSessionHour,
        fixPct: m.commitTypes.percentages.fix,
        prCount: m.prs.count,
        aiAssistedPct: m.aiAssisted.available ? m.aiAssisted.pct : null,
        focusScore: m.focus.score,
    };
}

function computeDeltas(priorMetrics, currentMetrics) {
    const prior = scalarView(priorMetrics);
    const current = scalarView(currentMetrics);
    const deltas = {};
    for (const key of Object.keys(current)) {
        const p = prior[key];
        const c = current[key];
        const delta = p !== null && c !== null ? round3(c - p) : null;
        const pctChange = p !== null && p !== 0 && c !== null ? round1(((c - p) / Math.abs(p)) * 100) : null;
        deltas[key] = { prior: p, current: c, delta, pctChange };
    }
    return deltas;
}

// ---------------------------------------------------------------------------
// Snapshot saving
// ---------------------------------------------------------------------------

/** <YYYY-MM-DD>-<n>.json, n starting at 1 and incrementing past any file already there for today. */
function uniqueSnapshotPath(dir, now) {
    const date = localDateString(now);
    let n = 1;
    let filePath = join(dir, `${date}-${n}.json`);
    while (existsSync(filePath)) {
        n++;
        filePath = join(dir, `${date}-${n}.json`);
    }
    return filePath;
}

// ---------------------------------------------------------------------------
// Help
// ---------------------------------------------------------------------------

function printHelp() {
    console.log(`Compute engineering-retrospective metrics from git history as JSON.

${USAGE}

Options:
  --window <spec>   Time window: Nd (days), Nh (hours), Nw (weeks). Default: 7d.
                    d/w windows start at local midnight N days back; h windows
                    start exactly N hours before now.
  --compare         Also compute the immediately-prior same-length window and
                    emit { meta, current, prior, deltas } instead of the flat shape.
  --save [dir]      Also write the JSON to <dir>/<YYYY-MM-DD>-<n>.json (n is
                    collision-safe). Default dir: docs/retros/ under the repo root.
  --base <ref>      Override base-ref detection (default: origin/<default-branch>,
                    probing origin/main and origin/master, falling back to HEAD).
  --no-fetch        Skip the best-effort \`git fetch origin <branch>\` before reading.
  -h, --help        Show this help.

Examples:
  # Last 7 days against the detected default branch
  node git-retro.mjs

  # Last 24 hours, no network access
  node git-retro.mjs --window 24h --no-fetch

  # Last 90 days vs. the 90 days before that, saved as a snapshot
  node git-retro.mjs --window 90d --compare --save
`);
}

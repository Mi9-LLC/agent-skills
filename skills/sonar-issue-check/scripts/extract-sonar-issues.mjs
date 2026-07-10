#!/usr/bin/env node
/**
 * Extract SonarCloud / SonarQube issues for the repository you run it in.
 *
 * By default it reports only the issues introduced in the *new code* of the
 * current git branch — the same "did I just introduce a problem?" signal you
 * want before committing or opening a pull request. Pass --all to report every
 * unresolved issue on the analyzed branch/PR instead, not just the new-code
 * period.
 *
 * No external dependencies: it uses Node's built-in fetch. Configuration
 * (project key, organization, host) is discovered from the project's own
 * `sonar-project.properties` — the file the SonarScanner itself reads — with a
 * fallback to the SonarLint binding in `.vscode/settings.json`, so the common
 * case needs no flags. The token is read from the SONAR_TOKEN environment
 * variable or a local .env file, keeping each person's credential out of git.
 *
 * Works against SonarCloud (a.k.a. SonarQube Cloud, sonarcloud.io) and against
 * a self-hosted SonarQube Server via --host. The `organization` parameter is
 * sent only when targeting SonarCloud (or when you pass --org explicitly),
 * because self-hosted SonarQube has no organizations concept.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { parseArgs } from 'node:util';
import { resolve } from 'node:path';

const DEFAULT_HOST = 'https://sonarcloud.io';
const PAGE_SIZE = 500;
// SonarCloud refuses to page past 10k results in a single query (p * ps must
// stay <= 10000); we surface this rather than silently truncating so a huge
// backlog is never mistaken for a clean one.
const MAX_TOTAL = 10000;
// Abort a hung request rather than letting the skill hang forever.
const FETCH_TIMEOUT_MS = 30000;
// .env files searched (in order) when SONAR_TOKEN is not in the environment.
const ENV_FILE_CANDIDATES = ['.env', 'env/.env'];

// Worst -> least, interleaving the legacy "Standard Experience" severities
// (BLOCKER/CRITICAL/MAJOR/MINOR/INFO) with the newer MQR impact severities
// (BLOCKER/HIGH/MEDIUM/LOW/INFO) so sorting and grouping work whichever
// vocabulary the server returns.
const SEVERITY_ORDER = ['BLOCKER', 'CRITICAL', 'HIGH', 'MAJOR', 'MEDIUM', 'MINOR', 'LOW', 'INFO'];

const { values: opts } = parseArgs({
    options: {
        project: { type: 'string', short: 'p' },
        org: { type: 'string' },
        branch: { type: 'string', short: 'b' },
        'pull-request': { type: 'string' },
        all: { type: 'boolean', default: false },
        'include-resolved': { type: 'boolean', default: false },
        types: { type: 'string' },
        severities: { type: 'string' },
        out: { type: 'string' },
        host: { type: 'string' },
        'env-file': { type: 'string' },
        'fail-on-issues': { type: 'boolean', default: false },
        help: { type: 'boolean', short: 'h', default: false },
    },
});

if (opts.help) {
    printHelp();
    process.exit(0);
}

/**
 * Locate the repository root so sonar-project.properties, .env, and
 * .vscode/settings.json resolve correctly no matter which directory the script
 * is invoked from.
 */
const repoRoot = (() => {
    try {
        return execSync('git rev-parse --show-toplevel', { encoding: 'utf8' }).trim();
    } catch {
        return process.cwd();
    }
})();

/**
 * Signals an expected, user-facing failure (bad token, missing config, API
 * error). We carry it via an exception rather than calling process.exit()
 * directly: exiting while a fetch socket is still open crashes Node's event
 * loop on Windows, so we unwind cleanly and set process.exitCode instead.
 */
class CliError extends Error {}

await main();

async function main() {
    try {
        const props = readScannerProperties();
        const projectKey = resolveProjectKey(props);
        const host = resolveHost(props);
        const { org: organization, derived: orgDerived } = resolveOrg(props, host, projectKey);
        const token = resolveToken();
        const target = resolveTarget();

        printHeader({
            host,
            projectKey,
            organization,
            orgDerived,
            target,
            onlyNewCode: !opts.all,
            includeResolved: opts['include-resolved'],
        });

        const summary = await fetchIssues({
            host,
            token,
            projectKey,
            organization,
            target,
            onlyNewCode: !opts.all,
            includeResolved: opts['include-resolved'],
            types: opts.types,
            severities: opts.severities,
        });

        report(summary);

        if (!isEmpty(opts.out)) {
            writeFileSync(opts.out, JSON.stringify(summary, null, 2));
            console.log(`\nFull JSON written to ${opts.out}`);
        }

        if (opts['fail-on-issues'] && summary.issues.length > 0) {
            process.exitCode = 1;
        }
    } catch (err) {
        if (err instanceof CliError) {
            console.error(`\nError: ${err.message}\n`);
            process.exitCode = 2;

            return;
        }

        throw err;
    }
}

// ---------------------------------------------------------------------------
// Config resolution (project key, organization, host)
// ---------------------------------------------------------------------------

/**
 * Parse sonar-project.properties — the canonical file the SonarScanner reads —
 * into a flat key/value map. Returns {} when the file is absent; it is optional
 * because the user can supply everything via flags or env vars instead.
 */
function readScannerProperties() {
    const props = {};
    try {
        const raw = readFileSync(resolve(repoRoot, 'sonar-project.properties'), 'utf8');
        for (const line of raw.split('\n')) {
            const clean = line.replace(/\r$/, '').trim();
            if (!clean || clean.startsWith('#') || !clean.includes('=')) {
                continue;
            }
            const eq = clean.indexOf('=');
            props[clean.slice(0, eq).trim()] = clean.slice(eq + 1).trim();
        }
    } catch {
        // file is optional — fall back to other sources
    }

    return props;
}

/**
 * Project key priority: --project flag, then sonar-project.properties
 * (sonar.projectKey, what the scanner actually uploads under), then the
 * SonarLint IDE binding in .vscode/settings.json (an editor convenience, not a
 * scanner source, so it is the last resort).
 */
function resolveProjectKey(props) {
    if (!isEmpty(opts.project)) {
        return opts.project;
    }
    if (!isEmpty(props['sonar.projectKey'])) {
        return props['sonar.projectKey'];
    }
    const fromIde = readProjectKeyFromVscode();
    if (!isEmpty(fromIde)) {
        return fromIde;
    }

    fail(
        'Could not determine the Sonar project key.\n' +
            'Set it in sonar-project.properties (sonar.projectKey=<key>), pass --project <key>,\n' +
            'or add the SonarLint connected-mode block to .vscode/settings.json.',
    );
}

/**
 * Read the project key from the SonarLint connected-mode config. We use a regex
 * rather than JSON.parse because VS Code settings allow comments and trailing
 * commas. Handles both the nested ("sonarlint.connectedMode.project": {
 * "projectKey": ... }) and dotted-key forms. Returns undefined when absent.
 */
function readProjectKeyFromVscode() {
    try {
        const raw = readFileSync(resolve(repoRoot, '.vscode/settings.json'), 'utf8');
        const match = raw.match(/"(?:sonarlint\.connectedMode\.project\.)?projectKey"\s*:\s*"([^"]+)"/);

        return match ? match[1] : undefined;
    } catch {
        return undefined;
    }
}

/**
 * Host priority: --host flag, then sonar.host.url in sonar-project.properties,
 * then the SONAR_HOST_URL env var, then SonarCloud. Trailing slashes are
 * stripped so URL joining stays clean.
 */
function resolveHost(props) {
    const raw =
        opts.host ??
        (isEmpty(props['sonar.host.url']) ? undefined : props['sonar.host.url']) ??
        (isEmpty(process.env.SONAR_HOST_URL) ? undefined : process.env.SONAR_HOST_URL) ??
        DEFAULT_HOST;

    return raw.replace(/\/+$/, '');
}

/**
 * Organization priority: --org, SONAR_ORG, sonar.organization (properties). On
 * SonarCloud the org is mandatory, so as a last resort we derive it from the
 * project-key prefix (keys are conventionally "<org>_<repo>") and flag it as
 * derived so the header can warn. On self-hosted SonarQube there are no
 * organizations, so we leave it undefined and never send the parameter.
 */
function resolveOrg(props, host, projectKey) {
    if (!isEmpty(opts.org)) {
        return { org: opts.org, derived: false };
    }
    if (!isSonarCloudHost(host)) {
        // Self-hosted SonarQube has no organizations concept; never auto-resolve one.
        return { org: undefined, derived: false };
    }
    if (!isEmpty(process.env.SONAR_ORG)) {
        return { org: process.env.SONAR_ORG.trim(), derived: false };
    }
    if (!isEmpty(props['sonar.organization'])) {
        return { org: props['sonar.organization'], derived: false };
    }

    return { org: deriveOrg(projectKey), derived: true };
}

function isSonarCloudHost(host) {
    try {
        const h = new URL(host).hostname.toLowerCase();

        return (
            h === 'sonarcloud.io' ||
            h.endsWith('.sonarcloud.io') ||
            h === 'sonarqube.com' ||
            h.endsWith('.sonarqube.com')
        );
    } catch {
        return false;
    }
}

/**
 * Derive the organization from the part of the project key before the first
 * underscore. Override with --org / SONAR_ORG / sonar.organization when that
 * convention does not hold.
 */
function deriveOrg(key) {
    const idx = key.indexOf('_');

    return idx > 0 ? key.slice(0, idx) : key;
}

// ---------------------------------------------------------------------------
// Token resolution
// ---------------------------------------------------------------------------

/**
 * Read SONAR_TOKEN from the real environment first (handy in CI), then fall
 * back to a local .env file (.env, then env/.env, or whatever --env-file
 * points at). We strip CRs because env files are often CRLF on Windows and a
 * trailing \r corrupts the auth header.
 */
function resolveToken() {
    if (!isEmpty(process.env.SONAR_TOKEN)) {
        return process.env.SONAR_TOKEN.trim();
    }

    const candidates = isEmpty(opts['env-file']) ? ENV_FILE_CANDIDATES : [opts['env-file']];
    const tried = [];
    for (const rel of candidates) {
        const envPath = resolve(repoRoot, rel);
        tried.push(envPath);
        let raw;
        try {
            raw = readFileSync(envPath, 'utf8');
        } catch {
            continue;
        }
        const token = extractEnvVar(raw, 'SONAR_TOKEN');
        if (!isEmpty(token)) {
            return token;
        }
    }

    fail(
        'SONAR_TOKEN was not found.\n' +
            'Export it in your shell (export SONAR_TOKEN=<token>), or add a line\n' +
            '  SONAR_TOKEN=<your token>\n' +
            `to one of: ${tried.join(', ')} (or pass --env-file <path>).\n` +
            'Generate a User Token in your Sonar account → Security.',
    );
}

function extractEnvVar(raw, name) {
    for (const line of raw.split('\n')) {
        const clean = line.replace(/\r$/, '').trim();
        if (clean.startsWith('#') || !clean.includes('=')) {
            continue;
        }
        const key = clean.slice(0, clean.indexOf('=')).trim();
        if (key === name) {
            return unquote(clean.slice(clean.indexOf('=') + 1).trim());
        }
    }

    return undefined;
}

// ---------------------------------------------------------------------------
// Target resolution
// ---------------------------------------------------------------------------

/**
 * Decide whether we are querying a pull request or a branch, defaulting to the
 * branch currently checked out.
 */
function resolveTarget() {
    if (!isEmpty(opts['pull-request'])) {
        return { kind: 'pullRequest', value: opts['pull-request'] };
    }

    const branch = opts.branch ?? currentBranch();

    return { kind: 'branch', value: branch };
}

function currentBranch() {
    try {
        return execSync('git rev-parse --abbrev-ref HEAD', { encoding: 'utf8' }).trim();
    } catch {
        fail('Not in a git repository and no --branch given. Pass --branch <name>.');
    }
}

// ---------------------------------------------------------------------------
// Sonar Web API
// ---------------------------------------------------------------------------

/**
 * Page through /api/issues/search and collect every matching issue.
 */
async function fetchIssues(cfg) {
    // Token-as-username Basic auth works on both SonarCloud and SonarQube
    // (incl. older Server versions that predate Bearer-header support).
    const auth = `Basic ${Buffer.from(`${cfg.token}:`).toString('base64')}`;
    const issues = [];
    let page = 1;
    let total = 0;

    while (true) {
        const params = new URLSearchParams({
            // componentKeys is deprecated since 10.2 but still accepted on both
            // SonarCloud and current SonarQube; kept for broad compatibility.
            componentKeys: cfg.projectKey,
            ps: String(PAGE_SIZE),
            p: String(page),
        });

        if (!cfg.includeResolved) {
            // Sonar's `resolved` param is exclusive: resolved=true returns ONLY
            // resolved issues. Omit it to get the union (resolved + unresolved)
            // that --include-resolved promises; default stays unresolved-only.
            params.set('resolved', 'false');
        }

        if (!isEmpty(cfg.organization)) {
            params.set('organization', cfg.organization);
        }
        params.set(cfg.target.kind, cfg.target.value);

        if (cfg.onlyNewCode) {
            params.set('inNewCodePeriod', 'true');
        }
        if (!isEmpty(cfg.types)) {
            params.set('types', cfg.types);
        }
        if (!isEmpty(cfg.severities)) {
            params.set('severities', cfg.severities);
        }

        const url = `${cfg.host}/api/issues/search?${params.toString()}`;
        const res = await fetchWithTimeout(url, auth, cfg.host);

        if (!res.ok) {
            const body = await res.text();
            if (res.status === 401 || res.status === 403) {
                fail(
                    `${cfg.host} rejected the request (HTTP ${res.status}). The SONAR_TOKEN is ` +
                        'missing, invalid, expired, or lacks access to this project.\n' +
                        'Generate a new User Token in your Sonar account → Security, then update your env.',
                );
            }
            fail(`Sonar API returned HTTP ${res.status}.\n${body}`);
        }

        const data = await res.json();
        total = data.total ?? 0;
        issues.push(...(data.issues ?? []));

        if (page * PAGE_SIZE >= total || page * PAGE_SIZE >= MAX_TOTAL) {
            break;
        }
        page += 1;
    }

    return {
        host: cfg.host,
        projectKey: cfg.projectKey,
        organization: cfg.organization,
        target: cfg.target,
        scope: cfg.onlyNewCode ? 'new-code' : 'all',
        includeResolved: cfg.includeResolved,
        total,
        truncated: total > MAX_TOTAL,
        issues: issues.map(simplify),
    };
}

/**
 * Fetch with an abort-based timeout so a hung server doesn't hang the skill.
 */
async function fetchWithTimeout(url, auth, host) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
        return await fetch(url, { headers: { Authorization: auth }, signal: controller.signal });
    } catch (err) {
        if (err.name === 'AbortError') {
            fail(`Request to ${host} timed out after ${FETCH_TIMEOUT_MS / 1000}s. Check connectivity or --host.`);
        }
        fail(`Network error contacting ${host}: ${err.message}`);
    } finally {
        clearTimeout(timer);
    }
}

/**
 * Trim the API payload down to the fields that matter for a terminal summary
 * and a readable JSON dump. Carries both the legacy severity/type fields and
 * the newer MQR `impacts` array (whichever the server populates).
 */
function simplify(issue) {
    const file = (issue.component ?? '').split(':').slice(1).join(':');

    return {
        rule: issue.rule,
        severity: issue.severity ?? topImpactSeverity(issue),
        type: issue.type ?? null,
        impacts: issue.impacts ?? [],
        message: issue.message,
        file,
        line: issue.line ?? null,
        status: issue.status,
        creationDate: issue.creationDate,
        key: issue.key,
    };
}

/**
 * MQR-mode fallback: when the legacy `severity` field is absent, take the
 * worst severity across the issue's software-quality impacts.
 */
function topImpactSeverity(issue) {
    const impacts = issue.impacts ?? [];
    for (const sev of SEVERITY_ORDER) {
        if (impacts.some((i) => i.severity === sev)) {
            return sev;
        }
    }

    return impacts[0]?.severity ?? null;
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

/**
 * Print the resolved host / project / target / scope before the network call
 * so the user can confirm what was queried even when authentication fails.
 */
function printHeader(ctx) {
    const label = ctx.target.kind === 'pullRequest' ? `PR #${ctx.target.value}` : `branch ${ctx.target.value}`;
    const org = isEmpty(ctx.organization) ? '' : ` (org: ${ctx.organization}${ctx.orgDerived ? ', derived from key' : ''})`;
    console.log(`Host    : ${ctx.host}`);
    console.log(`Project : ${ctx.projectKey}${org}`);
    console.log(`Target  : ${label}`);
    console.log(`Scope   : ${ctx.onlyNewCode ? 'new code only' : 'all code'}${ctx.includeResolved ? ' (incl. resolved)' : ''}`);
    console.log('');
}

function report(s) {
    if (s.issues.length === 0) {
        console.log(s.scope === 'new-code' ? '✓ No new issues. Clean to commit.' : '✓ No issues found.');

        return;
    }

    if (s.truncated) {
        console.log(`⚠ Result capped at ${MAX_TOTAL} (total ${s.total}). Narrow with --types or --severities.`);
    }

    const bySeverity = countBy(s.issues, 'severity');
    const byType = countBy(s.issues, 'type');

    console.log(`Found ${s.issues.length} issue(s):`);
    console.log(`  By severity: ${formatCounts(bySeverity, SEVERITY_ORDER)}`);
    console.log(`  By type    : ${formatCounts(byType)}`);
    console.log('');

    const sorted = [...s.issues].sort((a, b) => severityRank(a.severity) - severityRank(b.severity));

    for (const i of sorted) {
        const where = isEmpty(i.file) ? '(project-level)' : `${i.file}:${i.line ?? '?'}`;
        const kind = isEmpty(i.type) ? i.severity : `${i.severity}/${i.type}`;
        console.log(`  [${kind}] ${where}`);
        console.log(`     ${i.message}  (${i.rule})`);
    }
}

/**
 * Rank a severity for sorting; unknown/missing severities sort last instead of
 * first (a raw indexOf of -1 would float them to the top).
 */
function severityRank(severity) {
    const idx = SEVERITY_ORDER.indexOf(severity);

    return idx === -1 ? SEVERITY_ORDER.length : idx;
}

function countBy(items, field) {
    const counts = {};
    for (const item of items) {
        const value = item[field] ?? 'UNKNOWN';
        counts[value] = (counts[value] ?? 0) + 1;
    }

    return counts;
}

function formatCounts(counts, order) {
    const keys = isEmpty(order)
        ? Object.keys(counts)
        : [...order.filter((k) => k in counts), ...Object.keys(counts).filter((k) => !order.includes(k))];

    return keys.map((k) => `${k}=${counts[k]}`).join(', ') || 'none';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isEmpty(value) {
    return value === undefined || value === null || value === '';
}

function unquote(value) {
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        return value.slice(1, -1);
    }

    return value;
}

function fail(message) {
    throw new CliError(message);
}

function printHelp() {
    console.log(`Extract SonarCloud / SonarQube issues for this repository.

Usage:
  node <path-to-skill>/scripts/extract-sonar-issues.mjs [options]

Default behaviour:
  Reports unresolved issues introduced in the NEW CODE of the current git
  branch — the pre-commit / pre-PR signal. Config (project key, organization,
  host) is read from sonar-project.properties, falling back to the SonarLint
  binding in .vscode/settings.json. The token is read from the SONAR_TOKEN
  environment variable, then from .env / env/.env.

Options:
  -p, --project <key>     Sonar project key (default: sonar-project.properties,
                          then .vscode/settings.json)
      --org <org>         Organization (default: SONAR_ORG / sonar.organization;
                          on SonarCloud, else derived from the key prefix)
  -b, --branch <name>     Branch to query (default: current git branch)
      --pull-request <id> Query a pull request instead of a branch
      --all               Report every unresolved issue on the analyzed
                          branch/PR, not just the new-code period
      --include-resolved  Include resolved/closed issues
      --types <list>      Comma list: BUG,VULNERABILITY,CODE_SMELL
      --severities <list> Comma list: BLOCKER,CRITICAL,MAJOR,MINOR,INFO
      --out <file>        Also write the full result as JSON to <file>
      --host <url>        Sonar host (default: sonar.host.url / SONAR_HOST_URL,
                          else ${DEFAULT_HOST}); set this for self-hosted SonarQube
      --env-file <path>   File holding SONAR_TOKEN (default: .env, then env/.env)
      --fail-on-issues    Exit code 1 when matching issues are found (for gates)
  -h, --help              Show this help

Examples:
  # New issues on the branch I'm about to push
  node .../extract-sonar-issues.mjs

  # Every unresolved issue on the branch/PR, dumped to a file
  node .../extract-sonar-issues.mjs --all --out sonar-all.json

  # New issues on a specific pull request, only bugs & vulnerabilities
  node .../extract-sonar-issues.mjs --pull-request 482 --types BUG,VULNERABILITY

  # Self-hosted SonarQube Server (no organization)
  node .../extract-sonar-issues.mjs --host https://sonar.mycompany.com
`);
}

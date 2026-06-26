#!/usr/bin/env node
/**
 * analyze-initial-load.mjs — what ships on a Vite build's initial JS load.
 *
 * Given a Vite `dist` directory, this finds the true entry from index.html,
 * follows STATIC imports/re-exports (never dynamic import() or mapDeps strings)
 * to compute the entry's initial-load closure, and prints every initial-load
 * chunk ranked by transfer size (brotli/gzip), flagging likely single-library
 * vendor chunks as deferral candidates. Lazy chunks are listed separately.
 *
 * No dependencies — Node built-ins only.
 *
 * Usage:
 *   node analyze-initial-load.mjs <dist-dir> [--all] [--json]
 *     <dist-dir>  Directory containing index.html (e.g. dist, dist/ui).
 *     --all       Also list lazy (on-demand) chunks.
 *     --json      Emit machine-readable JSON instead of the text report.
 *     --help      Show this help.
 *
 * Why size is "transfer size": users download the compressed bytes. The script
 * prefers a sibling .br, then .gz, else gzips the chunk itself (≈ what a server
 * would send). That is the number that matters for first-load cost.
 */

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, basename, dirname } from 'node:path';
import { gzipSync } from 'node:zlib';

const args = process.argv.slice(2);
if (args.includes('--help') || args.length === 0) {
  console.log(readFileSync(new URL(import.meta.url)).toString().split('\n')
    .filter((l) => l.startsWith(' *')).map((l) => l.replace(/^ \*?/, '')).join('\n'));
  process.exit(0);
}
const asJson = args.includes('--json');
const showLazy = args.includes('--all');
const distDir = args.find((a) => !a.startsWith('--'));
if (!distDir || !existsSync(distDir)) {
  console.error(`dist dir not found: ${distDir}`);
  process.exit(1);
}

// ---- collect files -----------------------------------------------------------
function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const s = statSync(p);
    if (s.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}
const files = walk(distDir);
const jsFiles = files.filter((f) => f.endsWith('.js'));
const htmlFiles = files.filter((f) => f.endsWith('.html'));
if (jsFiles.length === 0) { console.error('no .js files under dist dir'); process.exit(1); }

// basename -> full path (basenames are unique in a Vite build thanks to hashes)
const byName = new Map();
for (const f of jsFiles) byName.set(basename(f), f);

// pick the top-most index.html (shortest path), else any html
const indexHtml = htmlFiles.sort((a, b) => a.length - b.length)
  .find((f) => basename(f) === 'index.html') || htmlFiles[0];
if (!indexHtml) { console.error('no index.html found under dist dir'); process.exit(1); }
const htmlText = readFileSync(indexHtml, 'utf8');

// ---- static import graph -----------------------------------------------------
// Matches `... from "./x.js"`, `... from "../a/x.js"`, side-effect `import "./x.js"`,
// and `export ... from "./x.js"`. Excludes dynamic `import(...)` (a quote never
// follows `import(`) and excludes mapDeps string arrays (no from/import keyword).
const FROM_RE = /\bfrom\s*["'][^"']*?\/?([\w.$-]+\.js)["']/g;
const SIDE_RE = /\bimport\s*["'][^"']*?\/?([\w.$-]+\.js)["']/g;

const staticImports = new Map(); // name -> Set(name) it statically imports
const content = new Map();       // name -> file text (cached)
function readChunk(name) {
  if (!content.has(name)) content.set(name, readFileSync(byName.get(name), 'utf8'));
  return content.get(name);
}
for (const [name] of byName) {
  const text = readChunk(name);
  const deps = new Set();
  for (const re of [FROM_RE, SIDE_RE]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text))) if (byName.has(m[1])) deps.add(m[1]);
  }
  staticImports.set(name, deps);
}

// ---- seeds: every .js referenced by index.html (entry script + modulepreloads)
const htmlRefs = new Set();
for (const m of htmlText.matchAll(/([\w.$-]+\.js)/g)) if (byName.has(m[1])) htmlRefs.add(m[1]);
// the entry is the index-* script; fall back to the first html ref
const entry = [...htmlRefs].find((n) => /^index-/.test(n)) || [...htmlRefs][0];

// ---- initial-load closure (BFS over static edges from all html-referenced js)
const initial = new Set();
const queue = [...htmlRefs];
while (queue.length) {
  const n = queue.shift();
  if (initial.has(n)) continue;
  initial.add(n);
  for (const d of staticImports.get(n) || []) if (!initial.has(d)) queue.push(d);
}
const lazy = [...byName.keys()].filter((n) => !initial.has(n));

// ---- sizes -------------------------------------------------------------------
function transferSize(name) {
  const path = byName.get(name);
  for (const ext of ['.br', '.gz']) {
    if (existsSync(path + ext)) return { bytes: statSync(path + ext).size, how: ext.slice(1) };
  }
  return { bytes: gzipSync(readFileSync(path)).length, how: 'gzip*' };
}

// ---- in-edges (who statically imports a chunk) + lazy reference hint ----------
const inEdges = new Map(); // name -> Set(importers)
for (const [n, deps] of staticImports) for (const d of deps) {
  if (!inEdges.has(d)) inEdges.set(d, new Set());
  inEdges.get(d).add(n);
}
// A chunk is "also wanted by lazy code" if any lazy chunk imports it statically
// or names it (mapDeps). That is a strong hint an initial-load vendor chunk could
// be deferred — its real consumers are lazy.
function referencedByLazy(name) {
  for (const l of lazy) {
    if ((staticImports.get(l) || new Set()).has(name)) return true;
    if (readChunk(l).includes(name)) return true; // mapDeps string ref
  }
  return false;
}

// ---- vendor heuristic --------------------------------------------------------
// Vite names manualChunks/vendor chunks with a lowercase token (cmdk, recharts,
// react-vendor, forms, xterm, validation…); app chunks are PascalCase source
// names (DashboardPage) or `index`. Lowercase, non-index => likely a vendor lib.
function stem(name) { return name.replace(/-[A-Za-z0-9_]+\.js$/, '').replace(/\.js$/, ''); }
function isVendorish(name) {
  const s = stem(name);
  return s !== 'index' && /^[a-z0-9][a-z0-9._-]*$/.test(s);
}

// ---- assemble ----------------------------------------------------------------
const rank = (names) => names.map((n) => ({
  chunk: n, stem: stem(n), vendor: isVendorish(n),
  ...transferSize(n),
  importedBy: [...(inEdges.get(n) || [])],
  alsoLazy: initial.has(n) ? referencedByLazy(n) : undefined,
})).sort((a, b) => b.bytes - a.bytes);

const initialRanked = rank([...initial]);
const lazyRanked = rank(lazy);
const totalInitial = initialRanked.reduce((s, c) => s + c.bytes, 0);
const candidates = initialRanked.filter((c) => c.vendor && c.chunk !== entry);

if (asJson) {
  console.log(JSON.stringify({
    entry, totalInitialBytes: totalInitial,
    initial: initialRanked, lazy: lazyRanked, candidates,
  }, null, 2));
  process.exit(0);
}

// ---- text report -------------------------------------------------------------
const kb = (b) => (b / 1024).toFixed(1).padStart(7) + ' kB';
const line = (c) => `  ${kb(c.bytes)}  ${c.vendor ? '[vendor?]' : '         '} ${c.chunk}` +
  (c.alsoLazy ? '  ← also used by lazy chunks (deferral candidate)' : '');

console.log(`\nVite initial-load analysis — ${distDir}`);
console.log(`index.html: ${basename(dirname(indexHtml))}/index.html   entry: ${entry}`);
console.log(`\nINITIAL LOAD — ${initialRanked.length} chunks, ${kb(totalInitial).trim()} (transfer size; * = gzipped here)`);
for (const c of initialRanked) console.log(line(c));

console.log(`\nDEFERRAL CANDIDATES (vendor-looking chunks on the initial load, largest first):`);
if (candidates.length === 0) console.log('  (none — no single-library vendor chunks on the initial load)');
for (const c of candidates) {
  console.log(`  ${kb(c.bytes)}  ${c.chunk}`);
  console.log(`            imported by: ${c.importedBy.join(', ') || '(entry html only)'}`);
  console.log(`            ${c.alsoLazy
    ? 'also referenced by lazy chunks → likely deferrable; check source consumers are all lazy'
    : 'not referenced by any lazy chunk → may be genuine shared/eager vendor code'}`);
}

if (showLazy) {
  console.log(`\nLAZY CHUNKS — ${lazyRanked.length} (fetched on demand):`);
  for (const c of lazyRanked) console.log(line(c));
}
console.log(`\nNext: for each candidate, grep source for its importers and classify the leak`);
console.log(`(eager import / barrel re-export / manualChunks hoist). See diagnosis-and-fixes.md.\n`);

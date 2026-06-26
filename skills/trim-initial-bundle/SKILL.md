---
name: trim-initial-bundle
description: >-
  Find and defer vendor libraries that ship in a React + Vite app's initial
  JavaScript load but are only needed behind lazy routes/components — shrinking
  first-load size, LCP, and TTI. Works by inspecting the *built* `dist`, never
  assumptions. Use this whenever the user wants to reduce / shrink / trim bundle
  or initial-load / first-load size, speed up first load / LCP / TTI / Lighthouse
  on a Vite app, asks why a specific library is in the main / entry / index chunk,
  wants to lazy-load or defer a heavy dependency (charts like recharts/chart.js,
  rich-text or code editors like monaco/codemirror, command palettes like cmdk,
  form libraries like react-hook-form, terminals like xterm, PDF/markdown/syntax
  renderers, map or diagram libs), or wants to analyze what's bloating a Vite
  build. Reach for it even when the user only says "the app loads slowly" or "our
  JS bundle is too big" and the project uses Vite — the analysis is cheap and
  reliably finds deferrable weight. Vite/Rollup/Rolldown only (not Webpack/Next).
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# Trim the initial bundle (React + Vite)

Get heavy vendor libraries **off a React app's initial JavaScript load** when they
are only needed behind a lazy route or a click. The user downloads and parses the
initial load before the page is interactive; every kilobyte of a library they
won't use on first paint is wasted LCP/TTI.

**Scope:** Vite (including rolldown-vite) and the Rollup/Rolldown `manualChunks`
model. The diagnosis transfers to other bundlers but the *fixes* here are
Vite/Rollup-specific. If the project is Next.js or raw Webpack, stop and say so —
this skill's fix recipes won't apply.

## The one rule that matters

**Decide everything from the built `dist`, never from the source or a plan.**
Bundlers regularly contradict what the code "should" do — tree-shaking misses,
`manualChunks` hoists, barrels leak. A plausible source-level fix routinely fails
to move the library. So the loop is always: build → inspect artifacts → change →
rebuild → re-inspect. If you find yourself asserting a chunk outcome you haven't
grepped out of `dist`, stop and grep it.

## Mental model

- **Initial load** = the entry chunk + every chunk it *statically* imports
  (transitively) + the chunks `index.html` lists as `modulepreload`. A library is
  "on the initial load" exactly when its code lands in that set.
- **Lazy** = a chunk reachable *only* through a dynamic `import()`. It is fetched
  on demand, not at first paint.
- **Goal:** a library used only by lazy routes/components should live *only* in
  lazy chunks. When it leaks into the initial load, the fix is to find *why* and
  cut that path.

Two references hold the depth — read them when you reach those phases:
- `references/diagnosis-and-fixes.md` — the leak mechanisms and exact fix patterns.
- `references/verification.md` — how to prove a change worked (and didn't regress).

## Workflow

Operate as **diagnose → plan → apply-on-approval → verify**. Bundler behavior is
subtle enough that you should show the user the evidence and the proposed change
*before* editing, then prove the result after.

### Phase 1 — Build and analyze (read-only)

1. Run the project's production build for the web app (e.g. `pnpm build`,
   `npm run build`, or a UI-only script like `build:ui`). Find the output dir
   (Vite default `dist/`; check `vite.config.*` `build.outDir`).
2. Run the bundled analyzer against the output's asset dir:
   ```bash
   node <skill>/scripts/analyze-initial-load.mjs <path-to-dist>
   ```
   It finds the true entry from `index.html`, computes the entry's static import
   closure, and prints **what is on the initial load, ranked by size**, plus the
   lazy chunks and which chunks reference each. (Run with `--help` for options.)
3. From that report, pick candidates: chunks on the initial load that look like a
   **single heavy vendor library** (named like `cmdk-…`, `recharts-…`,
   `forms-…`, or a `node_modules`-derived chunk) and that you suspect are only
   needed behind a lazy boundary. Note their sizes — that's the prize.

Do not skip the analyzer in favor of eyeballing source. The whole point is that
source is misleading here.

### Phase 2 — Diagnose each candidate

For each candidate library, find **every** source importer (grep the app `src`
for the package name and the local wrapper module's path). Then classify the leak
— it is almost always one of three (full detail in `diagnosis-and-fixes.md`):

1. **Eager static import** — a component that is always mounted (layout, sidebar,
   a provider, an always-rendered widget) statically imports the library, so it
   sits in the shell.
2. **Barrel re-export that isn't tree-shaken** — a widely-imported `index`
   barrel does `export { X } from './heavy'`; Vite/Rollup do **not** reliably drop
   it even when nothing uses `X`, so the heavy module rides into every barrel
   consumer (and the shell consumes the barrel).
3. **`manualChunks` hoisting** — the library is forced into its own
   `manualChunks` vendor chunk, but it's reached only behind a lazy boundary;
   Rollup/Rolldown then **promote that vendor chunk into the initial graph**
   (most reliably when two or more lazy chunks share it). This is the
   counterintuitive one: the manualChunks entry *causes* the leak.

A single library often has more than one of these at once (e.g. an eager barrel
re-export *and* a manualChunks entry). Identify all paths before planning.

### Phase 3 — Plan and get approval

Present, per candidate: the library and its initial-load size, the leak
mechanism(s) you found (with the grep evidence), the exact files/edits proposed,
and the **projected saving** (the chunk's brotli/gzip size). Then wait for the
user to approve before editing. This gate matters because the obvious fix
sometimes doesn't move the library — better to align on the plan than to ship a
no-op.

### Phase 4 — Apply the fixes

**Fix one mechanism at a time, then rebuild and re-verify before doing more.**
Cutting a single eager path (a barrel re-export or an eager import) often takes the
library off the initial load by itself — and rebuilding tells you whether anything
else (like a `manualChunks` entry) was ever actually contributing. Changing several
things at once leads to unnecessary edits and a wrong story about what fixed it.

Match the fix to the mechanism (patterns and code in `diagnosis-and-fixes.md`):

- **A. Remove the unused barrel re-export** of the heavy module. Confirm first
  that no one imports those symbols *from the barrel* (only the leak path uses
  them). This is the same class as a dead re-export pulling a form library onto
  every page.
- **B. Lazy-split the component.** Extract the heavy-dependency subtree into its
  own module and load it with
  `const Heavy = lazy(() => import('./Heavy').then((m) => ({ default: m.Heavy })))`,
  rendering it inside `<Suspense fallback={…}>`. Pull any constants/helpers that
  the *eager* shell also needs into a small dependency-free module, so the shell
  imports those without importing the heavy child.
- **C. Remove the library's `manualChunks` entry** — but only after you've cut
  every eager path (A/B), rebuilt, and confirmed the library is **still** on the
  initial load *despite all its source consumers now being lazy* (the entry still
  statically imports the named vendor chunk). That standalone-still-eager state is
  the real signature of a `manualChunks` hoist; then removing the entry lets it fold
  into the lazy chunk that consumes it. If cutting the eager paths already removed
  the library from the initial load, **leave the `manualChunks` entry alone** —
  removing it then only renames/merges an already-lazy chunk, a change for its own
  sake. And never *add* a `manualChunks` entry to "isolate" a lazy library — that
  can hoist it to the entry.

Keep edits surgical and match the codebase's existing lazy-loading convention
(grep for existing `lazy(() => import(...))` calls and mirror their shape).

### Phase 5 — Verify against the artifacts

Rebuild and prove it (recipes in `references/verification.md`):

- The library is **not** a static import of the entry chunk, **not** in
  `index.html`'s preload set, and its code signature is **absent** from the entry
  chunk.
- It **is** present in the intended lazy chunk, and **not duplicated** across
  chunks.
- Build is clean — no `INEFFECTIVE_DYNAMIC_IMPORT` warning (that means the module
  is *also* statically imported somewhere, defeating the split).
- The app's quality gates pass (typecheck, lint, tests).
- **Compare against a clean baseline build** (stash/checkout the changes, build,
  diff the initial-load set). This separates a real win from a pre-existing leak
  and catches chunk reshuffling your change may have caused elsewhere.

Report before/after initial-load sizes for the affected library and overall.

## Pitfalls (these cost real time — internalize them)

- **Source lies; artifacts don't.** Every "obvious" source fix in this domain has
  a decent chance of not moving the chunk. Grep `dist`, don't assume.
- **`manualChunks` can hoist a lazy-only library to the entry — but prove it's the
  cause before removing it.** A manualChunk is only the culprit if the library
  stays on the initial load *after* every eager path is cut. Don't reflexively
  delete a manualChunks entry because a heavy lib is on first load — first cut the
  eager paths (barrel/eager import) and rebuild; often that alone fixes it and the
  manualChunk was innocent. And never *add* one to "isolate" a deferred lib.
- **Barrels don't reliably tree-shake heavy re-exports.** A `export { X } from
  './heavy'` in a shell-consumed barrel leaks `heavy` even when `X` is unused.
- **Static import vs lazy dep-map.** In a chunk, `from"./x-HASH.js"` is a static
  import (eager). A bare `"assets/x-HASH.js"` *string* inside the Vite
  `__vite__mapDeps`/preload array is just a lazy-dependency manifest entry — that
  is fine and expected. Don't mistake the latter for a leak.
- **There can be several `index-*.js` chunks** — the real entry plus any chunk
  built from an `index.ts`/`index.tsx` source (barrels). Always identify the true
  entry from `index.html`, not by filename.
- **One change can reshuffle other chunks.** After each edit, re-run the full
  analysis and the baseline comparison — don't trust that only your target moved.
- **Windows + Vite `emptyOutDir`:** never leave your shell `cd`'d inside `dist`
  (or any path under it) when you rebuild — the directory delete fails with
  `EPERM`. Build from the project root and use absolute paths.
- **A library used by 2+ lazy routes** may, after deferral, land in a shared chunk
  loaded by just those routes (good). Verify it didn't get re-hoisted to the entry
  and isn't duplicated into each route.

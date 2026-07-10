# Verification

How to prove a library actually left the initial load — and that you didn't break
or reshuffle anything else. Every claim here is grepped out of `dist`, because in
this domain source-level reasoning is unreliable.

## Contents
- [Step 0 — find the true entry](#step-0--find-the-true-entry)
- [Static import vs lazy dep-map](#static-import-vs-lazy-dep-map)
- [Prove the library left the initial load](#prove-the-library-left-the-initial-load)
- [Prove it's in the lazy chunk and not duplicated](#prove-its-in-the-lazy-chunk-and-not-duplicated)
- [Build cleanliness and gates](#build-cleanliness-and-gates)
- [Baseline comparison (the part people skip)](#baseline-comparison)
- [Measuring the saving](#measuring-the-saving)
- [The Windows EPERM gotcha](#the-windows-eperm-gotcha)

The analyzer script does most of step 0 and the initial-load listing for you —
run the same `scripts/analyze-initial-load.mjs` Phase 1 uses, giving its full
path (the working directory in the blocks below is your project root, not the
skill directory). The greps below are for spot-checking a specific library and
for the before/after proof.

## Step 0 — find the true entry

There can be several `index-*.js` chunks (the real entry plus chunks built from
`index.ts`/`index.tsx` barrels). Identify the entry from `index.html`, never by
filename:

```bash
DIST=path/to/dist            # the dir containing index.html
ASSETS="$DIST/assets"        # Vite default
HTML="$DIST/index.html"
# The entry module script src + any modulepreloaded chunks = the initial-load set:
grep -oE 'assets/[A-Za-z0-9_.-]+\.js' "$HTML" | sed 's#assets/##' | sort -u
entry=$(grep -oE 'assets/index-[A-Za-z0-9_-]+\.js' "$HTML" | head -1 | sed 's#assets/##')
echo "entry=$entry"
```

`index.html`'s referenced JS = what the browser fetches before interactivity.
If the library's chunk is in that list, it's on the initial load, full stop.

## Static import vs lazy dep-map

This distinction trips people up. Inside a chunk file:

- **Static import (eager):** `import{a as t}from"./heavy-HASH.js"`,
  `from"./heavy-HASH.js"`, or a **bare side-effect** `import"./heavy-HASH.js"`
  (no `from`). The third form is easy to miss and is exactly how a side-effectful
  module re-exported by a barrel (`export * from './heavy'`) leaks into a chunk.
  All three are eager — match them with `(import|from)"\./heavy-…"`, not just
  `from`. Note hashes contain `-`, so the char class must include it.
- **Lazy dep-map entry (fine):** a bare quoted string `"assets/heavy-HASH.js"`
  inside an array (Vite's `__vite__mapDeps`/preload manifest). This only tells a
  *dynamic* import which extra chunks to preload *when that dynamic import runs*.
  Seeing the library's filename as a string here is expected and not a leak.

Test for a real static import specifically:

```bash
grep -oE '(import|from)"\./heavy-[A-Za-z0-9_-]+\.js"' "$ASSETS/$entry" \
  && echo ">>> STATIC import in entry (LEAK)" || echo "no static import in entry (good)"
```

## Prove the library left the initial load

Three independent checks — all must pass:

```bash
# 1. Entry does not statically import the library's chunk
grep -oE '(import|from)"\./heavy-[A-Za-z0-9_-]+\.js"' "$ASSETS/$entry" \
  || echo "OK: entry has no static heavy import"

# 2. index.html does not preload it (hashes can contain '-', '.', '_')
grep -oE 'heavy-[A-Za-z0-9_.-]+\.js' "$HTML" || echo "OK: not preloaded"

# 3. The library's code is not INLINED in the entry. Pick a signature string that
#    is unique to the library (an internal token, a data-attr, an export name).
#    Examples: cmdk → 'cmdk-input-wrapper'; react-hook-form → 'shouldUnregister'.
grep -c '<unique-signature>' "$ASSETS/$entry"   # expect: 0
```

Check (3) matters because if you removed a `manualChunks` entry, the library no
longer has its own file — it could have folded into the **entry** (bad) or a
**lazy** chunk (good). The signature grep tells you which.

## Prove it's in the lazy chunk and not duplicated

```bash
# Which chunk(s) contain the library's code now?
grep -l '<unique-signature>' "$ASSETS"/*.js | sed 's#.*/##'
# Expect: exactly the intended lazy chunk (e.g. WidgetList-HASH.js), and NOT the entry.
# More than one app chunk containing it = duplication; investigate the import graph.
```

For a library used by 2+ lazy routes, after deferral it may live in a shared chunk
that those routes import — confirm that shared chunk is itself lazy (not in the
entry's static closure / not in `index.html`).

## Build cleanliness and gates

```bash
# No "ineffective dynamic import" warning — it means the module you lazy-imported
# is ALSO statically imported somewhere, so the split did nothing. Rollup (Vite ≤7)
# emits the code INEFFECTIVE_DYNAMIC_IMPORT; Vite 8 / Rolldown may word it
# differently, so also match the human-readable phrasing.
<build command> 2>&1 | grep -iE 'INEFFECTIVE_DYNAMIC_IMPORT|dynamic import will not move module' \
  && echo "LEAK: also static" || echo "OK: dynamic import is clean"

# Then the project's gates:
<typecheck>  &&  <lint>  &&  <tests>
```

If the project has a bundle-size budget (e.g. `size-limit`), run it — the total
initial JS should drop and stay under budget.

## Baseline comparison

This is the step that separates a real win from a fake one, and catches collateral
reshuffling. Build the **unchanged** tree and compare its initial-load set to
yours. The library you targeted may already have been on (or off) the initial load
for reasons unrelated to your edit.

**Primary: `git worktree`.** Builds the baseline exactly once, in a side directory,
so the tree with your fix is never rebuilt a second time just for this comparison —
reuse the `$DIST` build Phase 5 already produced:

```bash
ANALYZER=<path-to-skill>/scripts/analyze-initial-load.mjs   # same script as Phase 1; use its full path so it runs from the project-root cwd this block needs
BASELINE=../baseline
git worktree add "$BASELINE" HEAD    # clean checkout of HEAD — untouched by your uncommitted fix
(cd "$BASELINE" && <build command>)
node "$ANALYZER" "$BASELINE/<same relative dist path as $DIST>" > /tmp/baseline.txt
node "$ANALYZER" "$DIST" > /tmp/after.txt   # the fix build from Phase 5 — no rebuild needed
diff /tmp/baseline.txt /tmp/after.txt
git worktree remove "$BASELINE"       # add --force if build artifacts block removal
```

**Fallback: `git stash`**, for when a worktree isn't practical (no spare disk, a
workspace/submodule layout that doesn't tolerate a second checkout). This rebuilds
the fix tree a second time after popping the stash:

```bash
git stash -u
<build command>
node "$ANALYZER" "$DIST" > /tmp/baseline.txt
git stash pop                      # restore your edits
<build command>
node "$ANALYZER" "$DIST" > /tmp/after.txt
diff /tmp/baseline.txt /tmp/after.txt
```

If you can't stash the whole tree safely (e.g. unrelated uncommitted work),
snapshot just the files you touched: `cp` them aside, `git checkout` them (and
remove any new files), build the baseline, then restore your versions. Confirm
**only your target library moved** — if other chunks changed placement, a
`manualChunks` edit reshuffled the graph and you need to re-evaluate.

## Measuring the saving

Report the saving as the **brotli (or gzip) size** of what left the initial load —
that's what users actually download. Vite with a compression plugin writes
`*.js.br` / `*.js.gz` next to each chunk; otherwise gzip the chunk yourself:

```bash
# Brotli/gzip sibling if present:
ls -l "$ASSETS"/heavy-*.js.br "$ASSETS"/heavy-*.js.gz 2>/dev/null
# Else approximate:
gzip -c "$ASSETS"/heavy-*.js | wc -c
```

State both the per-library saving and the change in total initial JS (sum of the
initial-load chunks before vs after).

## The Windows EPERM gotcha

On Windows, Vite's `emptyOutDir` deletes `dist` at the start of each build. If any
process — including your own shell — has its current directory **inside** `dist`,
the delete fails:

```
Error: EPERM, Permission denied: ...\dist\ui\assets
    at emptyDir (.../vite/.../node.js)
```

Avoid it: never `cd` into `dist` (or `dist/assets`) during the session — run all
greps with absolute paths from the project root, and run the build from the
project root. If you hit it, move the shell out (`cd` to the repo root) and
rebuild; the lock clears.

# Diagnosis and fixes

The three ways a lazy-only library leaks into the initial load of a Vite build
(Rollup on Vite ≤7, Rolldown on Vite 8), how to tell which you're facing, and the
exact fix for each. A single
library often has more than one path at once — find and cut all of them.

## Contents
- [Finding every importer](#finding-every-importer)
- [Mechanism 1 — eager static import](#mechanism-1--eager-static-import)
- [Mechanism 2 — barrel re-export not tree-shaken](#mechanism-2--barrel-re-export-not-tree-shaken)
- [Mechanism 3 — manualChunks hoisting](#mechanism-3--manualchunks-hoisting)
- [Fix A — remove the dead barrel re-export](#fix-a--remove-the-dead-barrel-re-export)
- [Fix B — lazy-split the component](#fix-b--lazy-split-the-component)
- [Fix C — remove the manualChunks entry](#fix-c--remove-the-manualchunks-entry)
- [Why these happen (so you can reason, not memorize)](#why-these-happen)

## Finding every importer

Before classifying, enumerate where the library is reached from. Two greps:

```bash
# 1. Direct imports of the npm package (and a local wrapper, if any)
rg -n "from '<pkg>'|from \"<pkg>\"|require\('<pkg>'\)" src
# e.g. the package, plus the project's wrapper module that imports it:
rg -n "from '<pkg>'" src ; rg -n "from '.*/<wrapper>'" src

# 2. Is it re-exported by any barrel (index.ts/tsx)?
rg -n "from '\\./<wrapper>'|export \\* from '\\./<wrapper>'" src/**/index.{ts,tsx}
```

Then ask of each importer: **is this module part of the always-loaded shell, or
only reached behind a lazy boundary?** Shell = App root, router shell, layout,
sidebar, providers, anything rendered before/around the routed page, and any
barrel those import. Lazy = a route loaded via `lazy()`/`import()`, or a component
behind a `React.lazy`/dynamic `import()`.

If *every* importer is lazy and the library is still on the initial load, the leak
is structural (Mechanism 2 or 3), not a real eager use.

## Mechanism 1 — eager static import

**Symptom:** a shell component (always mounted) does
`import { Thing } from '<heavy>'` at module top level. The library is genuinely in
the eager graph because eager code references it.

**Confirm:** the importer is reachable from the entry without crossing a dynamic
`import()`. In `dist`, the library's code signature appears *inlined in the entry
chunk* (or in a chunk the entry statically imports).

**Fix:** Mechanism-1 leaks are real usage — defer them with **Fix B** (move the
heavy subtree behind a lazy boundary). You can't tree-shake away a real eager use;
you have to make the use itself lazy.

## Mechanism 2 — barrel re-export not tree-shaken

**Symptom:** a widely-imported barrel (`components/ui/index.tsx`, `hooks/index.ts`,
etc.) contains `export { X, Y } from './heavy'` (or `export * from './heavy'`).
Nothing imports `X`/`Y` *from the barrel* — yet the heavy module rides into every
chunk that imports anything from the barrel, and the shell imports the barrel.

**Confirm:**
- Grep shows the only references to the barrel's heavy re-exported symbols are the
  barrel itself and the heavy module's own definition — **no consumer** imports
  them from the barrel.
- Despite that, `dist` shows the heavy library on the initial load.
- Vite/Rollup did not drop the re-export. (This is common: re-exports keep the
  binding "live" enough that conservative tree-shaking — especially without a
  `sideEffects: false` guarantee on the package — retains the module.)

**Fix:** **Fix A** — delete the dead re-export. Consumers that genuinely need the
heavy symbols should import them directly from the heavy module, not via the
shared barrel.

## Mechanism 3 — manualChunks hoisting

**Symptom:** `vite.config` has a `manualChunks` entry (Vite ≤7 / Rollup) — or an
`advancedChunks` / `codeSplitting` group (Vite 8 / Rolldown) — that forces the
library into its own vendor chunk (e.g. `['heavy', /[\\/]heavy[\\/]/]`), the library
is reached **only** behind a lazy boundary, yet `dist` shows the entry **statically
importing the heavy vendor chunk** (and `index.html` preloading it).

**Confirm:**
- All source importers are lazy (Mechanism-1 check fails — no eager use).
- The entry chunk has `from"./heavy-HASH.js"` (a static import), not merely a
  `mapDeps` string reference.
- A counter-example in the same build: another manual-chunked lib reached via a
  lazy *route* stays lazy — so it's not that manualChunks is always wrong, it's
  this lib's lazy topology (often: shared by 2+ lazy chunks, or lazied from inside
  an eager component) that triggers hoisting.

**Why:** Rollup/Rolldown treat a named `manualChunks` chunk as a first-class
output. When such a chunk is needed by more than one consumer — or by a lazy
chunk that the entry also relates to — the linker can satisfy it by importing the
vendor chunk from the *initial* chunk rather than duplicating it per lazy chunk.
The result: your "isolation" chunk becomes part of first load.

**Fix:** **Fix C** — remove the manualChunks entry. Without it, Rollup folds the
library into the lazy chunk that imports it (or a shared chunk loaded only by the
lazy consumers), which is exactly where you want it.

## Fix A — remove the dead barrel re-export

```diff
// components/ui/index.tsx  (a barrel many shell components import)
- export {
-   Command, CommandInput, CommandList, CommandItem, CommandGroup, CommandEmpty,
- } from './command';   // './command' pulls in cmdk
```

Pre-flight: prove no consumer uses those symbols *via the barrel* — check the
import statement as a unit, since a real multi-line named-import block (specifiers
and the `from` clause on different lines) would otherwise slip past a single-line grep:

```bash
rg -U -n "import \{[^}]*Command(Input|List|Item|Group|Empty)?\b[^}]*\}\s*from\s*['\"]@/components/ui['\"]" \
  src --type ts --type tsx   # expect: no matches
```

The component that genuinely uses the heavy module keeps importing it **directly**
(`import { Command } from './command'`), so it's unaffected. After removal, the
heavy module has no path from the shell-consumed barrel.

## Fix B — lazy-split the component

Split the heavy-dependency subtree out of the always-mounted component into its
own module, and load it lazily. Extract anything the eager parent *also* needs
(constants, tiny pure helpers) into a dependency-free module so the parent doesn't
transitively import the heavy child.

**Before** — `WidgetBar.tsx` (always mounted) imports the heavy lib directly:

```tsx
import { Command, CommandInput, CommandItem } from './command'; // heavy (cmdk)

const BADGE = 'bg-slate-600 text-white';        // also used by the trigger button

export const WidgetBar = (props) => (
  <Popover>
    <PopoverTrigger><span className={BADGE}>…</span></PopoverTrigger>
    <PopoverContent>
      <Command>{/* …heavy subtree… */}</Command>
    </PopoverContent>
  </Popover>
);
```

**After** — three files:

```ts
// WidgetBar.constants.ts  — dependency-free, safe for the eager shell
export const BADGE = 'bg-slate-600 text-white';
```

```tsx
// WidgetList.tsx  — the ONLY module that imports the heavy lib
import { Command, CommandInput, CommandItem } from './command'; // heavy lives here
import { BADGE } from './WidgetBar.constants';
export const WidgetList = (props: WidgetListProps) => (
  <Command>{/* …heavy subtree, props piped in… */}</Command>
);
```

```tsx
// WidgetBar.tsx  — eager shell; no heavy import anymore
import { lazy, Suspense } from 'react';
import { BADGE } from './WidgetBar.constants';

const WidgetList = lazy(() =>
  import('./WidgetList').then((m) => ({ default: m.WidgetList })),
);

export const WidgetBar = (props) => (
  <Popover>
    <PopoverTrigger><span className={BADGE}>…</span></PopoverTrigger>
    <PopoverContent>
      {/* Radix mounts children only when open → heavy chunk fetched on first open */}
      <Suspense fallback={<Spinner />}>
        <WidgetList {/* pipe the props the list needs */} />
      </Suspense>
    </PopoverContent>
  </Popover>
);
```

Notes:
- Match the codebase's existing lazy convention. Many Vite/React apps use the
  `.then((m) => ({ default: m.Name }))` unwrap for named exports — grep for it and
  mirror it rather than adding a default export.
- The `<Suspense fallback>` should reuse whatever loading affordance the component
  already shows, for visual consistency.
- Only remove imports/vars from the parent that *your* extraction made unused.
- If the heavy subtree is inside a popover/dialog/menu whose library mounts
  children lazily (Radix, etc.), the dynamic import fires on first open — ideal.

## Fix C — remove the manualChunks entry

**Prerequisite: confirm the manualChunk is actually the cause.** Apply this only
after Fixes A/B have cut every eager path, you've rebuilt, and the library is
**still** on the initial load — i.e. the entry still statically imports the named
vendor chunk even though all its source consumers are now lazy. If cutting the
eager paths already removed it from the initial load, the manualChunk was innocent
— leave it. Removing a manualChunk that isn't hoisting only renames/merges an
already-lazy chunk; it's churn, not a fix.

```diff
// vite.config.ts  — Vite ≤7 / Rollup
  build: {
    rollupOptions: {
      output: {
        manualChunks: (id) => {
          if (!id.includes('node_modules')) return;
          const chunks = [
-           ['heavy', /[\\/]heavy[\\/]/],
            ['react-vendor', /[\\/](react|react-dom|react-router-dom)[\\/]/],
            // …
          ];
          for (const [name, test] of chunks) if (test.test(id)) return name;
        },
      },
    },
  },
```

**On Vite 8 / Rolldown** the object-form `manualChunks` is removed and the function
form is deprecated; the same grouping lives in Rolldown's `output.advancedChunks`
(being renamed `output.codeSplitting`) as a `groups` array of `{ name, test }`
(where `test` is a regex matched against the module id). The fix is identical —
delete the deferred library's group from that array. See Rolldown's
[Manual Code Splitting](https://rolldown.rs/in-depth/advanced-chunks) docs for the
current syntax.

After removal, the library folds into the lazy chunk that imports it. You lose a
separately-named chunk (less "trackability" in the build output), but you gain the
actual goal: it's off the initial load. That trade is almost always right for a
deferred library.

Keep `manualChunks` entries for libraries that are legitimately shared across the
initial load (e.g. `react-vendor`) — those benefit from a stable cacheable chunk.
The rule of thumb: **manualChunks is for vendor code that's on first load anyway;
it is the wrong tool for deferring something.**

## Why these happen

You'll fix these faster if you hold the reasons, not the rules:

- **Tree-shaking is conservative across re-exports.** Without a hard
  `sideEffects: false` signal, a bundler keeps a re-exported module rather than
  risk dropping a side effect. So a barrel re-export is a near-guaranteed retain.
- **`manualChunks` (Rollup) / `advancedChunks` (Rolldown) is an output-grouping directive, not a "make lazy" directive.**
  It says "put these modules in a chunk named X," and the linker then wires X into
  whatever chunks need it — including initial ones. It cannot know you intended X
  to be lazy.
- **Lazy boundaries are about the *import graph*, not file structure.** A library
  is lazy iff the only path to it crosses a dynamic `import()`. Any eager static
  path — through a component, a barrel, or a hoisted vendor chunk — defeats it.

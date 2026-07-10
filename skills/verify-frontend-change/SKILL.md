---
name: verify-frontend-change
description: >-
  Use this skill EVERY time a frontend/UI change is about to be called done,
  fixed, or working — in a web app, a successful edit, a clean build, or an HMR
  reload is NOT evidence. It verifies the change in a real Chrome via the Chrome
  DevTools MCP server (console errors and a performance trace), with a
  fix-and-rerun loop on any failure. Trigger after any change that alters what
  the browser loads or does — components, pages, styles, routes, client state,
  bundler/dev-server config, client dependencies, static assets or the HTML
  shell — even a "trivial" one-liner — and on asks like "verify it works",
  "check it in the browser", "make sure nothing broke", "does it actually
  render". Do NOT trigger for backend-only, CLI, test-only, or docs-only
  changes, for running an existing e2e/test suite, for native (React Native) UI,
  when there is no runnable web frontend, or when a failure is already known and
  needs root-cause diagnosis first (systematic-debugging).
---

# Verify frontend change

A UI change is not done when the edit applies, the types check, or the build goes
green. Those prove the code *compiles*; they say nothing about whether the page
renders, the interaction behaves, the console stays clean, or the change dragged
something heavy into the load. The only evidence that counts is watching the change
work in a real browser.

**The iron law: never report a frontend change as done, fixed, or working until the
whole verification loop below has passed — every step, in one uninterrupted pass.**
"Should work now", "the build passes, so it's done", and "HMR picked it up" are all
banned conclusions.

There are exactly two acceptable end states:

1. **Verified** — every step passed in the same pass; report done *with the evidence*.
2. **Blocked** — a step cannot run (no Chrome DevTools MCP server, an auth wall with
   no test credentials, a component not mounted on any route, no runnable frontend in
   this environment). Report the change as **unverified**, name precisely what was
   and wasn't checked, and what's needed to finish. Blocked is not done — and it
   still gets the same cleanup as Verified (stop a dev server you started).

There is no third state. A change that "probably works" is a change you haven't
verified yet.

## Requirements

This skill drives Chrome through the **Chrome DevTools MCP server**
([`chrome-devtools-mcp`](https://github.com/ChromeDevTools/chrome-devtools-mcp)).
At Step 0, confirm its tools (typically named `mcp__chrome-devtools__*`) are
available. If they aren't, stop and tell the user to install it —

```
claude mcp add chrome-devtools --scope user npx chrome-devtools-mcp@latest
```

— then restart the session and rerun. Do not substitute "I read the code again
carefully" for the browser. Missing server → end state is **Blocked**, never Verified.

`references/chrome-devtools-mcp.md` in this skill has the tool cheatsheet (exact tool
names, tracing workflow, console reading, element targeting). Read it before your
first browser action of the session.

## The verification loop

Run the steps in order. **Any failure at any step: diagnose it, fix it, and rerun
from Step 1** — not from the step that failed. ("From the top" and "from Step 1"
mean the same thing: Step 0's what-changed analysis stands across reruns, unless
the fix changed which files or routes are affected — then redo it too.) A fix can
invalidate earlier steps (a config edit breaks server boot; a component fix changes
the route's console output), and evidence from before the fix proves nothing about
the code as it now stands. Done means all steps passed *after* the last edit.

### Step 0 — Preflight

- Confirm the Chrome DevTools MCP tools are available (see Requirements).
- Identify what changed and where it should be visible: which files, which
  component(s), which route(s). Trace a changed component upward through its
  importers to the page/route that mounts it (router config, `pages/`/`app/`
  directory, route elements). If nothing mounts it, that's a **Blocked** finding —
  say so rather than verifying an unrelated page.
- Find the dev command and check whether a server is already running —
  `references/dev-server-playbook.md` covers detection, ports, and reuse rules.

### Step 1 — Start the dev server

Start it as a background task (or reuse a running one per the playbook), wait for
the ready line, and **take the URL from the server's own output** — dev servers
silently hop ports when the default is busy. A crash or fatal error on boot is a
failure of this step: read the output, fix the cause, rerun from Step 1.

### Step 2 — Open the page

Navigate to the route where the change lives. Confirm the page actually rendered —
take a snapshot (and a screenshot when layout/visuals are the point) and check that
the changed element is present. A blank page, an error overlay (Vite/Next print
compile errors into the browser), or a missing element is a failure. If the route
sits behind a login, use the project's documented dev/test credentials (seed
scripts, `.env.example`, README); if there are none, that's **Blocked** — never
invent credentials or claim the page was verified.

### Step 3 — Interact with the change

Exercise the changed behavior itself, not just the page it lives on:

- Behavior change → perform it: click the new button, submit the form with real
  input, toggle the state, trigger the validation, open the modal.
- Pure rendering/style change → verify the rendering: snapshot + screenshot,
  hover if hover styles changed, resize the page if responsiveness changed.
- Multi-route change → repeat Steps 2–3 per affected route.

After each interaction, confirm the *expected* result appeared (wait for the
element/text, re-snapshot). An interaction that does nothing, throws, or produces
the wrong UI state is a failure.

### Step 4 — Console gate: zero new errors

The console tool reports messages **since the last navigation** — a redirect after
a form submit, a full-page link click, or moving to the next route wipes everything
from before it. So read the console **once per navigation, not once per pass**:
after each fresh load and the interactions on it, *before* anything that navigates
again. For multi-route changes, fold the console read into each route's Step 2–3
cycle. The gate applies to the union of all reads in the pass:

- **Any error attributable to the change = fail.** Attributable means: its stack
  or source file is one you touched, it fires when the changed behavior runs, or it
  did not occur before the change. **When you can't tell, treat it as yours** — the
  burden of proof is on calling it pre-existing, not on calling it new.
- Pre-existing errors (fire on routes untouched by the change, stack entirely in
  code you didn't touch) don't block, but report them explicitly — never silently.
- New warnings caused by the change (React key/hydration/act warnings, deprecation
  notices from an API you introduced): report them with the verdict; fix the ones
  that indicate real defects (hydration mismatch is a defect).

### Step 5 — Performance trace

Record a Chrome DevTools performance trace of the affected page — reload-and-trace
with auto-stop by default; when the change is about interaction cost (a click
handler, INP), trace around the interaction instead (see the reference). Then read
what came back — the Core Web Vitals summary and the insights (LCP breakdown,
render-blocking resources, layout shift culprits, long tasks).

- The trace **failing to record** is a step failure — fix the environment and rerun.
- A **regression attributable to the change** is a step failure: a render-blocking
  import you added, a long task inside your new code, layout shift from your
  component, the LCP element you touched getting dramatically slower. Fix and rerun
  from Step 1.
- Otherwise the step passes — report LCP, CLS, and any notable insight in the
  verdict. Two honesty caveats: dev-mode numbers (unminified, no prod optimizations)
  are relative signals, not production Web Vitals — when the change is
  performance-sensitive, offer a follow-up trace against the production build
  (`vite preview`, `next start`); and with no pre-change trace to compare against,
  call absolute numbers "current", not "unchanged".

### Verdict

Only when Steps 1–5 all passed in the same pass, report done — with evidence, not
adjectives:

```
Verified in the browser (http://localhost:5173/settings):
- Interacted: opened the new theme picker, selected "dark", saved — persisted
  after reload.
- Console: 0 errors, 0 new warnings (1 pre-existing 404 for /favicon.ico, also
  present on routes this change doesn't touch).
- Trace: LCP 1.1s, CLS 0.00; no long tasks from the new code (dev-mode numbers).
- Dev server: started by me, now stopped.
```

Then clean up — in **both** end states, Verified or Blocked: stop the dev server if
you started it; leave it untouched if you reused it.

## When a fix doesn't stick

Fixing a failure and rerunning is the normal path — once or twice. **After 3
fix-and-rerun cycles on the same failing step, stop.** Repeated failed fixes mean
the problem isn't where you're patching; question the approach instead of trying a
4th (if the `systematic-debugging` skill is installed, switch to it — its root-cause
discipline is exactly this situation). Report honestly: what was tried, what still
fails, current state of the working tree.

## Rationalizations

| Excuse | Reality |
|--------|---------|
| "The edit applied and the build is green." | The compiler checks types, not behavior. Blank pages and dead buttons build fine. |
| "It's a one-line CSS change." | One-liners break layouts, stacking contexts, and dark mode. The loop costs ~2 minutes. |
| "HMR already reloaded it — looked fine." | HMR hides boot errors and holds stale module state. Only a fresh full load counts. |
| "The console errors were probably already there." | Probably isn't a triage. Attribute each error or treat it as yours. |
| "A perf trace is overkill for this." | It's one tool call, and it's the only step that sees the 300 kB import your change dragged into first load. |
| "I'll verify after the next change too — batch them." | Batching destroys attribution: when it breaks, you no longer know which change did it. Verify per change. |
| "I can't verify (no MCP / auth wall), so I'll just call it done." | Blocked is a valid, honest end state. Fake-verified is not. |
| "Step 4 failed but my fix is obviously right — resume at Step 4." | The fix is a new change. Evidence gathered before it is void. Rerun from Step 1. |

## References

- `references/chrome-devtools-mcp.md` — install, exact tool names, snapshot/uid
  targeting, console reading, the trace workflow and how to read insights. Read
  before your first browser action.
- `references/dev-server-playbook.md` — find the dev command (any package manager,
  monorepos, non-JS frameworks), reuse-vs-start rules, ready-line patterns, port
  hopping, cleanup, Windows notes. Read at Steps 0–1.

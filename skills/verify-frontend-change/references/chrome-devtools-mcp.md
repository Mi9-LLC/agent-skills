# Chrome DevTools MCP cheatsheet

The [`chrome-devtools-mcp`](https://github.com/ChromeDevTools/chrome-devtools-mcp)
server (published by the Chrome DevTools team) lets the agent drive a real Chrome:
navigate, click, read the console, record performance traces. This file covers the
subset the verification loop needs. Tool names below are verbatim from the server's
tool reference as of v1.5.0 (July 2026) — if a call fails as unknown, list the
available tools and adapt rather than guessing older names (e.g. `emulate_cpu` /
`emulate_network` were consolidated into `emulate`).

## Install and availability

Registered under the server name `chrome-devtools`, tools appear as
`mcp__chrome-devtools__<tool>` (e.g. `mcp__chrome-devtools__navigate_page`). The
user may have registered it under a different server name — what matters is that
tools with these names exist, not the prefix.

If none are available, give the user the official command and stop (end state:
**Blocked**):

```
claude mcp add chrome-devtools --scope user npx chrome-devtools-mcp@latest
```

or the JSON equivalent in `.mcp.json` / MCP settings:

```json
{ "mcpServers": { "chrome-devtools": { "command": "npx", "args": ["-y", "chrome-devtools-mcp@latest"] } } }
```

Needs Node 20.19+ (or 22.12+/23+) and a current stable Chrome. Useful server flags
when the user configures it: `--headless` (no visible window), `--isolated`
(temporary profile), `--viewport 1280x720`, `--channel stable|beta|dev|canary`,
`--browser-url` (attach to an already-running Chrome).

## Tools per loop step

| Loop step | Tools |
|---|---|
| Open the page (Step 2) | `new_page`, `navigate_page`, `list_pages`, `select_page`, `close_page`, `wait_for` |
| See what rendered (Steps 2–3) | `take_snapshot` (a11y-tree text + uids), `take_screenshot` (visual evidence) |
| Interact (Step 3) | `click`, `fill`, `fill_form`, `hover`, `drag`, `press_key`, `type_text`, `upload_file`, `handle_dialog`, `wait_for` |
| Console gate (Step 4) | `list_console_messages`, `get_console_message` |
| Performance trace (Step 5) | `performance_start_trace`, `performance_stop_trace`, `performance_analyze_insight` |
| Responsive / conditions checks | `resize_page`, `emulate` (CPU/network throttling) |
| Diagnosis helpers | `evaluate_script`, `list_network_requests`, `get_network_request` |

## The uid interaction model

`take_snapshot` returns a text rendering of the page's accessibility tree where
every element carries a `uid`. Interaction tools (`click`, `fill`, `hover`, …)
target elements **by that uid** — there is no CSS-selector clicking.

The working rhythm:

1. `take_snapshot` → find the element (by role/name/text) → note its uid.
2. Act on it (`click {uid}`, `fill {uid, value}`, …).
3. `wait_for` the expected text/condition, then **re-snapshot before the next
   action** — uids belong to the snapshot they came from; after navigation or a
   re-render, stale uids error or hit the wrong element.

A snapshot is also your rendering evidence: the changed element should be *in* it.
Missing from the snapshot but present in the source usually means a conditional
render or a route mismatch — investigate before interacting. For visual changes
(layout, color, spacing) pair the snapshot with `take_screenshot`, since the a11y
tree won't show styling.

## Reading the console (Step 4)

`list_console_messages` returns the messages **since the last navigation** of the
selected page. That cuts both ways: the fresh load at the start of a pass scopes
out stale pre-fix messages, but any *further* navigation (a redirect after a form
submit, a link click, the next route of a multi-route change) silently wipes what
came before it. So read the console once per navigation — after each load and the
interactions on it, before anything that navigates again — and gate on the union.
Optional `types` filter narrows to e.g. errors; when triaging, read everything —
warnings carry hydration/deprecation signals. `get_console_message` fetches one
message in full when the list view truncates; stack traces are source-mapped, which
is what lets you attribute an error to a changed file.

## Recording the trace (Step 5)

```
performance_start_trace { reload: true, autoStop: true }
```

- `reload: true` — trace a full fresh load of the selected page (what you want:
  the change's cost is in the load path, not in an idle tab).
- `autoStop: true` — recording stops itself once the page settles; otherwise call
  `performance_stop_trace` after exercising the interaction you want profiled
  (use that form when the change is about interaction cost, e.g. INP on a click).

The result summarizes **Core Web Vitals — LCP, INP, CLS —** plus a list of named
insights (LCP breakdown, render-blocking requests, layout-shift culprits, long
tasks, document latency). Drill into any of them with
`performance_analyze_insight { insightName }` before deciding pass/fail — the
insight names the responsible resource or script, which is how you tell "my
change did this" from ambient dev-server noise.

Judging the result:

- **Attributable regression = step failure.** The insight or long task points at
  code/resources your change introduced (your new import render-blocking, your
  component shifting layout, your handler's long task).
- **Ambient result = pass with numbers reported.** Dev servers are unminified and
  unoptimized; absolute numbers run worse than production. Report them as
  "current, dev-mode" figures — never as proof the change costs nothing.
- When performance *is* the point of the change, offer a follow-up trace against
  the production build (`npm run build` + `vite preview` / `next start`, then the
  same trace against that URL) — those numbers are comparable to real Web Vitals.

`lighthouse_audit` also exists on current server versions; it's a heavier,
opinionated adjunct — the loop's required artifact is the trace, but a Lighthouse
run is a reasonable extra when the user asks for scores.

## Practical notes

- **One page at a time**: tools act on the *selected* page. After `new_page` or
  when several tabs exist, confirm the target with `list_pages` / `select_page`
  before snapshotting — acting on the wrong tab produces convincingly wrong
  evidence.
- **Error overlays**: Vite/Next compile errors render as a full-page overlay; the
  snapshot will show its text. That's a Step 2 failure with the diagnosis included
  — read it, fix, rerun.
- **Dialogs block everything**: a native `alert`/`confirm` freezes the page until
  `handle_dialog` deals with it. If tools suddenly hang, check for a dialog.
- **Failed network requests** (`list_network_requests`) often explain console
  errors — a 404'd chunk or CORS-blocked API call is the root cause behind a red
  console line that looks like a code bug.

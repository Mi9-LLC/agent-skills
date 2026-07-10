---
name: retro
description: >-
  Generate a data-grounded engineering retrospective from the repo's git
  history — commits, velocity, work sessions, commit-type mix, churn hotspots,
  test ratio, PR sizes, focus score, streaks, per-author stats, AI-assisted
  share — where every number is computed by a bundled script, never estimated.
  Trigger for ANY summarize-our-work-over-a-time-window ask: "what did we ship
  this week", "weekly retro", "engineering retrospective", "team velocity",
  "commit stats for the last N days", "who worked on what lately", "how
  productive were we this sprint", "summarize the last two weeks of work", or
  trend asks like "are we shipping faster than last month" (compare mode). Do
  NOT trigger for reviewing or fixing code, for single-commit questions plain
  git log/show answers (e.g. "what changed in commit X", "who touched this
  file"), or for performance-review / HR-evaluation asks about individuals —
  this skill reports team activity, it does not appraise people.
allowed-tools: Bash, Read, Write
disallowed-tools: Edit, NotebookEdit
---

# retro

Engineering retrospective for the current git repository. A bundled
zero-dependency Node script (`scripts/git-retro.mjs`, Node >= 18) computes
**every metric deterministically** from git history and emits one JSON
document; your job is only to turn that JSON into a candid, readable
narrative. This split exists because models fabricate plausible-looking
numbers when asked to do arithmetic over log output — here that is
structurally impossible: if a number is not in the JSON, it does not go in
the retro.

## The iron rule

**Every number in the retro comes from the script's JSON output.** Never
recompute, estimate, extrapolate, or "round for readability" beyond what the
JSON already gives you. If a metric you want is missing or `null`, say it is
unavailable — do not derive a substitute. This also means: do not run your
own `git log` arithmetic alongside the script; the script is the single
source of numbers.

## Read/Write contract

- **Read-only on the repository.** The script only reads git history (plus
  one best-effort `git fetch`); it never changes source files, git state, or
  configs.
- **Write exactly one thing, only when saving:** with `--save`, the script
  writes the JSON snapshot itself, and you may then Write the markdown
  report to `docs/retros/<YYYY-MM-DD>-retro.md`. That file is the only thing
  you ever Write, and only on an explicit save ask. **Never commit or push.**
- Default is terminal-only: the retro goes into the conversation, no files.

## How to run

```bash
node ${CLAUDE_SKILL_DIR}/scripts/git-retro.mjs
```

Pick flags from what the user asked for:

| User intent | Command |
|-------------|---------|
| Retro for the last week (default) | *(no flags — 7-day window)* |
| A different window | `--window 24h` / `--window 14d` / `--window 2w` |
| "vs last week" / trend / are-we-improving | `--compare` (adds the prior same-length window + deltas) |
| Keep a record of this retro | `--save` (JSON snapshot to `docs/retros/`; then you Write the markdown report next to it) |
| Snapshot somewhere specific | `--save <dir>` |
| Measure against a specific branch | `--base <ref>` (default: `origin/<default-branch>`, auto-detected) |
| Offline / air-gapped repo | `--no-fetch` |

Run with `-h` for every option. Times in the JSON are the runner's local
timezone; report them as-is and never override `TZ`.

## Honesty guards — report them, verbatim

The JSON carries a `guards` object. These are not noise to smooth over; they
are the difference between a retro and a hallucination. Carry any true guard
into the narrative as a caveat, in plain words:

- `zeroCommits` — the window has no commits. Say exactly that and suggest a
  wider window (`--window 14d`). **Never pad a quiet window with narrative.**
- `staleBase` — the newest commit on the base ref predates the window; the
  local ref is probably behind the remote (or the clock is off). Recommend a
  manual `git fetch` and note the retro may under-report.
- `fetchFailed` / `noRemote` — the freshness of the base could not be
  verified (offline, or no `origin`). Disclose it in one line.
- `detachedHead` — informational; mention only if it affects the base choice.
- `shallowClone` — streak numbers are unreliable; say so where streaks appear.

Under `--compare` there is no top-level `guards` key — check `current.guards`
and `prior.guards` separately; they can differ.

## Narrative structure

Open with a **tweetable one-liner** (one line, from JSON values only, e.g.
`Week of Jul 1: 47 commits (3 contributors), 3.2k LOC, 38% tests, 12 PRs, peak: 22:00 | streak 12d`),
then these sections, in order:

1. **Summary table** — commits, contributors, insertions/deletions/net LOC,
   files touched, active days, test ratio, sessions, PRs, AI-assisted share,
   streaks. Markdown table, values straight from the JSON.
2. **Time & session patterns** — the hourly histogram (render as a small
   text bar chart from `hourly`), peak hours, dead zones, and what the
   deep/medium/micro session split says about focus time. Sessions are
   detected per author (45-minute gap), so speak of them per person or as
   team totals — never as one interleaved stream.
3. **Shipping velocity** — commit-type mix (merges excluded), PR count and
   size buckets (note they are approximate — the JSON marks `approx: true`;
   if `prs.diffCapped` is true, say N merges (`prs.skipped`) were excluded
   from sizing entirely, not just approximated), and the `fixRatioHigh` flag
   if set: a fix share above 50% signals ship-fast-fix-fast and possible
   review gaps. Call out fix-chains (repeated fixes on the same area) when
   hotspots corroborate.
4. **Code-quality signals** — test ratio, test files changed, churn hotspots
   (files changed 5+ times), test-vs-prod tags on the hotspot list.
5. **Focus & ship of the window** — focus score with its modal directory
   (higher = deeper focused work, lower = scattered context-switching), and
   the highest-LOC PR/commit as "ship of the window": what it was, who
   shipped it, why it matters (infer the *why* from subjects/paths — that
   part is narrative, not numbers).
6. **Your week** — a personal deep-dive for the runner (`isCurrentUser` in
   `authors`): their commits, LOC, test ratio, top areas, peak hour, biggest
   commit, session pattern, personal streak. First person: "your peak
   hours…".
7. **Team leaderboard** — one table, sorted by commits, current user first,
   **stats only**: commits, +/−, net, test ratio, top area. No per-person
   commentary, praise, or growth notes — improvement talk stays team-level.
8. **Top 3 team wins** — highest-impact things shipped, each anchored to a
   PR/commit from the JSON: what, who, why it matters.
9. **3 things to improve** — specific and actionable, anchored in the data
   (e.g. "test ratio fell to 12% while `src/payments/` churned 9 times"),
   and **always aimed at the team, never at a named person**.
10. **3 habits for next week** — small, practical, each adoptable in under
    five minutes; at least one team-oriented.
11. **Comparison table** *(only with `--compare`)* — prior vs current with
    the script-computed deltas and direction arrows; two sentences on the
    biggest improvement and the biggest regression.

## Tone

- Candid, no coddling — but anchored in actual commits and JSON values, not
  vibes. Skip generic praise; say exactly what was good and why.
- Never rank or compare teammates against each other negatively, and never
  aim an improvement at a named person; individuals get stats, the team gets
  the coaching. Decline politely if the user asks to grade an individual —
  that is a performance-review ask, out of scope by design.
- Frame the AI-assisted share neutrally ("41% of commits were AI-assisted"),
  no judgment either way.
- 1,500–2,500 words. Tables and code blocks for data, prose for meaning.
- A solo repo gets the same retro minus the leaderboard/team sections — it
  is personal, not "a team of one".

## Saving (`--save` flow)

1. Run the script with `--save` — it writes the collision-safe JSON snapshot
   (`docs/retros/<YYYY-MM-DD>-<n>.json`) itself.
2. Write your finished narrative to `docs/retros/<YYYY-MM-DD>-retro.md`. If
   that file already exists (e.g. a second `--save` run today), don't
   overwrite it — use `docs/retros/<YYYY-MM-DD>-retro-2.md` (then `-3`, …)
   instead.
3. Tell the user both paths. Do not commit them.

Trends need no persistence: `--compare` recomputes the prior window live
from git, so it works even on a first run.

## When NOT to use this skill

- Code review, bug fixing, or any ask to change code — this skill only
  reports history.
- One-off git questions (`what changed in HEAD~1`, `who wrote this
  function`) — plain `git log` / `git blame` answers those faster.
- Performance reviews, promotion cases, or "who is my weakest engineer" —
  commit counts do not measure engineers, and this skill will not pretend
  they do.

---

Adapted from the `/retro` skill in
[`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT, © 2026 Garry
Tan). Rebuilt for this catalog: a deterministic script replaces
model-computed arithmetic (and gstack's anti-fabrication pre-flight prose),
gstack-state integrations (learnings, Greptile, telemetry, global mode) are
dropped, and per-person praise/growth critiques are replaced by stats-only
leaderboards with team-level coaching.

---
name: health
description: >-
  Run every quality gate the project already has — typecheck, lint, tests,
  dead-code, shell lint — through a bundled script that scores each gate
  0–10, computes a weighted composite health score, and tracks the trend
  against saved history; every number is computed by the script, never
  estimated. Trigger for ANY whole-project quality-overview ask: "check
  project health", "how healthy is the codebase", "quality dashboard", "run
  all the quality gates", "code health score", "full quality check", or
  trend asks like "are we getting better or worse". Do NOT trigger for
  fixing the findings (that edits code — sonar-issue-fix), for running a
  single gate ("just run the tests" needs no dashboard), for setting up CI
  pipelines, or for hosted SonarCloud/SonarQube results (sonar-issue-check).
allowed-tools: Bash, Read, Write
disallowed-tools: Edit, NotebookEdit
---

# health

A local quality-gate dashboard for the current repository. A bundled
zero-dependency Node script (`scripts/check-health.mjs`, Node >= 18) runs
the project's **own** tools (typecheck / lint / test / dead-code / shell
lint), parses their output, scores each category 0–10, computes the
weighted composite, and emits one JSON document; your job is only to turn
that JSON into a readable dashboard. This split exists because models
fabricate plausible-looking numbers when asked to parse tool output and do
scoring arithmetic — here that is structurally impossible: if a number is
not in the JSON, it does not go in the dashboard.

## The iron rule

**Every number in the dashboard comes from the script's JSON output** —
counts, per-category scores, the composite, trend deltas, durations, all of
it. Never recompute, estimate, or "round for readability" beyond what the
JSON already gives you. If a value is `null`, say it is unavailable — do
not derive a substitute. Do not run the underlying tools yourself alongside
the script; the script is the single source of numbers.

## Hard gates

- **Never fix issues.** This skill reports health; it changes nothing. If
  the user wants findings fixed, that is a separate ask (for Sonar
  findings, `sonar-issue-fix`).
- **Wrap, don't replace.** The script runs the project's own commands with
  the project's own configs. Never substitute a different linter, test
  runner, or flags because you prefer them.
- **Respect `.claude/health.json` exactly.** Once config exists, the user's
  commands, weights, and timeouts are law — do not second-guess them.
- **Skipped ≠ failed.** A category whose tool is not installed is reported
  as skipped and its weight redistributes; it never drags the score down.
- **Honest scores.** A 3.2/10 is reported as 3.2/10, with the failing
  output shown. No softening, no "but overall it looks fine".
- **Write almost nothing.** The script appends history only with `--save`;
  you Write only `.claude/health.json` (first-run flow below) and, on an
  explicit ask, a dated report. **Never commit or push.**

## How to run

```bash
node ${CLAUDE_SKILL_DIR}/scripts/check-health.mjs
```

| User intent | Command |
|-------------|---------|
| Health check (config exists) | *(no flags)* |
| First run — see what would be checked | `--detect-only` (prints proposed config, runs nothing) |
| Only some gates ("skip the tests") | `--only typecheck,lint` |
| Keep a record / track the trend | `--save` (appends to `docs/health/history.jsonl`) |
| History somewhere specific | `--save <dir>` |

Run with `-h` for every option. Per-category timeout is `timeoutSeconds`
in the config (default 300 s). Trends need no flag: when
`docs/health/history.jsonl` exists the script always reads it and emits
the `history` block.

## First run — detect, confirm, persist

If `<repo>/.claude/health.json` does not exist, **do not run any tools
yet**:

1. Run the script with `--detect-only`. stdout is the proposed config
   JSON; stderr has one note per category explaining what was (or was not)
   detected.
2. Show the user the proposed categories — command, weight, and the
   detection reason for each.
3. Ask with AskUserQuestion: **(A)** looks right — save and run,
   **(B)** adjust commands/weights first, then save and run, **(C)** run
   once without saving config.
4. On A: Write the `--detect-only` stdout **verbatim** as
   `.claude/health.json` — byte-for-byte, no reformatting, no reordering —
   so what the user confirmed is exactly what future runs execute. On B:
   apply the user's adjustments to that JSON, show the final version, then
   Write it. On C: Write nothing.
5. Run the script normally.

Once config exists, runs go straight through — no confirmation ceremony.

## Reading the JSON

- `categories[]` — one entry per gate: `command`, `weight`, `weightPct`
  (normalized over the gates that ran), `status` (`ran`/`skipped` +
  `skippedReason`), `exitCode`, `timedOut`, `durationS`, `parsed`/`parser`,
  `findings` (the canonical count the rubric scored), `counts` (per-tool
  detail), `score` 0–10, `label`, `outputTail` (last lines of real output).
- `composite`/`compositeLabel` — weighted average over run categories,
  `null` when nothing ran. Labels: 10 CLEAN · 7–9 WARNING · 4–6 NEEDS
  WORK · 0–3 CRITICAL.
- `recommendations[]` — script-ranked by `impact` (weight × shortfall)
  with HIGH/MED/LOW priority. The ranking is the script's; the *prose* is
  yours.
- `history` — previous run, `delta`, `direction`, per-category
  `regressions`, `last10`. `saved` — what `--save` appended, if anything.
- `guards` — honesty booleans (next section).

## Honesty guards — report them, verbatim

Carry any true guard into the dashboard as a plain-words caveat:

- `noToolsDetected` — nothing ran; composite is `null`. Report the empty
  dashboard exactly as that and say what detection looked for — **never
  invent a score for a repo with no gates.**
- `notGitRepo` — fine, but branch context is unavailable; say so.
- `dirtyWorkingTree` — scores reflect uncommitted changes; one-line note.
- `anyTimeout` — a gate hit its `timeoutSeconds` and scored 0; name it and
  suggest raising the timeout in `.claude/health.json` if it is expected.
- `anyParseFallback` — a tool's output was not recognized, so its score
  came from the exit code alone (0 → 10, non-zero → 4); flag that category
  as coarse-grained.
- `firstRun` — no history yet; trends start after the first `--save`.

## Dashboard structure

1. **Header** — repo, branch, date (all from the JSON).
2. **Category table** — one row per category: gate, command, score,
   label, findings, duration. Skipped rows say *skipped (reason)* — never
   a score.
3. **Composite** — `X.X/10 LABEL`, one sentence of interpretation.
4. **Details** — for every category scoring below 7, a short block
   quoting the most relevant `outputTail` lines (real tool output, not a
   paraphrase) and the parsed counts.
5. **Recommendations** — the script's ranked entries, one actionable
   sentence each, priority-tagged. Anchor each to the actual findings; do
   not pad with generic advice.
6. **Trend** *(when `history` is present)* — delta vs previous run,
   direction, a compact `last10` line, and any `regressions` called out
   by name.
7. **Caveats** — every true guard, one line each.

Keep it tight: tables and code blocks for data, a sentence or two of prose
per section for meaning. No motivational filler.

## Saving (`--save` flow)

1. Run the script with `--save` — it appends the history line itself.
2. Only on an explicit "save a report" ask, Write your finished dashboard
   to `docs/health/<YYYY-MM-DD>-health.md`.
3. Tell the user what was written where. Do not commit anything.

## When NOT to use this skill

- Fixing what the dashboard found — that changes code; do it as its own
  task (`sonar-issue-fix` for Sonar findings).
- Running a single gate — "run the tests" is just the test command, no
  dashboard needed.
- CI pipeline setup or hosted analysis — this skill is local-only;
  SonarCloud/SonarQube results are `sonar-issue-check`'s job.
- Anything that would modify the repo to improve the score.

---

Adapted from the `/health` skill in
[`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT, © 2026 Garry
Tan). Rebuilt for this catalog: a deterministic script replaces
model-parsed tool output and model-computed scoring; the gstack-only
gbrain dimension and `~/.gstack` global state are dropped (weights
renormalized to 100); config moves to a user-confirmed
`.claude/health.json` instead of machine-appended CLAUDE.md sections; and
history is opt-in (`--save`) and lives in-repo under `docs/health/`.

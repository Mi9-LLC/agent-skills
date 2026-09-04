---
name: execute-change
description: >-
  Autonomous execution of a plan brief in an OpenSpec-managed repo: one
  lead session drives the feature routine in fresh subagents, committing
  per checkpoint and stopping after the local commits. Takes a plan-brief
  path or a free-text idea, on the full route or the light one, chosen at
  preflight. Pauses only for a human decision; never deploys, pushes,
  opens a PR, or archives the change.
argument-hint: "<plan-brief path | free-text idea>"
disable-model-invocation: true
---

# execute-change

Execute a plan brief end to end in an OpenSpec-managed repository. You (the
session that loaded this skill) are the **lead**: you coordinate, you never
implement. Every pipeline step runs in a fresh subagent with an empty
context; you check its work against evidence on disk, commit checkpoints,
pause for the user only on genuine human decisions (the question reaches
their phone via Remote Control push), and stop after a local commit.

Where the run works is **the user's choice at preflight** (Step 0 check 6):
the current checkout, or a dedicated git worktree. Whichever they pick is the
run's **run root**, the directory every subagent, every lead command, every
commit, and every acceptance check treats as the repository root from Step 0
to close-out. Check 6 states the trade-offs in the question it asks.

The argument (`$ARGUMENTS`) is either a plan-brief path or a free-text
idea: if it resolves to an existing file, it is the brief — go straight to
Step 0; anything else is an idea — run the design-first entry below first.
One guard: an argument that looks like a file path (contains a slash or
ends in `.md`) but matches no file is probably a typo'd brief path — ask
before treating it as an idea. No argument → list the
`docs/up next/*-plan.md` candidates and ask the user to pick one or state
an idea.

## Ground rules

These are non-negotiable for every run:

1. **The lead never does the work itself — every task runs in a
   subagent.** The lead's context must hold coordination state (the
   ledger, verdicts, decisions), not code, research, or logs; that is what
   keeps the run alive for hours. Start a subagent for anything
   substantial — authoring, research, implementation, fixing, bulk file
   reading — and consume only its report. The only files you write
   directly are the ledger, the plan brief (design-first entry only), and,
   at close-out, the `tasks.md` checkbox reconciliation. The lead never
   edits source files.
2. **A subagent's "done" claim is not evidence.** After every step, run
   the acceptance check defined for that step before advancing. A failed
   check gets exactly one retry, a fresh subagent with the failure fed
   back, then you pause and ask the user. A subagent whose skill refuses
   to run pauses the run immediately: never guess forward.

   **A death gets one automatic relaunch.** A subagent has died when the
   Agent tool returns an error or a synthetic last message such as "529
   Overloaded" or "Internal server error" and no report file exists at its
   `{{REPORT_PATH}}`. A report file that exists, whatever its contents,
   means it finished, and its work is judged by the acceptance check, a
   missing `OPEN QUESTIONS` section included. Relaunch a dead one once,
   with the death-relaunch wrapper in
   [`references/step-prompts.md`](references/step-prompts.md) when its
   progress file exists and is non-empty (the files it lists are on disk
   and are not redone), the plain template otherwise; a second death pauses
   the run. That relaunch is one per subagent per step (per subagent inside
   a parallel set), shared with the stall ladder's single relaunch, and it
   does not consume the acceptance-check retry. A skill refusal is not a
   death.
3. **Human decisions pause the run.** (The design-entry interview is the
   one exception: it asks one category at a time, before any ledger
   exists.) Open questions and design forks from any subagent report are
   batched into ONE pause per step: a single AskUserQuestion, or
   consecutive calls in the same pause when there are more than 4 forks
   (the tool's per-call limit), never dropped and never merged beyond
   recognition. Update the ledger first, then wait: the question waits
   indefinitely, survives machine sleep, and pushes to the user's phone.
   Never resolve a fork by assumption.
4. **Never:** deploy, push, open a PR, archive the OpenSpec change, commit
   the ledger or the plan brief, or use `git add -A` / `git add .` — every
   commit stages explicit paths (`git add <path>...`).
5. **Internal knowledge is outdated.** Every subagent prompt embeds the
   standing implementer instructions: return open questions instead of
   guessing, and verify external library/API behavior against current
   documentation, not memory.
6. **The ledger is the source of truth.** Re-read it at every step
   boundary. After any auto-compaction, also re-read this SKILL.md from
   disk before continuing, and re-read the reference for the phase you are
   in (design entry:
   [`references/design-entry.md`](references/design-entry.md); Step 0:
   [`references/preflight.md`](references/preflight.md); steps 1 to 8: the
   step's template in
   [`references/step-prompts.md`](references/step-prompts.md)). Resume
   runs continue from the ledger, never from memory.

There is no `allowed-tools`/`disallowed-tools` line in the frontmatter: the
lead needs the Agent tool, Bash, AskUserQuestion, and file tools, so the
never-rules above are workflow discipline, not a tool-pool restriction.

## Design-first entry — from idea to approved brief

Only when the argument is an idea, not a file. The whole phase (the
research subagent, the categorized interview run in rounds, the brief
draft, and the approval gate) is in
[`references/design-entry.md`](references/design-entry.md) **(read it now,
before anything else, when the argument is an idea)**. It runs before Step
0: no branch, run root, or ledger exists yet, and only an approved brief
enters Step 0.

## Step 0 — Preflight (the user is still at the keyboard)

Full command detail, the companion-skill check, and the one-time machine
setup (Remote Control, push notifications, permission allowlist, optional
hooks) live in [`references/preflight.md`](references/preflight.md)
**(read it when you reach this step)**. The third reference file,
[`references/domain-docs.md`](references/domain-docs.md), holds the
`CONTEXT.md` and ADR formats; only the step-1 author subagent reads it.

**The skill directory.** Claude Code prints it when this skill loads
("Base directory for this skill: ..."). Record that path in the ledger as
`Skill dir:` (check 8); every script and hook path in this file is built
from it. When that line is not in context, read `installPath` for
`execute-change@mi9-agent-skills` from
`~/.claude/plugins/installed_plugins.json`. Under an `npx skills add`
install it is `~/.claude/skills/execute-change`, which ships no `hooks/`
folder, so the process sweep is skipped, as today.

Run the checks in this order:

1. **Plan brief.** Resolve the argument to a file; it must exist and be
   readable. Read it fully. (No candidates under `docs/up next/`? Ask the
   user for the path — repos may keep briefs elsewhere.)
2. **Resume check — before anything is created.** If the brief's ledger
   (check 8 defines its exact name) already exists, this is a resume:
   continue the pipeline from the fields the ledger records, and never
   create a second branch, run root, or ledger for the same plan, or
   re-ask the route. Which fields those are, and the whole procedure down
   to which checks are re-run and which are skipped, is the `## Resume
   (check 2)` section of
   [`references/preflight.md`](references/preflight.md); read it before
   carrying any of it out.
3. **OpenSpec-managed repo.** `openspec/config.yaml` at the repo root
   confirms it; if absent, `openspec context` decides, and a missing CLI
   cannot answer that question — run check 4's install path first, then
   return here. **Not managed → ask. Never end the run on a printed
   message alone**: this is a blocking AskUserQuestion the run waits on.
   Both option texts, every command, the init flags and their traps, and
   the version-check-before-`init` ordering are the `## OpenSpec: detect,
   install, update` section of `references/preflight.md`. Record the answer
   in the ledger's Decisions block when check 8 creates it.
4. **OpenSpec CLI installed and current.** Ask (AskUserQuestion) before
   installing or updating anything. The commands, the version-comparison
   rule, and the session-restart warning a regenerated `opsx` flow triggers
   are in that same `## OpenSpec: detect, install, update` section of
   `references/preflight.md`.
5. **Companion skills.** The run depends on `plan-eng-review` (step 2 and
   the step-5 re-run) and `verify-implementation` (step 7) being installed,
   and on the repo's own OpenSpec propose and update flows existing. Either
   missing → AskUserQuestion offering the install; the commands, the
   session-restart warning, and what regenerates a missing flow are the
   `## Companion skills` section of `references/preflight.md`.
6. **Run root and branch — a blocking question.** Identify the default
   branch, `git fetch` first so a branch created here starts from a current
   base (a fetch failure is not fatal: note it and continue from the local
   base). The run name is `<timestamp>-<plan name>`: `<timestamp>` is the
   current date-time at run start (e.g. `20260813-1054`), never a date from
   the brief's filename, which may be days old; `<plan name>` is that
   filename without its extension and without any date-time stamp it
   carries, sanitized for git (spaces → hyphens).

   Which directory is the run root is the user's decision, taken in a
   blocking AskUserQuestion asked before anything is created: reuse the
   current branch and this checkout (recommend this one), create the run's
   branch in this checkout, or create a dedicated worktree and branch. The
   `## Run root notes` section of `references/preflight.md` holds the option
   texts, everything the question must state before it is answered, the
   commands, the second confirmation when HEAD is the default branch, and
   the rule that no worktree command runs under either reuse option. Record
   the answer in the ledger's Decisions block, and the chosen option in the
   ledger's Run root field (check 8): a resume has to know whether a
   worktree exists.

   Once the chosen option has been carried out and the run root exists,
   record the run's **start commit**: `git rev-parse HEAD` in the run root,
   the full sha. It is the diff base for steps 7 and 8, a scope the base
   branch cannot give: under a reused branch the base branch IS the branch
   the run commits on, so a base-branch diff is empty.

   Then write the run's metadata file, `.claude/execute-change-run.json`,
   in **the directory this session was started in** — the main repo
   checkout — and not in the run root; `references/preflight.md` has its
   contents and the reason for that location. Its `session_id` comes from
   the `CLAUDE_CODE_SESSION_ID` environment variable, which the Bash tool
   inherits: read it, never guess it, and **if it is empty or absent, say
   so to the user and continue WITHOUT writing the file** — a wrong id
   leaves the hooks inert while the check-7 readiness line claims the
   heartbeat is armed.

   Finally, launch the run-root preparation as a BACKGROUND task, off the
   critical path (steps 1–5 don't need it): the project's dependency install
   (e.g. `npm ci`) followed by one run of the project's quality gates on the
   untouched run root — the **baseline**. Record per-gate pass/fail, with
   any failing output, in the ledger's Baseline field when it finishes.
   Whether the install runs at all depends on the run-root option: the
   `### Per-option consequences` section of `references/preflight.md`.

   6a. **Route — asked as the second question of check 6's call**, so Step
   0 still has one pause. The run takes one of two routes: **full** (steps
   1 to 8 as written below) or **light** (step 1 in a lighter form, then
   steps 6 and 7; the `## Light route` section defines it). You propose the
   route from a checklist, with no subagent, because check 1 already made
   you read the brief fully: the six signals, the recommendation rule, and
   how the question is asked are the `## Route (check 6a)` section of
   `references/preflight.md`.

   The user's answer is the route, whatever the recommendation was. Record
   it in the ledger's `Route` field (check 8) and in the Decisions block.
   There is no switch between routes once the run has started: a user who
   wants the review after choosing light stops the run, deletes the ledger,
   and re-runs with full.
7. **Readiness line — printed, never asked.** There is no approval question
   here: the manual invocation IS the authorization, and `tasks.md`, the
   only input to the step 6 concurrency decision, does not exist yet. Print
   one line stating the run's shape before the user walks away: plan brief,
   branch, base branch, the run root with the option that produced it
   (reused checkout, new branch here, or worktree), the route (check 6a),
   and the notification state — read `agentPushNotifEnabled` and
   `hasUsedRemoteControl` from `~/.claude.json` (the opening paragraph of
   the section of `references/preflight.md` whose heading starts
   `## One-time machine setup` explains both keys); either one false or
   absent → say plainly that pauses will wait in this terminal only.
8. **Ledger.** Create `<plan path>.ledger.md` next to the plan brief —
   literally append `.ledger.md` to the brief's full filename (e.g.
   `foo-plan.md` → `foo-plan.md.ledger.md`); this exact name is the resume
   key:

   ```markdown
   # execute-change ledger — <plan brief filename>
   - Branch: <the branch check 6 settled on>
   - Run root: <absolute path> (reused-checkout | new-branch-here | worktree)
   - Skill dir: <the base directory Claude Code printed when this skill loaded>
   - Route: full | light   <!-- check 6a; a ledger without this line means full -->
   - Base branch: <the default branch identified in check 6>
   - Start commit: <full sha>   <!-- the diff base for steps 7 and 8 -->
   - Change ID: (set after step 1)
   - Last completed step: 0
   - Parallel groups: allowed when tasks.md file lists are disjoint
   - Fix cycles used: 0 of 2
   - Baseline gates: (set when the background run-root prep finishes)
   ## Step log        <!-- per step: subagent outcome + acceptance-check result -->
   ## Decisions       <!-- every user answer, verbatim -->
   ## Open questions
   ## Completed implementation groups   <!-- one paragraph per group -->
   ```

   The Start commit field is written once, by check 6; a resume re-reads it
   and never recomputes it, because `HEAD` has moved and a recomputed base
   would shrink the audit's diff.

   Next to the ledger, create the reports folder `<plan path>.reports/`
   (e.g. `foo-plan.md.reports/`). Every pipeline subagent writes its full
   report to a file there, named by the lead in its prompt as
   `{{REPORT_PATH}}` (`step1.md`, `step4.md`, `step5-reader.md`,
   `step5-review.md`, `step6-group3.md`, `step7-fix1.md`, and so on; the
   placeholder table in `references/step-prompts.md` is the full list),
   with `OPEN QUESTIONS` as its first section, and returns only that path
   and a short summary. The ledger, the reports folder, and the plan brief
   are never committed; the user deletes all three at manual close-out.

## The pipeline — how every step runs

Steps 1–8 run through **fresh subagents**, normally one per step, with the
exceptions their sections define: step 3 is lead-run, step 5 is lead-run
except for its conditional `tasks.md` reader and the re-review it launches
under `NEEDS REVISION`, step 6 launches one per task group, and steps 7 and
8 may launch a bounded follow-up fix subagent. On the light route (check
6a) only steps 1, 6, and 7 run; the `## Light route` section defines the
differences, and everything here applies to both routes unless it says
otherwise.

Every prompt is taken verbatim from
[`references/step-prompts.md`](references/step-prompts.md) **(re-read the
step's template from that file immediately before each fill — never fill
one from memory; compaction corrupts verbatim-ness silently)**, with the
placeholders filled from the ledger: the change ID, the change folder
`openspec/changes/<id>/` inside the run root, the branch,
`{{START_COMMIT}}`, the run root path, and `{{REPORT_PATH}}` (one file per
step or task group under the reports folder check 8 created). The base
branch is a ledger field, not a placeholder: no template takes it any
more. Every acceptance-check command you run below — `openspec validate`,
the diffs, the commits, the gates — runs inside the run root.

**Read the report file, never the returned text.** A subagent returns only
its report path and a short summary; the returned text can arrive
truncated mid-sentence, inside `OPEN QUESTIONS` included. Every verdict,
finding, and open question you act on comes from the file.

**Lead shell discipline.** Never leave the shell in another directory: run
a command in a subdirectory as `(cd <dir> && <command>)`, or use `git -C
<dir>`, `pnpm -C <dir>` / `pnpm --filter`, `dotnet <verb> <path>`. And
never pass the run's worktree as an additional working directory
(`--add-dir`). Both break the hooks, which start from the payload's `cwd`,
the Bash tool's current directory, and walk up to the nearest directory
holding the metadata file. The symptom is a `start` (or every event)
missing from `.claude/execute-change-run.jsonl` while `ListAgents` shows
the subagent running.

**Acceptance checks** run by you, the lead, after each step completes; the
step's checkpoint commit, where one is defined, happens only AFTER its
check passes, never before. When a check passes, update the ledger before
advancing: set "Last completed step" to that step and record the outcome in
the Step log. That field is the resume key; left unwritten, a crash resumes
at step 1.

**The lead writes less.** A Step log entry is at most 5 lines: the
subagent's outcome, the acceptance-check result, the report file's path,
and at most two lines of what matters for the next step. Detail lives in
the report files, which the ledger names; do not copy it into the ledger.
Decisions are the one exception and stay verbatim. Between step boundaries
you write nothing except the ledger update and the next prompt fill.
Measured on 2026-09-03: the lead alone wrote 235,000 tokens in one run.

**No unplanned fix subagents on planning documents.** A contradiction
between `proposal.md`, `design.md`, the spec deltas, and `tasks.md` goes to
the step 4 retry (the one permitted retry, with the contradiction as its
feedback) or to the user, never to an extra subagent the pipeline does not
define. On 2026-09-03 two such subagents were launched in step 5 to
reconcile what two step 4 subagents had left; the run now has one step 4
subagent, so that contradiction is a failed step 4.

| After step | Evidence required on disk |
|---|---|
| 1, 4 | Expected artifacts exist in `openspec/changes/<id>/` AND `openspec validate <id> --strict` passes. Light route, step 1: `proposal.md` and `tasks.md` exist, and either at least one spec delta exists or the change's `.openspec.yaml` has `skip_specs: true`; validate passes; and the three mechanical `tasks.md` checks in `## Light route` pass |
| 2 | `design.md` contains a review report with a verdict |
| 3 | Every answered decision is recorded in the ledger |
| 4, quotes | Every line step 4 quoted is found by the lead's `grep -F -x` in the file it names (the step 5 check) |
| 5 | Under `NEEDS REVISION`: `design.md` holds a re-review report with a verdict. When the conditional reader ran: its report says PRESENT for every item it was given |
| 6 (each group) | The group's files actually changed in the run root, matching its report (uncommitted at check time — the commit follows the check) |
| 7 | An audit report with a verdict exists |
| 8 | The simplify report exists and the project's gates passed |

**Commit model** — so a crash is resumable from the last checkpoint and the
step-7 audit gets a real diff from the run's start commit. You commit by
explicit pathspec:

- after the change artifacts pass their last planning check — step 5 on
  the full route (or step 2 when the verdict was `APPROVED` with nothing
  to apply, since steps 4 and 5 are then skipped), step 1 on the light
  route: the OpenSpec change artifacts (`openspec/changes/<id>/`) plus any
  `CONTEXT.md` / `docs/adr/` files step 1 created or updated (the step-1
  report lists them);
- after each step-6 group: that group's changed files;
- after each step-7 fix cycle: the fix subagent's changed files, committed
  BEFORE the re-audit — the audit diffs committed state only, so an
  uncommitted fix is invisible to it;
- after step 8: the simplification changes;
- at close-out: the `tasks.md` reconciliation.

`verify-implementation` makes its own dedicated fix commits during step 7;
that is how the skill already works, and the feature branch is not shared.

**Models.** Steps 1, 2, 4, 7, and 8 run on Opus, and so do step 5's
conditional `tasks.md` reader and its re-review, step 6's set-failure fix
subagent, step 7's fix subagent, and the design-entry research subagent.
Pass the model explicitly on step 7 too; do not rely on
`verify-implementation`'s own pin propagating into a subagent. Step 6
groups run on the model their `tasks.md` row names, passed as the Agent
tool's `model` option — a missing or unmappable model name means Opus,
never a more expensive tier (catalog constraint: never pin Fable).

## Light route

Chosen at check 6a. Full-route step numbers are kept, so `Last completed
step` and a resume keep their meaning: a light run's ledger goes 0, 1, 6,
7. Everything not named in this table runs exactly as on the full route.

| Step | Light route |
|---|---|
| 0 | As on the full route, plus check 6a. The baseline prep runs as before; the first step 6 group waits for it, as before. |
| 1 | **Light author** — Opus subagent on the `Step 1 (light)` template in `references/step-prompts.md`, which defines every artifact it writes. It does NOT invoke the `/opsx:propose` flow, which writes every artifact of the schema, `design.md` included, and would re-plan a brief that is already the plan. No `design.md`. |
| 1, acceptance | The files exist (`proposal.md`, `tasks.md`, and either at least one delta or `skip_specs: true`); `openspec validate <id> --strict` passes; and you, the lead, run three mechanical checks on `tasks.md`: every group has a model, a blocked-by line, and at least one verify clause; the file lists of groups sharing a parallel group are disjoint; every listed file exists in the run root or is marked new. As on the full route, record the change ID in the ledger when the author returns, before these checks. A failed check is a failed step 1 (one retry with the failure fed back, then pause). Then the first checkpoint commit: the change artifacts plus step 1's `CONTEXT.md` / `docs/adr/` files. |
| 2 to 5 | Skipped. The Step log records one line: `Steps 2-5: skipped (light route)`. `Last completed step` goes from 1 straight to 6. |
| 6 | As on the full route. The step 6 template's read list names `design.md` and the spec deltas "if present", on both routes. |
| 7 | As on the full route: `verify-implementation` against `git diff <start commit>..HEAD`, at most 2 fix cycles. |
| 8 | Skipped. The Step log records `Step 8: skipped (light route)`. |
| Close-out | As on the full route. |

Pauses on the light route work as on the full route. There is no switch to
the full route mid-run (check 6a states what a user who wants the review
does instead): the full route's step 2 needs a `design.md` the light author
never writes.

## Heartbeat and stall handling

A subagent that hangs costs the run hours of silence, because the lead
deliberately does not watch subagents work. So immediately after launching
any subagent, arm one background watcher with
`Bash(run_in_background: true)`:

```bash
bash "<Skill dir>/scripts/stall-watcher.sh" "<absolute path of the session's project root>/.claude/execute-change-run.jsonl"
```

That file is the heartbeat log the three `execute-change` hooks append to,
described in [`references/preflight.md`](references/preflight.md). It sits
in the session's project root, the directory check 6 wrote the metadata
file in, since each hook writes the log next to the metadata file it just
read. Give the watcher that absolute path, never a bare relative one: the
shell's working directory moves between commands, so a relative path would
silently resolve somewhere else.

The script re-reads the log every 180 seconds, stays quiet until you need
to act, then exits, which notifies you. It also prints one line every 30
minutes — `alive: N agents running, oldest <age>` — so silence never means
"unknown". Its verdict is the last line it prints, and it always exits 0:

- `NOLOG` — no heartbeat log, so the `execute-change` hooks are not
  installed.
- `TROUBLE <notification type>: <text>` — a `notify` event of type
  `permission_prompt`, `agent_needs_input`, or `idle_prompt` arrived.
- `IDLE` — the log shows every subagent stopped.
- `STALL` — agents are still running and no `stop` or `notify` event has
  arrived for 3 consecutive checks (a 9-minute silence, detected at most 3
  minutes late).
- `WATCHER ERROR` — unexpected output from its own replay.

**`ListAgents` is authoritative: confirm every `IDLE` and every `STALL`
verdict with it before acting on it.** An agent listed as running means
the log is wrong, not that the agent finished: re-arm the watcher and
carry on. Write the `ListAgents` check and its outcome to the ledger, the
same as every other step.

**`IDLE` is the normal end of a watcher's life**, not a finding: you
already have the subagent's return value and are back in control, so arm a
fresh watcher at the next launch. An `IDLE` that arrives before the
subagent's return value is the suspect case: the watcher replays `start`
and `stop` lines to build its running set, so a missing `start` leaves that
set empty and the first check prints `IDLE` while the subagent works on.

**A `STALL` verdict means the log has been quiet for 9 minutes, not that
the subagent is stuck.** `SubagentStart` fires once and nothing else is
emitted until `SubagentStop`, so a step-6 implementer working normally for
20 minutes looks exactly like a stalled one from the log alone. Read the
agent's row in `ListAgents`:

- still running or busy → it is working, not stalled: re-arm the watcher
  and carry on, and send the subagent nothing. **This is the expected
  common outcome**, not a failure, and repeated ones are not repeated
  failures.
- idle while its `stop` event has not arrived → a real stall, and only
  then does the ladder start: send it a status request with `SendMessage`;
  still idle at the next check → `TaskStop` it and relaunch it once: the
  death-relaunch wrapper when its progress file is non-empty (ground rule
  2), otherwise the retry wrapper with `{{RETRY_FEEDBACK}}` filled from the
  stall itself ("the previous attempt stalled: no report file and no
  progress file after N minutes; any half-finished edits it left are in the
  working tree, see `git status --porcelain`"); still stuck after that →
  pause and ask the user. This is the single relaunch ground rule 2 allows,
  whichever of the two spends it.

**A `permission_prompt` notification is not a stall.** Only a human can
answer it, so there is nothing to retry: report it to the user at once and
wait.

A `stop` event carries no success or failure signal, so the watcher uses
it only to take that agent out of the running set. A failed step is caught
by your own acceptance check after the subagent returns; the watcher only
tells you when to go and look. When a check does fail, the `stop` event's
`agent_transcript_path` points straight at that subagent's transcript.

A subagent can finish its work and report while `ListAgents` still shows
it running. Before a lead gate run starts, `TaskStop` such an agent
deliberately, so its `stop` event and any sweep land before the gates, not
during them.

A watcher can also vanish without printing anything: the `SubagentStop`
sweep runs at batch end and may kill its shell before the next check. A
watcher that disappears at the end of a step is normal.

**Fallback timer when the log cannot be trusted.** When `IDLE` has proved
false once in a run, or the hooks are not installed (`NOLOG`), arm a plain
timer instead of the log watcher, with `Bash(run_in_background: true)`:

```bash
bash "<Skill dir>/scripts/stall-watcher.sh" --fallback "<run root>"
```

Its exit re-invokes you: call `ListAgents` and re-arm. The newest-file
line separates "working" (files still changing) from "stuck" (nothing
changed for two ticks) without waking the agent. It costs one line of
context every 3 minutes, which is why it is the fallback.

**When the hooks are not installed**, no JSONL file ever appears and the
watcher exits on its first check with `NOLOG`. Say so once, in the Step 0
readiness line or in the step log, and fall back to ground rules 2 and 3,
which hold the pause rules; never loop on a file that will not arrive.

## Step 1 — Author the OpenSpec change

Subagent (Opus) on the step 1 template in
[`references/step-prompts.md`](references/step-prompts.md), which invokes
the repo's own OpenSpec propose skill — the `/opsx:propose` flow; its
generated skill name varies by CLI version (e.g. `openspec-propose` or
`openspec-propose-change`). Afterwards these must exist: `proposal.md`,
`design.md`, the spec deltas, and `tasks.md` carrying, per task group, a
model, a parallel-group marking, a file list (parallel safety depends on
it), and verify clauses. Any `CONTEXT.md` and `docs/adr/` files the author
created are listed in its report and go into the first checkpoint commit
with the change artifacts.

**Content rules, not line caps.** Both step 1 templates in
`references/step-prompts.md` carry them, and the author is bound by them:
file lists and verify clauses in particular are never shortened, because
the step 6 concurrency gate and step 7 read them. When the author returns,
print `wc -l` of `design.md` (full route) and `tasks.md` in the Step log —
information only, no threshold — record the change ID in the ledger, then
run the acceptance check.

## Step 2 — Engineering review of the change

Subagent (Opus) runs `plan-eng-review` against the change artifacts. The
prompt states verbatim: you run non-interactively — do not call
AskUserQuestion; record every fork under `UNRESOLVED DECISIONS`; the file
that receives the spliced report is `design.md`.

## Step 3 — Resolve the review's open decisions (lead → user)

If the review left anything under `UNRESOLVED DECISIONS`, batch all of it
into one pause as ground rule 3 defines (this is the first place the phone
push earns its setup — the run may have been unattended for a while).
Record every answer in the ledger's Decisions section. No unresolved
decisions → skip to step 4, but still set `Last completed step` to 3 and
log `Step 3: no unresolved decisions`, so a resume never wonders whether
step 3 ran.

Step 4 waits for the answers. Nothing is launched while the question is
out: the required changes and the decisions are applied by one subagent in
one pass, after the user has answered. Two subagents editing `design.md`
and `tasks.md` in sequence left contradictions on 2026-09-03 that took two
more subagents to repair.

## Step 4 — Apply the review's required changes

A verdict of `APPROVED` with zero required changes and zero decisions →
skip steps 4–5 entirely and make the first checkpoint commit now, with the
contents the commit model above defines. Otherwise:
subagent (Opus) applies the review's Required plan changes via the repo's
OpenSpec update skill (the `/opsx:update` flow; generated name varies by
CLI version, e.g. `openspec-update-change`) AND folds the user's answered
decisions into the report's Decisions block — always one subagent, one
pass, launched after the step 3 answers are in (or at once, when step 3 had
nothing to ask). Its report ends with a `QUOTES` section: per required
change and per decision, the file it edited and ONE whole line quoted
exactly as it stands after all edits, the unslop pass included; and a
`TASKS.MD RE-READ` section listing any line of `tasks.md` that contradicts
a change it made (or `none`). Those quotes are what step 5 checks.

## Step 5 — Check that the changes are in the artifacts

**Lead-run, mechanical.** The step 4 template in
`references/step-prompts.md` fixes the layout of its `QUOTES` section. Cut
each block out of the report file with `awk`, never by retyping, then check
each quote against the artifact as a whole line, carriage returns stripped
from both sides (the artifacts may be CRLF):

```bash
# once per file step 4 quoted: extract that file's block from the report
awk -v f="<file>" '/^```/{inb=!inb; if(!inb){want=0}; next} inb && $0=="FILE: "f {want=1; next} inb && want' "<report path>" > "$QUOTES"
tr -d '\r' < "$QUOTES" > /tmp/q.txt
tr -d '\r' < "<run root>/openspec/changes/<id>/<file>" > /tmp/t.txt
while IFS= read -r line; do
  grep -F -x -q -- "$line" /tmp/t.txt || echo "MISSING: $line"
done < /tmp/q.txt
```

A quote reported `MISSING`, or a non-empty `TASKS.MD RE-READ` section,
means step 4 failed, not step 5: re-run step 4 with only the missing or
contradicted items as its inputs (the one permitted retry, with the
`MISSING` lines as its feedback), then this check again; still missing →
pause and ask. The check runs under `APPROVED WITH CHANGES` and under
`NEEDS REVISION` alike: `plan-eng-review`'s re-run re-verifies the prior
Required plan changes itself, but it only carries decisions forward, so
without this check the decisions would go unverified.

**One conditional reader.** When a required change or a decision edits a
`tasks.md` file list, a group boundary, or a blocked-by order, a fresh Opus
subagent (the `Step 5 — conditional tasks.md reader` template) checks only
those items and reports PRESENT or MISSING per item. A file count is the
class of change a whole-line grep cannot judge (the one real step 5 catch
on 2026-09-03 was a file list of 12 where 14 were touched). A `MISSING`
from the reader is handled exactly like a `MISSING` quote. No item of that
class → no reader.

**Re-review under `NEEDS REVISION`.** When the step 2 verdict was `NEEDS
REVISION`, the re-run of `plan-eng-review` is mandatory and launches right
after the grep check (and the reader, when one ran) passes — decisions
carried forward, using the re-review prefix in
`references/step-prompts.md`. Re-review outcomes: `APPROVED` → proceed;
`APPROVED WITH CHANGES` with new required changes, or new `UNRESOLVED
DECISIONS` → loop back through steps 3–5 exactly once; still `NEEDS
REVISION`, or anything unresolved after that one loop → pause and ask the
user. Under `APPROVED WITH CHANGES` there is no re-review: step 5 is the
grep check, plus the conditional reader when an item of its class exists
(the reader's trigger is the class of change, not the verdict). Once step 5
passes, commit the change artifacts and step 1's `CONTEXT.md` /
`docs/adr/` files (first checkpoint commit).

## Step 6 — Implement, task group by task group

One subagent per `tasks.md` task group, sequential in dependency order,
each on the model its row names. The step 6 template in
[`references/step-prompts.md`](references/step-prompts.md) defines what
that prompt carries; the implementer never ticks its own checkboxes and
never self-verifies.

**Before the first group launches:** confirm the Step 0 background baseline
task completed, and surface a red baseline to the user — it means
pre-existing failures that must never be attributed to the implementation.

Groups marked parallel run concurrently ONLY when their file lists in
`tasks.md` are disjoint; no file lists means the condition is unevaluable,
so serialize. Serialized is also the default otherwise: a parallel set
shares one working tree, and when check 6 reused the current checkout that
tree is the user's own. A parallel set runs like this: launch every group in
the set from the same snapshot (identical branch diff and completed-group
summaries), using the parallel variant of the step-6 prompt (verify clauses
only — no project-wide gates, they would race in the shared tree); when the
whole set has returned, run the acceptance checks serially, then the gates
the proportionate rule below picks for the set's combined changed files,
once over the still-uncommitted set, and only after the gates pass make the
per-group pathspec commits (the after-the-check commit rule holds, so
nothing red gets committed). A gate failure attributable to one group is
that group's failed acceptance check (one retry); a failure spanning groups
treats the whole set as the failed unit, one retry of the set, then pause
and ask.

**The retry of a set is one fix subagent, not a relaunch of every group.**
A failure that spans groups is an interaction between them (one group
changed a signature, another still calls the old one), and relaunching each
group would give every subagent half the picture. So: keep the set's
uncommitted edits in place, launch one Opus
subagent on the step 7 fix template in its set-failure variant
(`references/step-prompts.md`), with the failing gate output as its
`{{FINDINGS}}`, the union of the set's `tasks.md` file lists as its file
scope, and `step6-set<N>-fix.md` as its report file (`<N>` is the parallel
group number). When it returns, run the set's acceptance checks and gates
once more. The acceptance check after a set fix is: `git status
--porcelain` matches the union of the group reports' file lists plus the
fix report's file list, and every file in the fix report is in some group's
`tasks.md` file list. Green → the per-group pathspec commits as usual,
every file the fix touched going in the commit of the group whose list it
belongs to. Red, or a file changed outside the set's lists → pause and ask.
This fix subagent is the set's single retry; it does not count toward step
7's 2 fix cycles.

Before committing a serial group, run the gates yourself in the run root:
the implementer's own gate run is its iteration loop, not evidence (ground
rule 2), and the implementer does not run the full suite, so your run is
the only one that counts and is not duplicated. Judge any failure against
the ledger's Baseline: a failure already present at baseline is
pre-existing, so report it and never attribute it to the group. Then, after
the group passes its acceptance check and your gate run: commit the group
by pathspec, add a one-paragraph summary to the ledger, advance.

**Which gates a group gets — proportionate to what it changed.** A full
gate run takes minutes (about 8 in one measured repo); five serial groups
times a full run each is 40 minutes, much of it proving nothing. Decide
from the group's changed files (`git status --porcelain` in the run root):

- **Only documents, comments, or a README changed:** skip the type check
  and the tests — nothing there can break a test. Run only a gate that
  reads those files, if the project has one (a markdown lint, a link
  check).
- **Any code changed: the type check and the lint, always.** The type check
  (`tsc --noEmit`, `dotnet build --nologo`, or what the project's CLAUDE.md
  names) is fast and catches most of what breaks across files: a changed
  signature, a renamed export, a new required field.
- **Tests, when the runner has a related-tests mode:** run it over the
  group's changed source files — `vitest related <files>` or `jest
  --findRelatedTests <files>`. It runs every test file whose import graph
  reaches a changed file, so it covers the group's own tests plus tests in
  other groups' files that depend on the changed code. This is mechanical;
  it does not depend on reading the diff correctly.
- **Tests, when there is no such mode (.NET and others):** run the group's
  own test files, and the full suite when the group changes behavior that
  tests elsewhere assert on. The signals: a call count, the order of
  operations, the text of a SQL statement or a log message, state left
  behind after a run. Worked example: a group added one `probeInstance`
  call. No type error, and every test in its own file list passed. It broke
  an integration test in a different group's file that asserted on the
  exact list of probed names. This rule depends on your reading of the
  change: when unsure, run the full suite. It is cheaper than finding the
  breakage at the pre-audit run with several groups stacked on top.
- **The full gates once after the last group, before step 7**, whatever the
  per-group decisions were. A failure found there is located by bisecting
  the group commits — they are separate commits by pathspec. Steps 7 and 8
  re-run the full gates as well.

**Park the metadata file for every lead gate run.** Under the two
reuse-the-checkout options of check 6, the `SubagentStop` sweep kills any
allowlisted process that descends from this `claude` process or names the
run root and started after the batch began, and a gate run you start in the
run root is both; nested subagents (an implementer's own `Explore` agents)
and missed `start` events make the sweep fire far more often than once per
batch. So, immediately before starting any gate run yourself, move
`<session project root>/.claude/execute-change-run.json` to
`execute-change-run.json.parked`, and move it back as soon as the gate run
has finished — after it ends, not when it is launched. The hooks pass
through when that file is absent, so the sweep cannot fire in that window.
Two costs: no `start`, `stop`, or `notify` line is logged while the file is
parked, so park only when no subagent is running (the serial flow
guarantees that; `TaskStop` a subagent that has already reported but still
shows as running before you park); and a crash between park and restore
leaves the hooks inert, so a resume (check 2) must look for the `.parked`
file and restore it.

**Before believing a gate failure, check that it was a failure.** A killed
gate run looks exactly like a real one: the block ends in `[ELIFECYCLE]
Command failed with exit code 1` and names no failing test. Grep the gate's
own output for a failing-test marker first (`FAIL`, `✗`, `×`,
`AssertionError`, or the runner's equivalent). None, and the block ends in
`ELIFECYCLE` → it was killed, not failed: look for a `sweep` line
containing `killed pid` near that timestamp in
`.claude/execute-change-run.jsonl`, re-run the gate, and do not investigate
a bug that does not exist.

## Step 7 — Audit the implementation

Subagent runs `verify-implementation` over the whole change, against `git
diff <start commit>..HEAD` — everything this run committed, and nothing the
branch already carried before it began. The step 7 template in
[`references/step-prompts.md`](references/step-prompts.md) states that
scope verbatim. A `NEEDS ATTENTION` verdict → feed the findings to a fix
subagent (Opus), check its report, commit its changes by pathspec (the file
list from that report), and only then re-run the audit — it reads committed
state. Maximum 2 fix cycles for the whole run — update the ledger's "Fix
cycles used" counter as each one starts, so a crash cannot reset the bound
— then pause and ask the user.

## Step 8 — Simplification pass

Subagent (Opus) on the step 8 template in
[`references/step-prompts.md`](references/step-prompts.md), which is
self-contained and names what to look for. (Deliberately not the
`/simplify` built-in — its availability inside subagents is unverified.)
The subagent re-runs the project's own quality gates before reporting; its
edits stay uncommitted until they pass. A gate failure → launch step 7's
fix subagent with the failing gate output as the findings, then re-run the
gates, not the full audit; each such cycle counts toward the same 2-cycle
bound, and a bound already exhausted means pause and ask immediately. On
green: commit the simplification changes by pathspec.

## Close-out — reconcile, validate, stop

1. Reconcile the `tasks.md` checkboxes against the audit evidence — the
   lead's one permitted source edit — and commit that reconciliation by
   pathspec.
2. `openspec validate <id> --strict` as a read-only final check.
3. Run the process sweep once over the run root — the final guarantee, not
   the only one, since the `SubagentStop` hook already sweeps at every batch
   end. The script's parameter is named `-Worktree` and keeps that name; the
   value you pass is the run root, whatever check 6 settled on:

   ```bash
   SWEEP="<Skill dir>/../../hooks/sweep-worktree-processes.ps1"
   [ -f "$SWEEP" ] && pwsh -NoProfile -File "$SWEEP" \
     -Worktree "<run root path>" -Since "<the run's started_at>"
   ```

   Under an `npx skills add` install (`Skill dir` is
   `~/.claude/skills/execute-change`) skip the sweep without testing that
   path: `../..` then resolves to `~/.claude/`, whose `hooks/` folder, if
   one exists, holds the user's own hooks, not this plugin's.
   A missing script file means the sweep is not installed (an `npx skills
   add` install ships no `hooks/` folder) → skip the sweep and say so in
   the report. Otherwise list what it killed. Then delete the run's
   `.claude/execute-change-run.json` and
   `.claude/execute-change-run.jsonl` from the session's project root,
   where check 6 wrote them — the run is over, and removing the metadata
   file is what makes the hooks inert again.
4. **STOP.** Report to the user: verdicts per step, decisions taken, the
   commit list, leftover processes killed, the run root, and the remaining
   manual steps verbatim: deploy to the dev environment and smoke-test,
   update the work-folder CLAUDE.md files, delete the plan brief, the
   ledger, and the reports folder, `opsx:archive` the change, and open the
   PR. When the run had its own worktree, one more manual step follows the
   PR: remove it with `git worktree remove <path>`. A reused checkout has
   no worktree, so leave that step out rather than telling the user to
   remove a directory that does not exist.

## Pause-and-notify rules (apply at every step)

Every rule that once sat here lives in one place now. Ground rule 2 holds
the failure rules: a hard failure pauses, a soft failure gets one retry,
and an API or transport death gets one automatic relaunch. Ground rule 3
holds the batch-into-one-pause rule and AskUserQuestion's per-call limit.
`## Heartbeat and stall handling` holds the stall ladder and what each
watcher verdict means. An unexpected permission prompt waits and notifies
like any other pause, which is why this skill does not demand
`bypassPermissions`; `references/preflight.md` documents the recommended
per-repo allowlist and `acceptEdits` mode.

---
name: execute-change
description: >-
  Autonomous end-to-end execution of a plan brief in an OpenSpec-managed repo:
  one lead session drives the whole feature routine — author the OpenSpec
  change, engineering review gate, apply the required changes, implement task
  group by task group, adversarial audit, simplification pass — each
  pipeline step running in fresh subagents, committing per checkpoint on a
  dedicated branch in the run's own git worktree (several plans can run
  concurrently on one repo), and stopping after the local commits. Accepts
  a finished plan brief or a free-text idea — an idea first goes through a
  design interview and a user-approved brief before anything executes.
  Pauses with a phone push only when it needs the user: a decision, or a
  failure it may not resolve alone. Never deploys, never pushes, never
  opens a PR.
argument-hint: "<plan-brief path | free-text idea>"
disable-model-invocation: true
---

# execute-change

Execute a plan brief end to end in an OpenSpec-managed repository. You (the
session that loaded this skill) are the **lead**: you coordinate, you never
implement. Every pipeline step runs in a fresh subagent with an empty context;
you check each subagent's work against evidence on disk, commit checkpoints,
pause for the user only on genuine human decisions (the question reaches
their phone via Remote Control push), and stop after a local commit — the
user deploys, archives, and opens the PR by hand.

Each run works in its **own git worktree**, created at preflight: the
pipeline never touches the main working tree (a design-first run writes
only the brief there), and several runs with different plans can execute
on one repo at once — each has its own worktree and branch, and git
refuses to check one branch out twice.

The argument (`$ARGUMENTS`) is either a plan-brief path or a free-text
idea: if it resolves to an existing file, it is the brief — go straight to
Step 0; anything else is an idea — run the design-first entry below first.
One guard: an argument that looks like a file path (contains a slash or
ends in `.md`) but matches no file is probably a typo'd brief path — ask
before treating it as an idea.
No argument → list the `docs/up next/*-plan.md` candidates and ask the
user to pick one or state an idea.

## Ground rules

These are non-negotiable for every run:

1. **The lead never does the work itself — every task runs in a
   subagent.** This is what keeps the run alive for hours: the lead's
   context must hold coordination state (the ledger, verdicts, decisions),
   not code, research, or logs. Start a subagent for anything substantial
   — authoring, research, implementation, fixing, bulk file reading — and
   consume only its report. The only files you write directly are the
   ledger, the plan brief (design-first entry only), and, at close-out,
   the `tasks.md` checkbox reconciliation; the lead never edits source
   files.
2. **A subagent's "done" claim is not evidence.** After every step, run the
   acceptance check defined for that step before advancing. A failed check
   gets exactly one retry — a fresh subagent with the failure fed back —
   then you pause and ask the user. A subagent that dies, or whose skill
   refuses to run, pauses the run immediately: never guess forward.
3. **Human decisions pause the run.** (The design-entry interview is the
   one exception: it deliberately asks one category at a time, before any
   ledger exists.) Open questions and design forks from
   any subagent report are batched into ONE pause per step — a single
   AskUserQuestion, or consecutive calls when there are more than 4 forks
   (the tool's per-call limit). Update the ledger first, then wait: the
   question waits indefinitely, survives machine sleep, and pushes to the
   user's phone. Never resolve a fork by assumption.
4. **Never:** deploy, push, open a PR, archive the OpenSpec change, commit
   the ledger or the plan brief, or use `git add -A` / `git add .` — every
   commit stages explicit paths (`git add <path>...`).
5. **Internal knowledge is outdated.** Every subagent prompt embeds the
   standing implementer instructions: return open questions instead of
   guessing, and verify external library/API behavior against current
   documentation, not memory.
6. **The ledger is the source of truth.** Re-read it at every step boundary;
   after any auto-compaction, also re-read this SKILL.md from disk before
   continuing. Resume runs continue from the ledger, never from memory.

There is no `allowed-tools`/`disallowed-tools` line in the frontmatter — the
lead needs the Agent tool, Bash, AskUserQuestion, and file tools, so the
never-rules above are workflow discipline, not a tool-pool restriction.

## Design-first entry — from idea to approved brief

Only when the argument is an idea, not a file. Two quick guards first:
run Step 0 check 3 (OpenSpec-managed?) now — one command, so a
non-OpenSpec repo fails before the interview, not after it; and scan
`docs/up next/*.ledger.md` — an existing ledger whose brief matches this
idea is an interrupted run: offer resume instead of a new interview.

This phase runs **before Step 0**: no branch, worktree, or ledger exists
yet, everything happens in the main tree, and an interruption here simply
restarts the entry. The locked decisions are recorded in the brief
itself, which the step-1 author reads.

1. **Research.** Launch a fresh research subagent (prompt in
   [`references/step-prompts.md`](references/step-prompts.md)) — it reads
   the relevant code read-only, verifies external capabilities against
   current documentation, and returns a compact design dossier: facts,
   constraints, reuse candidates, decision points. You do not read the
   code yourself — the dossier keeps your context lean for the long run.
2. **Interview.** From the dossier, surface every genuinely open design
   decision as categorized questions (A, B, C, …), each option list
   carrying a `[REC]`-marked recommended default — one category per
   AskUserQuestion call (4 questions per call; more → consecutive calls).
   Lock each category as it is answered; continue until no ambiguity
   remains. Never assume an answer.
3. **Draft the brief.** Write
   `docs/up next/<YYYY-MM-DD-HHmm>-<slug>-plan.md` (folder created if
   missing; slug derived from the idea): context, the locked decisions,
   requirements, technical approach, out of scope, verification
   expectations. This is the one source-tree file the lead writes itself;
   like any brief, it is never committed by the run.
4. **Approval gate.** Post a compact summary plus the file path, then ask:
   approve / request changes (AskUserQuestion — works from the phone).
   Changes loop back into the draft, and into the interview if they open
   a new fork. Only an approved brief enters Step 0 — nothing executes on
   an unapproved brief.

From here the run is identical to the brief-path entry: continue with
Step 0 using the new brief's path.

## Step 0 — Preflight (the user is still at the keyboard)

Full command detail, the companion-skill check, and the one-time machine
setup (Remote Control, push notifications, permission allowlist, optional
hooks) live in [`references/preflight.md`](references/preflight.md)
**(read it when you reach this step)**.

Run the checks in this order:

1. **Plan brief.** Resolve the argument to a file; it must exist and be
   readable. Read it fully. (No candidates under `docs/up next/`? Ask the
   user for the path — repos may keep briefs elsewhere.)
2. **Resume check — before anything is created.** If the brief's ledger
   (check 8 defines its exact name) already exists, this is a resume:
   re-read the recorded branch, worktree path, change ID, base branch, and
   last completed step; if the worktree directory no longer exists, run
   `git worktree prune` first (a hand-deleted folder leaves a stale
   registration that makes the add fail), then recreate it
   (`git worktree add <recorded path> <recorded branch>` — the branch
   still exists) and re-run the project's dependency install in it
   (a recreated worktree is a bare checkout; the gates need it). If the
   worktree survived, `git status` it: uncommitted changes, or a ledger
   that disagrees with the branch (e.g. a committed group with no ledger
   summary), → surface to the user before continuing — never build on
   unexplained edits. Then re-run
   checks 3–5 (the environment can drift between runs), skip checks 6–8 —
   the branch, worktree, and ledger already exist, and the ledger records
   the check-7 answers — and continue the pipeline from the ledger. Never
   create a second branch, worktree, or ledger for the same plan.
3. **OpenSpec-managed repo.** `openspec/config.yaml` at the repo root
   confirms it. If absent, run `openspec context` — a non-zero exit means
   the repo is not OpenSpec-managed: stop and explain (a repo without a
   local `openspec/` directory can still be managed via stores, which is
   why the CLI, not the directory, is the authority). One ordering caveat:
   if `openspec` is not installed at all, `openspec context` cannot answer
   — when `config.yaml` is absent AND the CLI is missing, run check 4's
   install path first, then return here.
4. **OpenSpec CLI installed and current.**
   - `openspec --version` fails → AskUserQuestion: install globally? On
     yes: `npm install -g @fission-ai/openspec@latest`, then `openspec
     update` in the repo.
   - Compare the installed version to `npm view @fission-ai/openspec
     version`. Older → AskUserQuestion: update? On yes: the same two
     commands. **Trap:** an outdated CLI silently reports "up to date" from
     `openspec update` — the version comparison is always against npm,
     never against `openspec update`'s own output.
   - If `openspec update` regenerated `.claude/commands/opsx/` or
     `.claude/skills/openspec-*` files: warn the user that commands and
     skills are scanned at session start, and ask whether to restart the
     session before executing (recommended) or continue with the current
     one.
5. **Companion skills.** The run depends on `plan-eng-review` and
   `verify-implementation` being installed (repo-level `.claude/skills/` or
   user-level). If either is missing → AskUserQuestion: install via
   `npx skills add https://github.com/Mi9-LLC/agent-skills --skill <name>`?
   On yes, install — with the same session-restart warning as above. Also
   confirm the repo's own OpenSpec flows exist (`.claude/commands/opsx/` or
   `.claude/skills/openspec-*` files — steps 1 and 4 invoke them); missing
   → `openspec update` regenerates them (restart warning again).
6. **Worktree and branch.** Identify the default branch; `git fetch`
   first so the branch is created from a current base (a fetch failure is
   not fatal — note it and continue from the local base). Build the run
   name `<timestamp>-<plan name>`: `<timestamp>` is the current date-time
   at run start (e.g. `20260813-1054`) — never a date taken from the
   brief's filename, which may be days old; `<plan name>` is the brief's
   filename without its extension and with any date-time stamp the
   filename itself carries stripped out, sanitized for git (spaces →
   hyphens). Then, from the main repo root (the path below is relative to
   it), create the run's dedicated worktree and branch in one command:

   ```bash
   git worktree add "../<repo folder name>.worktrees/<run name>" \
     -b agent/execute-change/<run name> <default branch>
   ```

   The entire run — every subagent, every lead command, every commit —
   happens inside that worktree; treat it as the repository root from here
   on. The main working tree is never touched (it may stay dirty; the user
   can keep working in it), and the run's only writes outside the worktree
   are the ledger and, on a design-first run, the brief it drafted — side
   by side in the main tree. Finally, prepare the worktree so
   the quality gates can run: the project's dependency install as its own
   docs define it (e.g. `npm ci`) — a per-run setup cost.
7. **Readiness and authorization** — one batched AskUserQuestion:
   - Remote Control and "Push when actions required" are on (or the user
     accepts terminal-only waiting);
   - the run is authorized to proceed autonomously through local commits
     on the feature branch;
   - whether task groups marked parallel may run concurrently.
8. **Ledger.** Create `<plan path>.ledger.md` next to the plan brief —
   literally append `.ledger.md` to the brief's full filename (e.g.
   `foo-plan.md` → `foo-plan.md.ledger.md`); this exact name is the resume
   key:

   ```markdown
   # execute-change ledger — <plan brief filename>
   - Branch: agent/execute-change/<run name>
   - Worktree: <absolute path of the worktree created in check 6>
   - Base branch: <the default branch identified in check 6>
   - Change ID: (set after step 1)
   - Last completed step: 0
   - Parallel groups approved: yes/no
   - Fix cycles used: 0 of 2
   ## Step log        <!-- per step: subagent outcome + acceptance-check result -->
   ## Decisions       <!-- every user answer, verbatim -->
   ## Open questions
   ## Completed implementation groups   <!-- one paragraph per group -->
   ```

   The ledger and the plan brief are never committed; the user deletes both
   at manual close-out.

## The pipeline — how every step runs

Steps 1–8 run through **fresh subagents** — normally one per step, with
the exceptions their sections define: step 3 is lead-run (no subagent),
step 6 launches one per task group, and steps 5, 7, and 8 may launch a
bounded follow-up (re-review / fix subagent). Every prompt is taken
verbatim from
[`references/step-prompts.md`](references/step-prompts.md) **(read it when
you reach step 1 and keep it open for the rest of the run)**, with the
placeholders filled from the ledger: the change ID, the change folder
`openspec/changes/<id>/` inside the worktree, the branch, the base branch,
and the worktree path. Every acceptance-check command you run below —
`openspec validate`, the diffs, the commits, the gates — runs inside the
worktree.

**Acceptance checks** (run by you, the lead, after each step completes —
the step's checkpoint commit, where one is defined, happens only AFTER its
check passes, never before). When a check passes, update the ledger before
advancing: set "Last completed step" to that step and record the outcome
in the Step log — this field is the resume key; left unwritten, a crash
resumes at step 1.

| After step | Evidence required on disk |
|---|---|
| 1, 4 | Expected artifacts exist in `openspec/changes/<id>/` AND `openspec validate <id> --strict` passes |
| 2 | `design.md` contains a review report with a verdict |
| 3 | Every answered decision is recorded in the ledger |
| 5 | The landing report says LANDED for every item, with quoted evidence |
| 6 (each group) | The group's files actually changed in the worktree, matching its report (uncommitted at check time — the commit follows the check) |
| 7 | An audit report with a verdict exists |
| 8 | The simplify report exists and the project's gates passed |

**Commit model** — a deliberate deviation from the manual routine's single
close-out commit, so a crash is resumable from the last checkpoint and the
step-7 audit gets a real branch-vs-base diff. You commit by explicit
pathspec:

- after step 5: the OpenSpec change artifacts (`openspec/changes/<id>/`);
- after each step-6 group: that group's changed files;
- after each step-7 fix cycle: the fix subagent's changed files, committed
  BEFORE the re-audit — the audit diffs committed state only, so an
  uncommitted fix is invisible to it;
- after step 8: the simplification changes;
- at close-out: the `tasks.md` reconciliation.

`verify-implementation` makes its own dedicated fix commits during step 7 —
that is how the skill already works, and the feature branch is not shared.
The ledger and the plan brief are excluded from every commit.

**Models.** Steps 1, 2, 4, 5, 7, and 8 run on Opus — pass the model
explicitly on step 7 too; do not rely on `verify-implementation`'s own
pin propagating into a subagent. Step 6 groups run on the model their
`tasks.md` row names, passed as
the Agent tool's `model` option — a missing or unmappable model name means
Opus, never a more expensive tier (catalog constraint: never pin Fable).

## Step 1 — Author the OpenSpec change

Subagent (Opus) authors the change from the plan brief via the repo's own
OpenSpec propose skill — the `/opsx:propose` flow; its generated skill
name varies by CLI version (e.g. `openspec-propose` or
`openspec-propose-change`) — with, per task group, a model, a
parallel-group marking, and a file list (parallel safety depends on it):
`proposal.md`,
`design.md`, spec deltas, and `tasks.md` with a model column, parallel
groups, verify clauses, and the standing implementer instructions. When it
returns, record the change ID in the ledger, then run the acceptance check.

## Step 2 — Engineering review of the change

Subagent (Opus) runs `plan-eng-review` against the change artifacts. The
prompt states verbatim: you run non-interactively — do not call
AskUserQuestion; record every fork under `UNRESOLVED DECISIONS`; the file
that receives the spliced report is `design.md`.

## Step 3 — Resolve the review's open decisions (lead → user)

If the review left anything under `UNRESOLVED DECISIONS`, batch all of it
into one AskUserQuestion (this is the first place the phone push earns its
setup — the run may have been unattended for a while). AskUserQuestion
takes at most 4 questions per call — more forks than that means
consecutive calls in the same pause, never dropped or merged-beyond-
recognition questions. Record every answer in the ledger's Decisions
section. No unresolved decisions → skip to step 4.

## Step 4 — Apply the review's required changes

A verdict of `APPROVED` with zero required changes and zero decisions →
skip steps 4–5 entirely and make the first checkpoint commit (the change
artifacts) now. Otherwise: subagent (Opus) applies the review's Required
plan changes via the repo's
OpenSpec update skill (the `/opsx:update` flow; generated name varies by
CLI version, e.g. `openspec-update-change`) AND folds the user's answered
decisions into the report's Decisions block.

## Step 5 — Confirm the changes landed

Fresh subagent (Opus) — deliberately not the step-4 author — checks that
each required change and each answered decision is actually present in the
artifacts, with per-item evidence in its report. Any MISSING item means
step 4 failed, not step 5: re-run step 4 with only the missing items as
its inputs, then step 5 again — once; still MISSING → pause and ask. If
the step-2 verdict was
`NEEDS REVISION`, one re-run of `plan-eng-review` follows (decisions carried
forward). Re-review outcomes: `APPROVED` → proceed; `APPROVED WITH CHANGES`
with new required changes, or new `UNRESOLVED DECISIONS` → loop back through
steps 3–5 exactly once; still `NEEDS REVISION`, or anything unresolved after
that one loop → pause and ask the user. Once the check passes, commit the
change artifacts (first checkpoint commit).

## Step 6 — Implement, task group by task group

One subagent per `tasks.md` task group, sequential in dependency order, each
on the model its row names. Each group's prompt carries: the change folder
path, its task group verbatim, the ledger's summaries of completed groups,
and an instruction to read the branch diff so far. The implementer never
ticks its own checkboxes and never self-verifies.

Groups marked parallel run concurrently ONLY when the user approved
concurrency in Step 0 AND their file lists in `tasks.md` are disjoint —
no file lists in `tasks.md` means the condition is unevaluable: serialize.
Serialized is also the default otherwise: they share one working tree. A
parallel set runs like this: launch every group in the set from the same
snapshot (identical branch diff and completed-group summaries), using the
parallel variant of the step-6 prompt (verify clauses only — no
project-wide gates, they would race in the shared tree); when the whole
set has returned, run the acceptance checks serially, then the project's
quality gates once over the still-uncommitted set, and only after the
gates pass make the per-group pathspec commits (the after-the-check
commit rule holds — nothing red gets committed). A gate failure
attributable to one group is that group's failed acceptance check (one
retry); a failure spanning groups treats the whole set as the failed unit
— one retry of the set, then pause and ask.

After each group passes its acceptance check: commit the group by pathspec,
add a one-paragraph summary to the ledger, advance.

## Step 7 — Audit the implementation

Subagent runs `verify-implementation` over the whole change; the prompt
states the diff scope verbatim: the feature branch against its base branch.
A `NEEDS ATTENTION` verdict → feed the findings to a fix subagent (Opus),
check its report, commit its changes by pathspec (the file list from that
report), and only then re-run the audit — it reads committed state.
Maximum 2 fix cycles for the whole run — update the ledger's "Fix cycles
used" counter as each one starts (a crash must not reset the bound) —
then pause and ask the user.

## Step 8 — Simplification pass

Subagent (Opus) with a self-contained prompt: review the combined branch
diff for reuse, simplification, and efficiency cleanups; apply only
behavior-preserving fixes. (Deliberately not the `/simplify` built-in — its
availability inside subagents is unverified.) The subagent re-runs the
project's own quality gates before reporting; its edits stay uncommitted
until they pass. A gate failure → launch step 7's fix subagent with the
failing gate output as the findings, then re-run the gates — not the full
audit; each such cycle counts toward the same 2-cycle bound, and a bound
already exhausted means pause and ask immediately. On green: commit the
simplification changes by pathspec.

## Close-out — reconcile, validate, stop

1. Reconcile the `tasks.md` checkboxes against the audit evidence — the
   lead's one permitted source edit — and commit that reconciliation by
   pathspec.
2. `openspec validate <id> --strict` as a read-only final check.
3. **STOP.** Report to the user: verdicts per step, decisions taken, the
   commit list, the worktree path, and the remaining manual steps verbatim:
   deploy to the dev environment and smoke-test, update the work-folder
   CLAUDE.md files, delete the plan brief and the ledger, `opsx:archive`
   the change, open the PR, and after the PR remove the run's worktree
   (`git worktree remove <path>`).

## Pause-and-notify rules (apply at every step)

- A subagent report containing open questions or forks → batch them into
  one pause for that step (a single AskUserQuestion; consecutive calls in
  the same pause when there are more than 4 forks), update the ledger, and
  wait. With Remote Control on, the question pushes to the phone, waits
  indefinitely, and survives machine sleep.
- An unexpected permission prompt behaves the same way — waits and
  notifies. This is why the skill does not demand `bypassPermissions`;
  `references/preflight.md` documents the recommended per-repo allowlist
  and `acceptEdits` mode so routine commands don't prompt.
- Hard failure (a subagent dies or its skill refuses) → pause and ask,
  never guess forward. Soft failure (a "done" claim that fails your
  acceptance check) → one retry with the failure fed back, then pause
  and ask.

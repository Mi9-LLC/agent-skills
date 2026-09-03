---
name: execute-change
description: >-
  Autonomous end-to-end execution of a plan brief in an OpenSpec-managed repo:
  one lead session drives the whole feature routine — author the OpenSpec
  change, engineering review gate, apply the required changes, implement task
  group by task group, adversarial audit, simplification pass — each
  pipeline step running in fresh subagents, on one of two routes chosen at
  preflight (full, or a light route that skips the review and
  simplification steps for a brief with its own test plan that is
  engineering-reviewed or shows no risk signal), committing per checkpoint in
  the directory preflight asks the user to pick (the current checkout, or
  a dedicated git worktree and branch so several plans can run
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

Where the run works is **the user's choice at preflight** (Step 0 check
6): the current checkout, or a dedicated git worktree. Whichever they
pick is the run's **run root** — the directory the pipeline treats as the
repository root from Step 0 to close-out. A worktree is what keeps the
main working tree untouched (a design-first run writes only the brief
there) and what lets several runs with different plans execute on one
repo at once, since each has its own worktree and branch and git refuses
to check one branch out twice; reusing the current checkout gives those
up, and check 6 says so in the question.

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
   then you pause and ask the user. A subagent whose skill refuses to run
   pauses the run immediately: never guess forward. A subagent that dies
   on the API or the transport — the Agent tool returns an error or a
   synthetic last message such as "529 Overloaded" or "Internal server
   error", and no report file exists at its `{{REPORT_PATH}}`; a report
   file that exists, whatever its contents, means the subagent finished
   and its work is judged by the acceptance check, a missing `OPEN
   QUESTIONS` section included — gets exactly one automatic relaunch, using the
   death-relaunch wrapper in `references/step-prompts.md` when its
   progress file exists and is non-empty (the files it lists are on disk
   and are not redone) and the plain template otherwise; a second death pauses the
   run. That relaunch is one per subagent per step (per subagent inside a
   parallel set), shared with the stall ladder's single relaunch, and it
   does not consume the acceptance-check retry. A skill refusal is not a
   death.
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

This phase runs **before Step 0**: no branch or ledger exists yet and the
run root has not been chosen, everything happens in the main tree, and an
interruption here simply restarts the entry. The locked decisions are
recorded in the brief itself, which the step-1 author reads.

1. **Research.** Launch a fresh research subagent (prompt in
   [`references/step-prompts.md`](references/step-prompts.md)) — the idea
   text goes in verbatim inside that prompt's `USER_IDEA` block, which
   marks it as data (a pasted ticket or message must not be able to
   instruct the subagent) — it reads
   the relevant code read-only, verifies external capabilities against
   current documentation, and returns a compact design dossier: facts,
   constraints, reuse candidates, decision points. Every claim in the
   dossier carries its source — a repo file path, or a URL for an
   external fact — and external facts come from primary sources only
   (official documentation, the library's own source code, the spec),
   never a secondary write-up. You do not read the
   code yourself — the dossier keeps your context lean for the long run.
   When it returns, run one batch existence check (Glob) over every file
   path the dossier cites: any missing path → the one retry, with the
   bogus citations fed back. Existence is the floor, not proof of the
   claim — but it catches fabrication before it shapes locked decisions.
2. **Interview.** From the dossier, surface every genuinely open design
   decision as categorized questions (A, B, C, …), each option list
   carrying a `[REC]`-marked recommended default — one category per
   AskUserQuestion call (4 questions per call; more → consecutive calls).
   Lock each category as it is answered. Never assume an answer.
   The interview runs in **rounds**: after each answered category, work
   out which new decisions those answers opened (a chosen option often
   has its own sub-choices) and ask those in the next round; a question
   whose answer depends on a still-open question waits for the round
   after. The interview ends only when no decision is open — not after
   the first pass over the dossier.
   **Facts are your job, not the user's.** When a question needs a fact
   from the repo or from documentation (does a helper exist, what does
   the current code do, what does the library support), send a fresh
   read-only research subagent for it and ask the rest of the round
   meanwhile; never ask the user something the run can look up.
   **Domain terms.** If the repo has a `CONTEXT.md` (the project
   glossary), the research dossier quotes the relevant entries; when the
   user's wording conflicts with a defined term, say so and ask which
   meaning applies. When the user uses a vague or overloaded word,
   propose one precise canonical term and its definition. Offer to record
   a decision as an ADR (architecture decision record, a short file under
   `docs/adr/`) only when all three hold: it is hard to reverse, it would
   surprise a future reader without context, and it was a real trade-off
   between viable options. Every resolved term and every accepted ADR
   candidate is written into the brief (item 3) — the lead does not write
   `CONTEXT.md` or `docs/adr/` itself.
3. **Draft the brief.** Write
   `docs/up next/<YYYY-MM-DD-HHmm>-<slug>-plan.md` (folder created if
   missing; slug derived from the idea): context, the locked decisions,
   requirements, technical approach, out of scope, verification
   expectations, plus two sections the Step 1 author turns into files:
   `## Glossary updates` (each resolved term with its one-or-two-sentence
   definition and the words to avoid) and `## Decisions to record as
   ADRs` (each accepted ADR candidate in 1–3 sentences: context, decision,
   why). Either section may read "none". The brief ends with a third
   section, `## Research dossier`, holding item 1's dossier verbatim —
   the subagents in steps 1, 2, and 7 already read the brief, and a
   resumed run re-reads it, so this section is what gives them the same
   facts the interview used instead of leaving those facts in your
   context only. This is the one source-tree file
   the lead writes itself; like any brief, it is never committed by the
   run.
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
**(read it when you reach this step)**. The third reference file,
[`references/domain-docs.md`](references/domain-docs.md), holds the
`CONTEXT.md` and ADR formats; only the step-1 author subagent reads it.

Run the checks in this order:

1. **Plan brief.** Resolve the argument to a file; it must exist and be
   readable. Read it fully. (No candidates under `docs/up next/`? Ask the
   user for the path — repos may keep briefs elsewhere.)
2. **Resume check — before anything is created.** If the brief's ledger
   (check 8 defines its exact name) already exists, this is a resume:
   re-read the recorded branch, run root, run-root option, change ID, base
   branch, and last completed step. What happens next depends on which
   option the ledger records.

   *Recorded as a worktree:* if the worktree directory no longer exists,
   run `git worktree prune` first (a hand-deleted folder leaves a stale
   registration that makes the add fail), then recreate it
   (`git worktree add <recorded path> <recorded branch>` — the branch
   still exists) and re-run the project's dependency install in it
   (a recreated worktree is a bare checkout; the gates need it).

   *Recorded as the current checkout:* nothing is created or recreated —
   the run root is a directory the user already owns. Verify instead that
   the recorded branch is the one checked out there
   (`git rev-parse --abbrev-ref HEAD`). A different branch is a
   stop-and-ask, never something to fix silently by checking the recorded
   branch out over whatever the user is now doing.

   Either way, `git status` the run root before continuing: uncommitted
   changes, or a ledger that disagrees with the branch (e.g. a committed
   group with no ledger summary), → surface to the user — never build on
   unexplained edits. (In a reused checkout a dirty tree may simply be the
   user's own work, which is exactly why it goes to them rather than being
   assumed either way.)

   Then do these three things, in this order, before the pipeline
   continues:

   1. **Re-run checks 3–5.** The environment can drift between runs.
   2. **Re-arm the hooks.** Rewrite `.claude/execute-change-run.json` in
      the directory THIS session was started in, carrying this session's
      own `session_id` — read from the `CLAUDE_CODE_SESSION_ID`
      environment variable, exactly as check 6 does, with the same
      empty-variable guard. The hooks match on that id, so until this is
      done a resumed run has every hook inert — it is a new session with
      a new id, and the file check 6 wrote names the old one. Keep the
      `run_root`, `branch`, and `ledger` values the ledger records, and
      keep the ORIGINAL `started_at`: the process sweep uses it as its
      cutoff, so resetting it would spare every process the run started
      before the interruption. Leave the recorded start commit alone — a
      resume re-reads that field from the ledger and never re-derives it.
      If `.claude/execute-change-run.json.parked` exists instead of the
      live file, the interrupted run crashed during a lead gate run
      (Step 6 parks the file for that window): take its values from the
      `.parked` copy, write the live file, and delete the `.parked` one,
      so the hooks are armed again.

      Then append one **resume boundary event** to the heartbeat log
      `.claude/execute-change-run.jsonl` beside it — a single line:

      ```json
      {"kind":"resume","at":"<now, ISO-8601 UTC>"}
      ```

      The log is appended to, never truncated or renamed: its history is
      worth keeping, and the boundary event is what makes the replay
      correct without losing it. Both replays that read this log — the
      hook's own sweep replay and the stall watcher below — treat a
      `resume` line as a hard reset and forget everything before it.
      Without it, the `start` lines of subagents the interruption killed
      have no matching `stop`, so the running set never empties again:
      the automatic sweep never runs for the rest of the resumed run and
      every watcher ends in `STALL`.

      **Order matters:** append the boundary event and rewrite the
      metadata file BEFORE arming any watcher, or the first watcher of
      the resumed run replays the stale tail.
   3. **Skip checks 6, 6a, 7, and 8.** The branch, run root, route, start
      commit, and ledger already exist. Never create a second branch, run
      root, or ledger for the same plan, and never re-ask the route.

   Then continue the pipeline from the ledger. The ledger's `Route` line
   decides which step follows `Last completed step`: a ledger with no
   `Route` line is a full-route run (older runs resume unchanged); a
   ledger with `Route: light` and `Last completed step` anywhere from 1
   to 5 resumes at step 6, because the light route has no steps 2 to 5.
3. **OpenSpec-managed repo.** `openspec/config.yaml` at the repo root
   confirms it. If absent, run `openspec context` — a non-zero exit means
   the repo is not OpenSpec-managed (a repo without a local `openspec/`
   directory can still be managed via stores, which is why the CLI, not
   the directory, is the authority). One ordering caveat: if `openspec`
   is not installed at all, `openspec context` cannot answer — when
   `config.yaml` is absent AND the CLI is missing, run check 4's install
   path first, then return here.

   **Not managed → ask. Never end the run on a printed message alone.**
   A notice is something the user can scroll past or read after the fact,
   and a run that ends that way ends without them noticing. This is a
   blocking AskUserQuestion, and the run waits on the answer:

   - **Stop the run and work without OpenSpec** — recommend this one.
     The pipeline has no change to author, review, or validate here, so
     it cannot run at all. Hand the plan brief back and continue in this
     session as ordinary work: no run branch, no checkpoint commits, and
     none of the review or audit gates.
   - **Run `openspec init` here, then continue the run.** This writes an
     `openspec/` directory and Claude command files into the repo, so it
     changes the repo before any plan work begins. A repo that is not
     OpenSpec-managed is usually that way on purpose, which is why the
     first option is the recommended one.

   On the init answer, **bring the CLI current before initializing**: run
   check 4's version comparison against `npm view @fission-ai/openspec
   version` and take its install/update path when the local CLI is older.
   `openspec init` generates the repo's instruction and command files, so
   an outdated CLI writes outdated ones into a brand-new root — the one
   moment where a stale CLI does lasting damage. Then initialize
   (`openspec init --tools claude`; `--tools` is required, not cosmetic —
   [`references/preflight.md`](references/preflight.md) has the flags and
   the traps), re-run `openspec context` to confirm the root now resolves,
   and apply check 4's restart rule, because `init` creates
   `.claude/commands/opsx/` and commands are scanned at session start.
   Record the answer in the ledger's Decisions block when check 8 creates
   it.
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
6. **Run root and branch — a blocking question.** Identify the default
   branch; `git fetch` first so a branch created here starts from a
   current base (a fetch failure is not fatal — note it and continue from
   the local base). Build the run name
   `<timestamp>-<plan name>`: `<timestamp>` is the current date-time
   at run start (e.g. `20260813-1054`) — never a date taken from the
   brief's filename, which may be days old; `<plan name>` is the brief's
   filename without its extension and with any date-time stamp the
   filename itself carries stripped out, sanitized for git (spaces →
   hyphens).

   **The run root** is the directory the whole run works in: every
   subagent, every lead command, every commit, and every acceptance check
   treats it as the repository root from here on. Which directory that is
   is the user's decision, and it is a blocking AskUserQuestion asked
   before anything is created. Read the two facts the question needs
   first: the branch checked out right now (`git rev-parse --abbrev-ref
   HEAD`) and whether the tree is dirty (`git status --porcelain`).

   - **Reuse the current branch and this checkout** — recommend this one.
     Commits go onto the branch that is checked out now, in this
     directory. No branch is created, no directory is created, and the
     run root is this checkout.
   - **Create the run's branch in this checkout.**
     `git checkout -b agent/execute-change/<run name> <default branch>`
     here: the run gets its own branch, but the run root is still this
     one directory.
   - **Create a dedicated worktree and branch.** A separate checkout of
     its own, created from the main repo root (the path is relative to
     it), and the run root is that new directory:

     ```bash
     git worktree add "../<repo folder name>.worktrees/<run name>" \
       -b agent/execute-change/<run name> <default branch>
     ```

   Put these facts in the question itself — they are what makes the answer
   an informed one, not decoration:

   - **The first two options give up three things the third provides.**
     The run root is then the user's own working tree, so "the run never
     touches your main working tree" stops being true; the user cannot
     keep working in the repo while the run executes, since subagents
     edit files under them for hours; and a concurrent run of a different
     plan on this repo is not supported — a separate worktree is what
     makes that possible, because git refuses to check one branch out
     twice.
   - **The first option while the default branch is checked out.** When
     HEAD is the default branch (`main`, `master`, whatever this check
     resolved), say so plainly in the question text: reusing it commits an
     hours-long autonomous change straight onto the default branch. Do not
     block it — the answer is the user's — but never let it pass unstated.
   - **The first two options with a dirty tree.** When
     `git status --porcelain` is non-empty, name that in the question.
     Commits stage explicit pathspecs, so unrelated modified files are
     never committed; but the baseline gate run and every later gate run
     execute against those changes, so a failure they cause can be blamed
     on the implementation. Committing or stashing first is the clean
     path.
   - **The first two options and the process sweep.** When the last
     subagent of a batch stops, the run sweeps the run root: it kills
     allowlisted build and test processes (`node`, `npm`, `vitest`,
     `dotnet`, and the like) whose command line names the run root, or
     that descend from this `claude` process, started after the batch
     began. Reusing this checkout puts that sweep in the user's own
     directory at the end of every subagent batch, and a `vitest` or dev
     server they started in another terminal carries the run root's path
     on its command line, so it is killed too. The sweep runs
     automatically, with no preview and no confirmation. It also reaches
     the lead's own gate runs: a gate run in the run root is a child of
     this `claude` process and names the run root on its command line,
     so a sweep fired while it runs kills it, and the killed run looks
     like a real failure (observed twice on 2026-09-01, 50 minutes lost).
     The mitigation is the parking rule in Step 6: the metadata file is
     moved aside for every lead gate run, which disarms the hooks for
     that window.

   **Second confirmation — the first option while the default branch is
   checked out.** When the user picks "reuse the current branch and this
   checkout" and HEAD is the default branch, ask once more, with a real
   second AskUserQuestion, before anything is created or written. State
   both consequences plainly: an hours-long autonomous run's checkpoint
   commits go straight onto the default branch, and step 7 runs
   `verify-implementation`, whose own rule is that it never commits to a
   shared branch — so its fix commits would land on the default branch
   too. Offer confirming the first option, switching to a new branch in
   this checkout (recommend this one here), or switching to a worktree.
   Only a clear confirmation proceeds on the default branch; any other
   answer takes the option it names.

   Record the answer in the ledger's Decisions block, and the chosen
   option in the ledger's Run root field (check 8) — a resume has to know
   whether a worktree exists.

   **Reusing this checkout means no worktree commands, ever.** Under
   either of the first two options, `git worktree add`, `git worktree
   remove`, and `git worktree prune` are not run at any point of the run:
   not here, not on resume (check 2), not at close-out — and the final
   report must not tell the user to remove a worktree that does not
   exist.

   Once the chosen option has been carried out and the run root exists,
   record the run's **start commit**: `git rev-parse HEAD` in the run
   root, the full sha. This is the diff base for steps 7 and 8. Every
   commit the run makes is a descendant of it under all three options,
   which is what makes it a scope the base branch cannot give: under the
   first option the base branch IS the branch the run commits on, so a
   base-branch diff is empty, and under a reused feature branch it also
   carries whatever the user committed before the run started.

   Whichever option was taken, the main tree keeps the ledger and, on a
   design-first run, the brief; under the worktree option those two —
   together with the metadata file and the heartbeat log written below,
   which also live in the session's project root — are the run's writes
   outside the run root. Then write the run's
   metadata file, `.claude/execute-change-run.json`, in **the directory
   this session was started in** — the main repo checkout — and not in
   the run root: the hooks start from the payload's `cwd` — the Bash
   tool's current directory, which a `cd` can leave inside a subdirectory
   — and walk up to the nearest directory holding the metadata file, and
   the session's project root is the one directory every such walk from
   inside the project reaches. Under the two reuse-checkout options the
   session's directory and the run root are the same directory anyway, so
   this is one fixed location in all three cases, not worktree-only
   special-casing. The `run_root` field inside the file is what points at
   the actual run root:

   ```json
   {
     "session_id": "<this lead session's id>",
     "run_root": "<absolute path of the run root chosen above>",
     "branch": "<the branch reused, or agent/execute-change/<run name>>",
     "ledger": "<plan path>.ledger.md",
     "started_at": "<run start, ISO-8601 UTC>"
   }
   ```

   **Where the session id comes from.** The Claude Code CLI puts it in the
   `CLAUDE_CODE_SESSION_ID` environment variable, and the Bash tool
   inherits it — read it, never guess it:

   ```bash
   SESSION_ID=$CLAUDE_CODE_SESSION_ID
   ```

   The hooks compare this string against the payload's `session_id`, so a
   wrong one makes every hook silently inert. **If the variable is empty
   or absent: say so to the user and continue WITHOUT writing the metadata
   file** — no file is better than a wrong id, because a wrong id leaves
   the hooks inert while the check-7 readiness line claims the heartbeat is
   armed. The run then proceeds degraded, exactly as it does on a machine
   where the hooks are not installed.

   **The payload's `cwd` is the shell's directory, not the session's.**
   Established 2026-09-01: a `cd` into a subdirectory of the project
   persists between the lead's Bash commands, and a hook that fires while
   the shell sits there receives that subdirectory as `cwd`. The hook as
   shipped before that date read `<cwd>/.claude/execute-change-run.json`
   literally, so every event fired while the shell was inside a package
   directory was lost — 4 of 8 `SubagentStart` events in one run, each
   launched right after a command that had changed into a package
   directory; the matching `SubagentStop` events were logged only because
   a later command had reset the directory. The hook now walks up from
   `cwd` to the nearest directory holding the metadata file, so a shell
   anywhere inside the project finds it. Two rules stay in force anyway,
   because an installed copy of the older hook has the defect until the
   plugin is updated and because a walk up from outside the project finds
   nothing: **never leave the shell in another directory** — run a
   command in a subdirectory as `(cd <dir> && <command>)`, or use `git -C
   <dir>`, `pnpm -C <dir>` / `pnpm --filter`, `dotnet <verb> <path>` —
   and **do not pass the run's worktree as an additional working
   directory** (`--add-dir`), since a `cd` into it is not reset and the
   worktree is outside the project tree, so no walk up reaches the
   metadata file. The symptom of either is a `start` (or every event)
   missing from `.claude/execute-change-run.jsonl` while `ListAgents`
   shows the subagent running.

   The ledger path is the file check 8 will create: `<plan path>.ledger.md`
   is deterministic from the brief path, so writing it here, before check 8
   runs, is safe. This file is what the three `execute-change` hooks read
   (`references/preflight.md` describes them) — it is written here,
   rewritten only by a resume (check 2) to carry the new session's id,
   and deleted at close-out. Finally, launch the
   run-root preparation as a BACKGROUND task, off the critical path
   (steps 1–5 don't need it):
   the project's dependency install (e.g. `npm ci`) followed by one run
   of the project's quality gates on the untouched run root — the
   **baseline**. A fresh worktree always needs that install; a reused
   checkout usually already has its dependencies, so run the install
   there only if the gates fail for missing ones — a reinstall in the
   user's own directory is a change they did not ask for. Record
   per-gate pass/fail (with any failing output) in
   the ledger's Baseline field when it finishes. Before the first step-6
   group launches: confirm the task completed, and surface a red baseline
   to the user — it means pre-existing failures that must never be
   attributed to the implementation.

   6a. **Route — asked in the same call as the run-root question.** The
   run takes one of two routes: **full** (steps 1 to 8 as written below)
   or **light** (step 1 in a lighter form, then steps 6 and 7; the `##
   Light route` section defines it). You propose the route from a
   checklist; the user confirms it as the second question of check 6's
   AskUserQuestion call, so Step 0 still has one pause. (Check 6's
   second confirmation for the default branch stays a separate follow-up
   call, as before.) No subagent: check 1 already made you read the brief
   fully. Answer six signals from the brief's own text — its file table,
   its order section, its headings — and print each answer in the
   question together with the brief line it comes from. A brief that does
   not say what it touches gets `yes` on the signal it leaves open.

   1. **Shared contract.** The change edits an exported type, function,
      schema, or API that another package in the repo, or another repo,
      imports.
   2. **Infrastructure or data.** Deploy scripts, cloud resources, alert
      policies, CI config, database migrations, backfills.
   3. **Sensitive paths.** Auth, permissions, secrets, locks, concurrency,
      caching.
   4. **Breadth.** More than one package, or more than 8 files expected to
      change (8 is `plan-eng-review`'s own hotspot threshold).
   5. **Test plan present.** The brief names concrete test cases and the
      commands or gates that prove them.
   6. **Engineering-reviewed.** The brief carries an `## ENG REVIEW
      REPORT` section whose verdict is `APPROVED` or `APPROVED WITH
      CHANGES`, whose closing marker is `NO UNRESOLVED DECISIONS`, and
      whose required changes are marked addressed. A `## Research
      dossier` section does not count: the design-first entry interviews
      the user but runs no engineering review.

   The recommendation rule, printed in the question with the six answers:

   - **Light [REC]** when signals 1 to 4 are all `no` AND 5 is `yes`; or
     when 5 and 6 are both `yes` (an engineering-reviewed plan with its
     own test plan — the full route would review it again).
   - **Full [REC]** otherwise.

   The user's answer is the route, whatever the recommendation was.
   Record it in the ledger's `Route` field (check 8) and in the Decisions
   block. There is no switch between routes once the run has started: a
   user who wants the review after choosing light stops the run, deletes
   the ledger, and re-runs with full.
7. **Readiness line — printed, never asked.** There is no approval
   question here. The manual invocation IS the authorization: this skill
   is invoke-only, it commits by explicit pathspec on the branch check 6
   settled, and it never pushes. Concurrency is decided mechanically at
   step 6 (disjoint `tasks.md` file lists, serialize otherwise) — at this
   point `tasks.md` does not exist yet, so there is nothing to approve.
   Print one line stating the run's shape before the user walks away:
   plan brief, branch, base branch, the run root with the option that
   produced it (reused checkout, new branch here, or worktree), the route
   (full or light, check 6a), and the
   notification state — read `agentPushNotifEnabled` and
   `hasUsedRemoteControl` from `~/.claude.json`; either one false or
   absent → say plainly that pauses
   will wait in this terminal only. Neither flag records the per-session
   `/remote-control` toggle, so this is a notice, not a claim that the
   phone push is confirmed working. The Step-0 questions are check 6's
   run-root fork and check 6a's route question, both always asked and
   asked in one call, plus the conditional ones: a
   missing brief path (check 1), unexplained edits in the run root on
   resume (check 2), the not-OpenSpec-managed fork
   (check 3), and the install/update offers in checks 4–5.
8. **Ledger.** Create `<plan path>.ledger.md` next to the plan brief —
   literally append `.ledger.md` to the brief's full filename (e.g.
   `foo-plan.md` → `foo-plan.md.ledger.md`); this exact name is the resume
   key:

   ```markdown
   # execute-change ledger — <plan brief filename>
   - Branch: <the branch check 6 settled on>
   - Run root: <absolute path> (reused-checkout | new-branch-here | worktree)
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

   The Start commit field is written once, by check 6. A resume re-reads
   it; it never recomputes it, because `HEAD` has moved since the run
   began and re-deriving it would shrink the audit's diff to the work
   done after the interruption.

   Next to the ledger, create the reports folder `<plan path>.reports/`
   (e.g. `foo-plan.md.reports/`). Every pipeline subagent writes its full
   report to a file there, named by the lead in its prompt as
   `{{REPORT_PATH}}` (`step1.md`, `step4.md`, `step5-reader.md`,
   `step5-review.md`, `step6-group3.md`, `step7-fix1.md`, and so on — the
   placeholder table in `references/step-prompts.md` is the full list),
   with `OPEN QUESTIONS` as the first section, and returns only
   the path plus a short summary. Read the file, not the returned text:
   on 2026-09-01 the returned report reached the lead truncated
   mid-sentence five times in one run, twice inside `OPEN QUESTIONS`.

   The ledger, the reports folder, and the plan brief are never committed;
   the user deletes all three at manual close-out.

## The pipeline — how every step runs

Steps 1–8 run through **fresh subagents** — normally one per step, with
the exceptions their sections define: step 3 is lead-run (no subagent),
step 5 is lead-run except for its conditional `tasks.md` reader and the
re-review it launches under `NEEDS REVISION`, step 6 launches one per
task group, and steps 7 and 8 may launch a bounded follow-up (fix
subagent). On the light route (check 6a) only steps 1, 6, and 7 run —
the `## Light route` section below defines the differences; everything
in this section applies to both routes unless it says otherwise. Every
prompt is taken verbatim from
[`references/step-prompts.md`](references/step-prompts.md) **(re-read the
step's template from that file immediately before each fill — never fill
one from memory; compaction corrupts verbatim-ness silently)**, with the
placeholders filled from the ledger: the change ID, the change folder
`openspec/changes/<id>/` inside the run root, the branch, the start commit
(`{{START_COMMIT}}` — the diff base every template's diff uses), the
run root path, and the report file (`{{REPORT_PATH}}` — one file per
step or task group under the reports folder check 8 created; the lead
reads that file, because the returned text can arrive truncated). The
base branch is a ledger field, not a placeholder: no
template takes it any more. Every acceptance-check command you run below —
`openspec validate`, the diffs, the commits, the gates — runs inside the
run root.

**Acceptance checks** (run by you, the lead, after each step completes —
the step's checkpoint commit, where one is defined, happens only AFTER its
check passes, never before). When a check passes, update the ledger before
advancing: set "Last completed step" to that step and record the outcome
in the Step log — this field is the resume key; left unwritten, a crash
resumes at step 1.

**The lead writes less.** A Step log entry is at most 5 lines: the
subagent's outcome, the acceptance-check result, the report file's path,
and at most two lines of what matters for the next step. Detail lives in
the report files, which the ledger names; do not copy it into the
ledger. Decisions are the one exception and stay verbatim. Between step
boundaries you write nothing except the ledger update and the next
prompt fill — no running commentary, no restatement of a report you have
already read. Measured on 2026-09-03: the lead alone wrote 235,000
tokens in one run, a 36 KB ledger among them, and wall time on this
pipeline equals words written.

**No unplanned fix subagents on planning documents.** A contradiction
between `proposal.md`, `design.md`, the spec deltas, and `tasks.md` goes
to the step 4 retry (the one permitted retry, with the contradiction as
its feedback) or to the user — never to an extra subagent the pipeline
does not define. On 2026-09-03 two such subagents were launched in step 5
to reconcile what two step 4 subagents had left; the run now has one
step 4 subagent, so that class of contradiction should not arise, and
when it does, it is a failed step 4.

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

**Commit model** — a deliberate deviation from the manual routine's single
close-out commit, so a crash is resumable from the last checkpoint and the
step-7 audit gets a real diff from the run's start commit. You commit by
explicit pathspec:

- after the change artifacts pass their last planning check — step 5 on
  the full route (or step 2 when the verdict was `APPROVED` with nothing
  to apply, since steps 4 and 5 are then skipped), step 1 on the light
  route: the OpenSpec change artifacts
  (`openspec/changes/<id>/`) plus any `CONTEXT.md` / `docs/adr/` files
  step 1 created or updated (the step-1 report lists them);
- after each step-6 group: that group's changed files;
- after each step-7 fix cycle: the fix subagent's changed files, committed
  BEFORE the re-audit — the audit diffs committed state only, so an
  uncommitted fix is invisible to it;
- after step 8: the simplification changes;
- at close-out: the `tasks.md` reconciliation.

`verify-implementation` makes its own dedicated fix commits during step 7 —
that is how the skill already works, and the feature branch is not shared.
The ledger and the plan brief are excluded from every commit.

**Models.** Steps 1, 2, 4, 7, and 8 run on Opus, and so do step 5's
conditional `tasks.md` reader and its re-review, step 6's set-failure fix
subagent, step 7's fix subagent, and the
design-entry research subagent — pass the model explicitly on step 7 too;
do not rely on `verify-implementation`'s own
pin propagating into a subagent. Step 6 groups run on the model their
`tasks.md` row names, passed as
the Agent tool's `model` option — a missing or unmappable model name means
Opus, never a more expensive tier (catalog constraint: never pin Fable).

## Light route

Chosen at check 6a. Full-route step numbers are kept, so `Last completed
step` and a resume keep their meaning: a light run's ledger goes 0, 1, 6,
7. Everything not named in this table runs exactly as on the full route.

| Step | Light route |
|---|---|
| 0 | As on the full route, plus check 6a. The baseline prep runs as before; the first step 6 group waits for it, as before. |
| 1 | **Light author** — Opus subagent on the `Step 1 (light)` template in `references/step-prompts.md`. It does NOT invoke the `/opsx:propose` flow, which writes every artifact of the schema, `design.md` included, and would re-plan the brief. It runs `openspec new change <id>` for the scaffold, then writes by hand: `proposal.md` (the brief's why and what, short); spec deltas under `specs/<capability>/spec.md`, one requirement per behavior the brief changes, in SHALL/MUST wording; `tasks.md` with the same columns as the full route (model, parallel group, blocked by, file list, verify clauses, the standing implementer instructions), its task groups taken from the brief's own order section. When the brief changes no observable behavior (a refactor, tooling, docs) it sets `skip_specs: true` in the change's `.openspec.yaml` and writes no delta. No `design.md`. The step 1 content rules apply. It also writes the brief's glossary and ADR sections to `CONTEXT.md` and `docs/adr/`, as the full-route author does. |
| 1, acceptance | The files exist (`proposal.md`, `tasks.md`, and either at least one delta or `skip_specs: true`); `openspec validate <id> --strict` passes; and you, the lead, run three mechanical checks on `tasks.md`: every group has a model, a blocked-by line, and at least one verify clause; the file lists of groups sharing a parallel group are disjoint; every listed file exists in the run root or is marked new. As on the full route, record the change ID in the ledger when the author returns, before these checks. A failed check is a failed step 1 (one retry with the failure fed back, then pause). Then the first checkpoint commit: the change artifacts plus step 1's `CONTEXT.md` / `docs/adr/` files. |
| 2 to 5 | Skipped. The Step log records one line: `Steps 2-5: skipped (light route)`. `Last completed step` goes from 1 straight to 6. |
| 6 | As on the full route. The step 6 template's read list names `design.md` and the spec deltas "if present", on both routes. |
| 7 | As on the full route: `verify-implementation` against `git diff <start commit>..HEAD`, at most 2 fix cycles. |
| 8 | Skipped. The Step log records `Step 8: skipped (light route)`. |
| Close-out | As on the full route. |

Pauses on the light route work as on the full route. There is no switch
to the full route mid-run: the full route's
step 2 needs a `design.md` the light author never writes, and a switch
would need a `design.md` author for a path nobody expects to take. A
user who wants the review stops the run, deletes the ledger, and re-runs
with full.

**What the light route gives up.** `verify-implementation` works from the
diff and the claims made about it. It cannot catch what `plan-eng-review`
catches before code exists: a changed path with no regression test asked
for, over-build inside the claim, silent-failure gaps, architecture and
performance findings, and a wrong `tasks.md` decomposition. The route
rule in check 6a sends every brief without a test plan to the full route
for this reason, and every brief with a risk signal too, unless an
engineering review has already been run on it (signal 6), in which case
`plan-eng-review` has already had its chance to catch those.

## Heartbeat and stall handling

A subagent that hangs — waiting on a permission prompt, stuck on a
question it cannot ask, or simply dead — costs the run hours of silence,
because the lead deliberately does not watch subagents work. Immediately
after launching any subagent, arm one background watcher with
`Bash(run_in_background: true)`: an `until` loop that re-reads
`.claude/execute-change-run.jsonl` **in the session's project root** — the
same directory check 6 wrote the metadata file in, since each hook writes
the log next to the metadata file it just read. Give the loop the absolute
path, not a bare relative one: the shell's working directory moves between
commands, so a relative path would silently resolve somewhere else. That
file is the heartbeat log the three `execute-change` hooks append to,
described in
[`references/preflight.md`](references/preflight.md) — every 180 seconds
and exits, which notifies you, on the first of these:

- the newest `start` event for a still-running agent has had no `stop` and
  no `notify` event for 3 consecutive checks (a 9-minute silence, detected
  at most 3 minutes late);
- a `notify` event of type `permission_prompt`, `agent_needs_input`, or
  `idle_prompt` arrived.

A `stop` event carries no success or failure signal — `SubagentStop`'s
payload has no field for one — so the watcher uses it only to take that
agent out of the running set. A failed step is caught where it always was:
by your own acceptance check after the subagent returns (the table in the
previous section). That check is the gate; the watcher only tells you when
to go and look. When a check does fail, the `stop` event's
`agent_transcript_path` points straight at that subagent's transcript,
which is the quickest way to see what it actually did.

It also prints one line every 30 minutes — `alive: N agents running,
oldest <age>` — so silence never means "unknown". That cadence is the
point: this is a check every 3 minutes that speaks only on trouble, not a
status line every 3 minutes. A persistent monitor at that rate can be
auto-stopped for volume, and every line it prints costs you the context
this skill's whole subagent design exists to protect.

```bash
# Arm this right after launching a subagent, with Bash(run_in_background: true).
# It stays quiet until you need to act, then exits — which notifies you.
LOG="<absolute path of the session's project root>/.claude/execute-change-run.jsonl"
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # the arm time: older events are not fresh activity
silent=0; checks=0; prev_last=""; verdict=""
until [ -n "$verdict" ]; do
  sleep 180
  checks=$((checks + 1))
  status=$(python - "$LOG" "$SINCE" <<'PY'
import datetime, json, sys
log, since = sys.argv[1], sys.argv[2]
iso = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
now = datetime.datetime.now(datetime.timezone.utc)
cut = iso(since)
try:
    lines = open(log, encoding="utf-8").read().splitlines()
except OSError:
    print("NOLOG"); raise SystemExit
running, last, trouble = {}, cut, ""
for line in lines:
    try:
        e = json.loads(line)
        at, kind = iso(e["at"]), e.get("kind")
    except Exception:
        continue
    # The running set is rebuilt from the WHOLE log: every start adds and every
    # stop removes, whatever their timestamps. cut is a separate question.
    # A resume boundary is a hard reset: the interrupted run's subagents died
    # without a stop, so their starts would otherwise hold the set non-empty
    # forever and every watcher would end in STALL. The log is appended to
    # rather than truncated -- the history is worth keeping, and this event is
    # what makes the replay correct without losing it.
    if kind == "resume":
        running.clear()
        continue
    if kind == "start":
        running[e.get("agent_id")] = at
        continue
    if kind == "stop":
        running.pop(e.get("agent_id"), None)   # a stop carries no pass/fail signal
    elif kind != "notify":
        continue
    if at < cut:
        continue          # predates this watcher: not fresh activity, not trouble
    last = max(last, at)
    if kind == "notify" and e.get("notification_type") in (
            "permission_prompt", "agent_needs_input", "idle_prompt"):
        trouble = "%s: %s" % (
            e.get("notification_type"), e.get("notification_text"))
if trouble:
    print("TROUBLE " + trouble)
elif not running:
    print("IDLE")
else:
    age = int((now - min(running.values())).total_seconds())
    print("RUN %d %d %s" % (len(running), age, last.isoformat()))
PY
)
  case "$status" in
    NOLOG*)   verdict="NOLOG - no heartbeat log; the execute-change hooks are not installed" ;;
    TROUBLE*) verdict="$status" ;;
    IDLE*)    verdict="IDLE - all subagents stopped" ;;
    RUN*)     set -- $status
              if [ "$4" = "$prev_last" ]; then
                silent=$((silent + 1))
              else
                silent=0; prev_last="$4"
              fi
              if [ "$silent" -ge 3 ]; then
                verdict="STALL - $2 agent(s) running, no stop or notify event for 9 minutes"
              elif [ $((checks % 10)) -eq 0 ]; then
                echo "alive: $2 agents running, oldest $(($3 / 60))m"
              fi ;;
    *)        verdict="WATCHER ERROR - unexpected output: $status" ;;
  esac
done
echo "$verdict"
```

**The watcher also exits when the batch is done.** `IDLE` means the log
shows every subagent stopped, and when that is true it is the normal end
of a watcher's life, not a finding — you already have the subagent's
return value and are back in control. Arm a fresh watcher at the next
launch. One watcher per launch that exits with its batch is the whole
design; a watcher left running past its batch would wait forever for
trouble that can no longer arrive.

**Confirm an `IDLE` verdict with `ListAgents` before believing it, exactly
as a `STALL`.** A `start` line can be missing: on 2026-09-01 the log held
`start` lines for 4 of 8 subagents in one session, and a parallel batch of
three launched with no `start` line for any of them. The cause is known
and fixed in the hook (check 6 explains it: the payload's `cwd` is the
shell's directory, and the hook now walks up from it), but an installed
copy of the older hook keeps the defect until the plugin is updated, and
the lead's own `cd` discipline is the other half of the guard. The
watcher replays `start` and `stop` lines to build its running set, so a
missing `start` leaves the set empty and the watcher prints `IDLE` at its
first check while the subagent works on for another ten minutes. An
`IDLE` that arrives before the subagent's return value is suspect on its
face. Call `ListAgents`: an agent listed as running means the replay is
wrong, not that the agent finished — re-arm and carry on. A missing
`start` also means every later `stop` event closes an apparently empty
batch, so the process sweep fires on every stop instead of once per
batch; that is why Step 6 parks the metadata file around lead gate runs.

**Fallback timer when the log cannot be trusted.** When `IDLE` has proved
false once in a run, or the hooks are not installed (`NOLOG`), arm a plain
timer instead of the log watcher, with `Bash(run_in_background: true)`:

```bash
sleep 175
echo "tick $(date -u +%H:%M:%SZ) newest-file: $(find '<run root>' -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort | tail -1)"
```

Its exit re-invokes you: call `ListAgents`, which is authoritative, and
re-arm. The newest-file line separates "working" (files still changing)
from "stuck" (nothing changed for two ticks) without waking the agent.
This costs one line of context every 3 minutes, which is why it is the
fallback and not the default.

A subagent can finish its work and report while `ListAgents` still shows
it running. Before a lead gate run starts, `TaskStop` such an agent
deliberately, so its `stop` event and any sweep land before the gates,
not during them.

A watcher can also vanish without printing anything. The `SubagentStop`
sweep runs at batch end and may kill the watcher's own shell before its
next 180-second check. A watcher that disappears at the end of a step is
normal either way.

**A STALL verdict means the log has been quiet for 9 minutes — not that
the subagent is stuck.** `SubagentStart` fires once and nothing else is
emitted until `SubagentStop`, so a step-6 implementer working normally for
20 minutes looks exactly like a stalled one from the log alone. The
9-minute trigger is the cheap signal to go and look; `ListAgents` is what
tells you what is actually happening. Call it first and read the agent's
row:

- still running or busy → it is working, not stalled: re-arm the watcher
  and carry on, and send the subagent nothing. **This is the expected
  common outcome** — a STALL line followed by a busy row is the watcher
  doing its job, not a failure, and repeated ones are not repeated
  failures.
- idle while its `stop` event has not arrived → a real stall, and only
  then does the ladder start: send it a status request with `SendMessage`;
  still idle at the next check → `TaskStop` it and relaunch it once —
  with the death-relaunch wrapper in
  [`references/step-prompts.md`](references/step-prompts.md) when the
  subagent's progress file exists and is non-empty (so the files it
  already finished are not redone), and with the retry wrapper otherwise,
  its `{{RETRY_FEEDBACK}}` filled with the stall itself ("the previous
  attempt stalled: no report file and no progress file after N minutes;
  any half-finished edits it left are in the working tree, see `git
  status --porcelain`"); still stuck after
  that → pause and ask the user. This relaunch is the same single
  relaunch ground rule 2 allows for an API death: one per subagent per
  step, whichever of the two spends it.

Write the `ListAgents` check and its outcome to the ledger, the same as
every other step.

**A `permission_prompt` notification is not a stall.** Only a human can
answer it, so there is nothing to retry: report it to the user at once and
wait.

**When the hooks are not installed**, no JSONL file ever appears and the
watcher exits on its first check with `NOLOG`. Say so once — in the Step 0
readiness line or in the step log — and fall back to the pause-and-notify
rules at the end of this file; never loop on a file that will not arrive.

## Step 1 — Author the OpenSpec change

Subagent (Opus) authors the change from the plan brief via the repo's own
OpenSpec propose skill — the `/opsx:propose` flow; its generated skill
name varies by CLI version (e.g. `openspec-propose` or
`openspec-propose-change`) — with, per task group, a model, a
parallel-group marking, and a file list (parallel safety depends on it):
`proposal.md`,
`design.md`, spec deltas, and `tasks.md` with a model column, parallel
groups, verify clauses, and the standing implementer instructions. Each
task group is a **vertical slice** — a piece of the change that can be
demonstrated or verified on its own, sized to fit one fresh context
window; a group that only prepares the ground for later groups
(prefactoring) comes first. One exception: a mechanical change too wide
for a vertical slice — renaming a shared symbol or a column, where one
edit breaks call sites across the whole codebase — is sequenced
**expand–contract** instead. The first group adds the new form beside the
old, so nothing breaks and that group is green on its own; the following
groups migrate the call sites in batches, one group per batch, each green
on its own because the old form still exists; the last group removes the
old form and is blocked by every migration batch.
The author also reads the repo's `CONTEXT.md`
and `docs/adr/` when present, uses the glossary's words in the artifacts,
and writes the brief's `## Glossary updates` and `## Decisions to record
as ADRs` sections into `CONTEXT.md` (repo root) and `docs/adr/NNNN-slug.md`
using the formats in
[`references/domain-docs.md`](references/domain-docs.md) — files created
only when there is something to write, so they are committed with the
change artifacts at the first checkpoint.

**Content rules, not line caps** (both routes; the step 1 templates
carry them): `design.md` holds only the decisions the brief leaves open,
one per heading, and restates neither the brief, nor the problem (that is
`proposal.md`), nor the code (the implementer reads it). `tasks.md` has
one line per task naming the file and the change — no rationale, no
code, nothing `design.md` or the brief already says; file lists and
verify clauses are never shortened, because the step 6 concurrency gate
and step 7 read them. On 2026-09-03 a 10 KB brief produced 154 KB of
artifacts (`design.md` 78 KB, `tasks.md` 58 KB), and wall time equals
words written. When the author returns, print `wc -l` of `design.md`
(full route) and `tasks.md` in the Step log — information only, no
threshold — record the change ID in the ledger, then run the acceptance
check.

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
section. No unresolved decisions → skip to step 4, but still set `Last
completed step` to 3 and log `Step 3: no unresolved decisions`, so a
resume never wonders whether step 3 ran.

Step 4 waits for the answers. Nothing is launched while the question is
out: the required changes and the decisions are applied by one subagent
in one pass, after the user has answered. The cost is up to about 16
minutes of subagent work that could have run during the pause; when the
user is away for hours the wait dominates anyway, and two subagents
editing `design.md` and `tasks.md` in sequence left contradictions on
2026-09-03 that took two more subagents to repair.

## Step 4 — Apply the review's required changes

A verdict of `APPROVED` with zero required changes and zero decisions →
skip steps 4–5 entirely and make the first checkpoint commit (the change
artifacts plus step 1's `CONTEXT.md` / `docs/adr/` files) now. Otherwise: subagent (Opus) applies the review's Required
plan changes via the repo's
OpenSpec update skill (the `/opsx:update` flow; generated name varies by
CLI version, e.g. `openspec-update-change`) AND folds the user's answered
decisions into the report's Decisions block — always one subagent, one
pass, launched after the step 3 answers are in (or at once, when step 3
had nothing to ask). Its report ends with a
`QUOTES` section: per required change and per decision, the file it
edited and ONE whole line quoted exactly as it stands after all edits,
the unslop pass included; and a `TASKS.MD RE-READ` section listing any
line of `tasks.md` that contradicts a change it made (or `none`). Those
quotes are what step 5 checks.

## Step 5 — Check that the changes are in the artifacts

**Lead-run, mechanical.** Step 4's `QUOTES` section is one fenced block
per file, opened by a `FILE: <path>` line, the quoted lines verbatim
below it (the step 4 template fixes that layout). Cut each block out of
the report file with `awk`, never by retyping, then check each quote
against the artifact as a whole line, carriage returns stripped from both
sides (the artifacts may be CRLF):

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
`tasks.md` file list, a group boundary, or a blocked-by order, a fresh
Opus subagent (the `Step 5 — conditional tasks.md reader` template)
checks only those items and reports PRESENT or MISSING per item. A file
count is the class of change a whole-line grep cannot judge (the one real
step 5 catch on 2026-09-03 was a file list of 12 where 14 were touched).
A `MISSING` from the reader is handled exactly like a `MISSING` quote.
No item of that class → no reader.

**Re-review under `NEEDS REVISION`.** When the step 2 verdict was `NEEDS
REVISION`, the re-run of `plan-eng-review` is mandatory and launches
right after the grep check (and the reader, when one ran) passes —
decisions carried forward, using the re-review prefix in
`references/step-prompts.md`. Re-review outcomes: `APPROVED` → proceed;
`APPROVED WITH CHANGES` with new required changes, or new `UNRESOLVED
DECISIONS` → loop back through steps 3–5 exactly once; still `NEEDS
REVISION`, or anything unresolved after that one loop → pause and ask the
user. Under `APPROVED WITH CHANGES` there is no re-review: step 5 is the
grep check, plus the conditional reader when an item of its class exists
(the reader's trigger is the class of change, not the verdict). Once
step 5 passes, commit the change artifacts
and step 1's `CONTEXT.md` / `docs/adr/` files (first checkpoint commit).

## Step 6 — Implement, task group by task group

One subagent per `tasks.md` task group, sequential in dependency order, each
on the model its row names. Each group's prompt carries: the change folder
path, its task group verbatim, the ledger's summaries of completed groups,
and an instruction to read the branch diff so far, plus `CONTEXT.md` and
`docs/adr/` when present (glossary words go into names and messages; an
ADR is never contradicted silently — a conflict comes back as an open
question). The implementer never
ticks its own checkboxes and never self-verifies.

Groups marked parallel run concurrently ONLY when their file lists in
`tasks.md` are disjoint —
no file lists in `tasks.md` means the condition is unevaluable: serialize.
Serialized is also the default otherwise: a parallel set shares one
working tree, and when check 6 reused the current checkout that tree is
the user's own. A
parallel set runs like this: launch every group in the set from the same
snapshot (identical branch diff and completed-group summaries), using the
parallel variant of the step-6 prompt (verify clauses only — no
project-wide gates, they would race in the shared tree); when the whole
set has returned, run the acceptance checks serially, then the gates the
proportionate rule below picks for the set's combined changed files, once
over the still-uncommitted set, and only after the
gates pass make the per-group pathspec commits (the after-the-check
commit rule holds — nothing red gets committed). A gate failure
attributable to one group is that group's failed acceptance check (one
retry); a failure spanning groups treats the whole set as the failed unit
— one retry of the set, then pause and ask.

**The retry of a set is one fix subagent, not a relaunch of every
group.** A failure that spans groups is an interaction between them (one
group changed a signature, another still calls the old one), and
relaunching each group in parallel gives every subagent half the picture
while they edit one shared tree. So: keep the set's uncommitted edits in
place, launch one Opus subagent on the step 7 fix template in its
set-failure variant (`references/step-prompts.md`), with the failing gate
output as its `{{FINDINGS}}`, the union of the set's `tasks.md` file
lists as its file scope, and `step6-set<N>-fix.md` as its report file
(`<N>` is the parallel group number). When it returns, run the set's
acceptance checks and gates once more. The acceptance check after a set
fix is: `git status --porcelain` matches the union of the group reports'
file lists plus the fix report's file list, and every file in the fix
report is in some group's `tasks.md` file list. Green → the per-group
pathspec commits as usual: every file the fix touched belongs to some
group's list, and goes in that group's commit. Red, or a file changed outside the
set's lists → pause and ask. This fix subagent is the set's single retry;
it does not count toward step 7's 2 fix cycles.

Before committing a serial group, run the gates yourself in the
run root — the implementer's own gate run is its iteration loop, not
evidence (a subagent's "done" claim is not evidence; this is the same
rule). The implementer does not run the full suite; your run is the only
one that counts, so it is not duplicated. Judge any failure against the
ledger's Baseline: a failure already
present at baseline is pre-existing — report it, never attribute it to
the group. Then, after the group passes its acceptance check and your
gate run: commit the group by pathspec, add a one-paragraph summary to
the ledger, advance.

**Which gates a group gets — proportionate to what it changed.** A full
gate run takes minutes (about 8 in one measured repo); five serial
groups times a full run each is 40 minutes, much of it proving nothing.
Decide from the group's changed files (`git status --porcelain` in the
run root):

- **Only documents, comments, or a README changed:** skip the type check
  and the tests — nothing there can break a test. Run only a gate that
  reads those files, if the project has one (a markdown lint, a link
  check).
- **Any code changed: the type check and the lint, always.** The type
  check (`tsc --noEmit`, `dotnet build --nologo`, or what the project's
  CLAUDE.md names) is fast and catches most of what breaks across files:
  a changed signature, a renamed export, a new required field.
- **Tests, when the runner has a related-tests mode:** run it over the
  group's changed source files — `vitest related <files>` or `jest
  --findRelatedTests <files>`. It runs every test file whose import
  graph reaches a changed file, so it covers the group's own tests plus
  tests in other groups' files that depend on the changed code. This is
  mechanical; it does not depend on reading the diff correctly.
- **Tests, when there is no such mode (.NET and others):** run the
  group's own test files, and the full suite when the group changes
  behavior that tests elsewhere assert on. The signals: a call count,
  the order of operations, the text of a SQL statement or a log message,
  state left behind after a run. Worked example: a group added one
  `probeInstance` call. No type error, and every test in its own file
  list passed. It broke an integration test in a different group's file
  that asserted on the exact list of probed names. A group that deletes
  a database row other tests assert still exists is the same shape, and
  no import graph catches that one either. This rule depends on your
  reading of the change: when unsure, run the full suite. It is cheaper
  than finding the breakage at the pre-audit run with several groups
  stacked on top.
- **The full gates once after the last group, before step 7**, whatever
  the per-group decisions were. A failure found there is located by
  bisecting the group commits — they are separate commits by pathspec.
  Steps 7 and 8 re-run the full gates as well.

**Park the metadata file for every lead gate run.** Under the two
reuse-the-checkout options of check 6, the `SubagentStop` sweep kills any
allowlisted process that descends from this `claude` process or names
the run root, started after the batch began — and a gate run you start
in the run root is both. Nested subagents (an implementer's own
`Explore` agents) and missed `start` events (see the heartbeat section)
make the sweep fire far more often than once per batch. So, immediately
before starting any gate run yourself, move
`<session project root>/.claude/execute-change-run.json` to
`execute-change-run.json.parked`, and move it back as soon as the gate
run has finished — after it ends, not when it is launched. The hooks
pass through when that file is absent, so the sweep cannot fire in that
window. Two costs: no `start`, `stop`, or `notify` line is logged while
the file is parked, so do this only when no subagent is running (the
serial flow guarantees that; `TaskStop` a subagent that has already
reported but still shows as running in `ListAgents` before you park);
and a crash between park and restore leaves the hooks inert — a resume
(check 2) must look for the `.parked` file and restore it.

**Before believing a gate failure, check that it was a failure.** A
killed gate run looks exactly like a real one: the block ends in
`[ELIFECYCLE] Command failed with exit code 1` and names no failing
test. Grep the gate's own output for a failing-test marker first
(`FAIL`, `✗`, `×`, `AssertionError`, or the runner's equivalent). None,
and the block ends in `ELIFECYCLE` → it was killed, not failed: look for
a `sweep` line containing `killed pid` near that timestamp in
`.claude/execute-change-run.jsonl`, re-run the gate, and do not
investigate a bug that does not exist.

## Step 7 — Audit the implementation

Subagent runs `verify-implementation` over the whole change; the prompt
states the diff scope verbatim: the run's start commit against `HEAD`
(`git diff <start commit>..HEAD`) — everything this run committed, and
nothing the branch already carried before it began.
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
3. Run the process sweep once over the run root — the `SubagentStop` hook
   already sweeps when the last subagent of a step stops, so this is the
   final guarantee, not the only one. The script's parameter is named
   `-Worktree` and keeps that name; the value you pass is the run root,
   whatever check 6 settled on:

   ```bash
   SWEEP=$(ls ~/.claude/plugins/cache/*/execute-change/*/hooks/sweep-worktree-processes.ps1 2>/dev/null | head -1)
   [ -n "$SWEEP" ] && pwsh -NoProfile -File "$SWEEP" \
     -Worktree "<run root path>" -Since "<the run's started_at>"
   ```

   The path is resolved at run time on purpose: the plugin cache directory
   carries a commit sha that changes on every `claude plugin marketplace
   update`, so a literal path written into this file would go stale. An
   empty `$SWEEP` means the plugin is not installed → skip the sweep and
   say so in the report. Otherwise list what it killed. Then delete the
   run's `.claude/execute-change-run.json` and
   `.claude/execute-change-run.jsonl` from the session's project root,
   where check 6 wrote them — the run is over, and removing the metadata
   file is what makes the hooks inert again.
4. **STOP.** Report to the user: verdicts per step, decisions taken, the
   commit list, leftover processes killed, the run root, and the
   remaining manual steps verbatim:
   deploy to the dev environment and smoke-test, update the work-folder
   CLAUDE.md files, delete the plan brief, the ledger, and the reports
   folder, `opsx:archive` the change, and open the PR. One more manual step follows the PR when
   the run had its own worktree: remove it with
   `git worktree remove <path>`. When check 6 reused the current
   checkout there is no worktree — leave that step out rather than
   telling the user to remove a directory that does not exist.

## Pause-and-notify rules (apply at every step)

- A subagent report (the file at its `{{REPORT_PATH}}`, not the returned
  summary) containing open questions or forks → batch them into
  one pause for that step (a single AskUserQuestion; consecutive calls in
  the same pause when there are more than 4 forks), update the ledger, and
  wait. With Remote Control on, the question pushes to the phone, waits
  indefinitely, and survives machine sleep.
- An unexpected permission prompt behaves the same way — waits and
  notifies. This is why the skill does not demand `bypassPermissions`;
  `references/preflight.md` documents the recommended per-repo allowlist
  and `acceptEdits` mode so routine commands don't prompt.
- API or transport death (an Agent tool error or a synthetic last
  message such as "529 Overloaded" or "Internal server error", with no
  report file at the subagent's `{{REPORT_PATH}}`; an existing report
  file, whatever its contents, means the subagent finished and the
  acceptance check judges it) → one automatic relaunch: with the death-relaunch
  wrapper from `references/step-prompts.md` when the subagent's progress
  file (`<report label>.progress.md` in the reports folder) exists and is
  non-empty, with the plain template when it does not. A second death of the same
  subagent → pause and ask. The relaunch does not consume the
  acceptance-check retry; it shares its budget with the stall ladder's
  relaunch (one per subagent per step, per subagent in a parallel set).
- Hard failure (a subagent's skill refuses to run — not a death) → pause
  and ask, never guess forward. Soft failure (a "done" claim that fails
  your acceptance check) → one retry with the failure fed back, then
  pause and ask.

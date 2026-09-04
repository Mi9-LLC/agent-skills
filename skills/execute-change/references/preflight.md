# Preflight detail — the Step 0 checks and one-time machine setup

Read this file at Step 0. The first five sections are the Step 0 checks, in
the order SKILL.md runs them; the last section is one-time machine setup the
skill only points the user at — it never configures any of it itself.

## Resume (check 2)

Read this section when SKILL.md check 2 finds the brief's ledger already
on disk. Re-read the recorded branch, run root, run-root option, route,
change ID, base branch, start commit, and last completed step; what
happens next depends on which option the ledger records.

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
   hook's own sweep replay and SKILL.md's stall watcher — treat a
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

## OpenSpec: detect, install, update

**Detection.** `openspec/config.yaml` at the repo root is the positive
signal. If it is absent, the repo may still be OpenSpec-managed through a
store (a shared spec location outside the repo), so ask the CLI:

```bash
openspec context
```

Current OpenSpec CLIs fail loudly when run outside a managed root — exit
code 1, with `Error: No OpenSpec root found from the current directory.`
on stderr (verified on 1.9.0 and again on 1.11.0). Ordering caveat: this
check needs the CLI — if `openspec` is not installed and `config.yaml` is
absent, run the install path below first, then come back; a "command not
found" failure must never be read as "not an OpenSpec repo".

**Non-zero exit → ask the user, do not just stop.** This skill only works
where the `opsx:` command set does, so the run cannot proceed as it
stands — but ending on a printed explanation is how a user misses that
the run stopped at all. This is a blocking AskUserQuestion, and the run
waits on the answer:

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

**Initialize (the user chose to make the repo managed).** Do the version
check FIRST, not after. `openspec init` writes the repo's instruction and
command files, so an outdated CLI puts outdated files into a brand-new
root, and nothing later in the run corrects them. Run the version
comparison from "Update (CLI outdated)" below and take its update path if
the local CLI is behind, then:

```bash
openspec init --tools claude
```

- **`--tools claude` is required, not cosmetic.** Without it, `init`
  prompts for the tool list. An unattended run then hangs on a prompt
  nobody is watching. `--tools` accepts `all`, `none`, or a
  comma-separated list; `claude` is the one this skill needs.
- **Do not pass `--force` by default.** It is documented as "auto-cleanup
  legacy files without prompting", so it deletes without asking. If
  `init` stops on a legacy-file question, that is a real user decision —
  pause and ask rather than forcing past it.
- `--no-animation` replaces the animated welcome screen with a static
  one, which is the better choice when the output is being read by the
  lead rather than a person.
- `init` creates `.claude/commands/opsx/`, so the session-restart rule
  under "Update" applies here too: commands and skills are scanned at
  session start.
- Confirm the result with `openspec context` before continuing. A zero
  exit means the root resolves; anything else means initialization did
  not take, and that is a stop-and-ask, not something to retry blindly.

**Install (CLI missing).** `openspec --version` errors → the CLI is not
installed. Ask the user (AskUserQuestion) before touching their machine.
On yes:

```bash
npm install -g @fission-ai/openspec@latest
openspec update        # run inside the repo — regenerates the opsx commands/skills
```

**Update (CLI outdated).** Compare versions:

```bash
openspec --version                        # installed — prints the bare version, e.g. 1.9.0
npm view @fission-ai/openspec version     # latest on npm
```

Installed < latest (compare the two version strings numerically, not as
text) → ask the user; on yes, run the same two commands as the install
path.

**The trap this ordering exists for:** an outdated CLI silently reports
"up to date" from `openspec update` — that command refreshes the repo's
generated files from the *installed* CLI, it does not upgrade the CLI. The
version comparison is therefore always against `npm view`, never against
`openspec update`'s output.

**Session-restart warning.** If `openspec update` regenerated
`.claude/commands/opsx/` or `.claude/skills/openspec-*` files, the running
session may not see the new versions: commands and skills are scanned at
session start. Tell the user, and ask whether to restart the session before
executing (recommended — the run depends on the `opsx:` flows being current)
or continue with the current one.

## Companion skills

The pipeline invokes two catalog skills inside subagents:

| Skill | Used at | Check |
|---|---|---|
| `plan-eng-review` | Step 2 (and the step-5 re-run) | Present under the repo's `.claude/skills/` or the user-level `~/.claude/skills/` |
| `verify-implementation` | Step 7 | Same |

If either of these two is missing, ask the user (AskUserQuestion) whether
to install it:

```bash
npx skills add https://github.com/Mi9-LLC/agent-skills --skill plan-eng-review
npx skills add https://github.com/Mi9-LLC/agent-skills --skill verify-implementation
```

Newly installed skills carry the same session-restart warning as an
OpenSpec update: they are scanned at session start, so recommend a restart
before executing.

The pipeline also invokes the repo's own OpenSpec flows — the propose
flow at step 1 and the update flow at step 4. Their generated skill names
vary by CLI version (e.g. `openspec-propose` vs `openspec-propose-change`)
— confirm a propose and an update skill exist among the
`.claude/skills/openspec-*` files (or `.claude/commands/opsx/`); if
missing, `openspec update` regenerates them — not `npx skills add` — with
the same session-restart warning as above.

## Run root notes

The **run root** is the directory the run works in, and SKILL.md check 6
asks the user which directory that is: the current checkout (reusing its
branch, or with a new branch created there), or a dedicated git worktree
the check creates. The recommended answer is the current checkout; the
worktree is what buys concurrency and an untouched main tree, and check 6
states that trade-off in the question. Check 6a's route question (full or
light) is asked in the same AskUserQuestion call as the run-root question,
so Step 0 has one pause and not two.

### The question check 6 asks

Three options, asked as one blocking AskUserQuestion before anything is
created. Read the two facts the question needs first: the branch checked
out right now (`git rev-parse --abbrev-ref HEAD`) and whether the tree is
dirty (`git status --porcelain`).

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

### The start commit

Recorded once the run root exists (`git rev-parse HEAD` in the run root,
the full sha) and never recomputed. It is the diff base for steps 7 and 8.
Every commit the run makes is a descendant of it under all three options,
which is what makes it a scope the base branch cannot give: under the first option the base branch
IS the branch the run commits on, so a base-branch diff is empty, and under
a reused feature branch it also carries whatever the user committed before
the run started.

### The metadata file

Whichever option was taken, the main tree keeps the ledger and, on a
design-first run, the brief; under the worktree option those two — together
with the metadata file and the heartbeat log — are the run's writes outside
the run root. The metadata file, `.claude/execute-change-run.json`, is
written in **the directory this session was started in** — the main repo
checkout — and not in the run root: the hooks start from the payload's
`cwd` — the Bash tool's current directory, which a `cd` can leave inside a
subdirectory — and walk up to the nearest directory holding the metadata
file, and the session's project root is the one directory every such walk
from inside the project reaches. Under the two reuse-checkout options the
session's directory and the run root are the same directory anyway, so this
is one fixed location in all three cases, not worktree-only special-casing.
The `run_root` field inside the file is what points at the actual run root:

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

The `ledger` path is the file check 8 will create: `<plan path>.ledger.md`
is deterministic from the brief path, so writing it before check 8 runs is
safe. This file is what the three `execute-change` hooks read — it is
written at check 6, rewritten only by a resume to carry the new session's
id, and deleted at close-out.

### Per-option consequences

**When the run root is the current checkout:**

- Dependencies are already installed and build caches are warm, so the
  background baseline run is usually just the gates. Run the install there
  only if the gates fail for missing ones — a reinstall in the user's own
  directory is a change they did not ask for.
- No `git worktree add`, `remove`, or `prune` runs at any point, and
  close-out has no worktree-removal step.
- One run at a time on this repo. Nothing enforces that, so two
  simultaneous runs of different plans in one checkout would edit each
  other's files; a worktree is what makes concurrent runs safe.
- The user cannot work in the repo while the run executes, and a
  pre-existing dirty tree is judged by every gate run — check 6 surfaces
  both before the answer is given.

**When the run root is a dedicated worktree:**

- **Per-run setup cost.** A fresh worktree has no installed dependencies —
  run the project's install step (e.g. `npm ci`) there before the gates
  can pass, and expect cold build caches on the first gate run.
- **Git is the concurrency guard.** A branch can only be checked out in
  one worktree; two runs can never collide on a branch even by mistake.
  Two runs of the *same* plan are prevented by the resume check instead —
  the second session finds the ledger and resumes rather than recreating.
- **Removal is manual.** The worktree outlives the run on purpose (the PR
  is opened from its branch); `git worktree remove <path>` is the last
  manual close-out step, and `git worktree list` shows anything left over.

## Route (check 6a)

SKILL.md check 6a asks the route as the second question of check 6's
AskUserQuestion call. Answer these six signals from the brief's own text —
its file table, its order section, its headings — and print each answer in
the question together with the brief line it comes from. A brief that does
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

## One-time machine setup (documented only — the skill never configures this)

The run pauses on human decisions and waits indefinitely; this setup is what
turns "waiting in a terminal you aren't looking at" into "a push
notification on your phone you can answer from anywhere". The skill does not
ask the user to confirm it — the answer would change nothing the run does.
Step 0 prints the notification state instead, read from `~/.claude.json`:
`agentPushNotifEnabled` (the "Push when actions required" setting) and
`hasUsedRemoteControl`. Either one false or absent → the readiness line
says plainly that pauses will wait in this terminal only. Neither file flag
records the per-session `/remote-control` toggle, so a printed notice is as
far as detection goes, not a claim that the phone push is confirmed working.

### Remote Control + phone push

1. **Enable Remote Control.** Type `/remote-control` in the session
   (research-preview feature; works on Pro/Max accounts signed in with
   claude.ai). For every future session instead: `/config` → turn on
   **"Enable Remote Control for all sessions"**.
2. **Connect the phone.** Install the Claude app (iOS/Android), sign in
   with the same claude.ai account, open the **Code** tab — the running
   session appears in the list. Accept the notification permission.
3. **Enable the push.** In the terminal's `/config`, turn on **"Push when
   actions required"** — a waiting question or permission prompt then sends
   a push to the phone. AskUserQuestion prompts (including multi-select)
   render in the app and can be answered from there while execution stays
   on the local machine (verified live 2026-08-13).

A question or permission prompt in an interactive session waits with no
timeout, and the session survives machine sleep (nothing executes while the
machine sleeps; the wait itself costs nothing). The machine must be on and
awake while steps execute.

### Permission mode and allowlist

Do **not** run with `bypassPermissions` — an unexpected permission prompt
pausing the run and notifying the phone is a feature of this design, not a
defect. The recommended setup for an unattended run:

- **`acceptEdits` mode** for the session, so file edits by implementer
  subagents don't prompt.
- **A per-repo allowlist** in `.claude/settings.json` (or
  `settings.local.json`) covering the exact commands the routine uses, so
  the routine ones never prompt. Typical entries: the repo's own quality
  gates (build / typecheck / lint / test commands), `git status`,
  `git add`, `git commit`, `git worktree` (needed only when check 6
  creates a worktree), `git diff`, `git log`,
  `openspec`, and `bash <Skill dir>/scripts/stall-watcher.sh` (the stall
  watcher, armed after every subagent launch) — and nothing broader. Anything outside the list still
  prompts, which pauses and notifies: exactly the intended behavior.

### Run hooks (shipped with the `execute-change` plugin)

Three hooks ship in the plugin entry `execute-change@mi9-agent-skills`,
declared inline in that entry in `.claude-plugin/marketplace.json`. They are
inline because a marketplace entry does not accept a hooks file path, and
because both entries in this repo share the repo root as their plugin root,
so a `hooks/hooks.json` sitting there would load into both plugins. The
scripts themselves — `hooks/execute-change-watch.py` and
`hooks/sweep-worktree-processes.ps1` — are unchanged and still referenced by
name. `npx skills add` installs skill files only, so these arrive with the
plugin or not at all:

| Hook event | What it does |
|---|---|
| `SubagentStart` | Appends a `start` line to `<session project root>/.claude/execute-change-run.jsonl` |
| `SubagentStop` | Appends a `stop` line (agent id, `agent_transcript_path`, `stop_hook_active`); when replaying the log shows no subagent still running and the platform is Windows, also runs the process sweep |
| `Notification` | Appends a `notify` line — permission prompts, agent-needs-input, idle |

**Where the run-state files live.** Both `execute-change-run.json` and
`execute-change-run.jsonl` are written under `.claude/` in the **directory the
session was started in** — the main repo checkout — and not in the run root.
The hooks start from the payload's `cwd` and walk up to the nearest directory
holding the metadata file. That `cwd` is the Bash tool's current directory,
not the session's project root: a `cd` into a subdirectory of the project
persists between commands, while Claude Code resets the directory only when a
command leaves the project. A worktree lives outside the project, so a
metadata file written inside the worktree was never found and every hook
stayed inert. Under the two reuse-checkout options the project root and the
run root are the same directory, so nothing changes there. The `run_root`
field inside the metadata file is what points at the actual run root.

Before 2026-09-01 the hook read `<cwd>/.claude/execute-change-run.json`
literally, with no walk up. Reproduced that day: a subagent launched while the
shell sat in a subdirectory of the project produced no `start` and no `stop`
line at all; in the live run that day, 4 of 8 `SubagentStart` events were
missing, each after a command that had changed into a package directory, and
their `SubagentStop` events were logged only because a later command had reset
the directory. The walk up fixes that for any directory inside the project. It
does not reach a metadata file from a directory outside the project, so **do
not start the lead session with the run's worktree passed as an additional
working directory** (`--add-dir`): a `cd` into it is not reset, and no walk up
from there finds the session's project root. And the lead never leaves the
shell in another directory in any case — `(cd <dir> && <command>)`, `git -C`,
`pnpm -C` / `--filter`, `dotnet <verb> <path>` — because an installed copy of
the older hook keeps the defect until the plugin is updated.

All three fire in the **parent (lead) session**, not inside the subagent, so
one script wired to all three sees the whole run from one place. The JSONL
log is what the lead's stall watcher reads (SKILL.md, "Heartbeat and stall
handling"). Every append is one short write of one JSON object and nothing
shares a mutable document, so parallel step-6 groups cannot corrupt each
other's writes. A `stop` line says nothing about whether the subagent
succeeded — `SubagentStop` has no such field — but its
`agent_transcript_path` is where that subagent's transcript can be read,
which is the fastest way to see what a failed or stalled one actually did.

Install:

```bash
claude plugin marketplace add Mi9-LLC/agent-skills
claude plugin install execute-change@mi9-agent-skills
```

**A run works without them, degraded:** there is no heartbeat log to watch
and no automatic process sweep, so a stalled subagent is caught only by the
pause rules in SKILL.md's ground rules 2 and 3, and leftover processes
survive in the run root until the close-out sweep is run by hand.

**Pass-through rule.** The hooks are installed per machine, so they run in
every session, including every session that has nothing to do with this
skill. They do nothing at all unless
`<session project root>/.claude/execute-change-run.json` exists AND names the
current `session_id`; absent, unreadable, malformed, or another session's run
file all mean the same thing — write nothing and return. This is the same
inert-when-not-a-run rule the optional `Stop` hook below needs.

**Always exit 0.** Exit code 2 on `SubagentStop` tells Claude Code to block
the subagent from stopping and hand it the hook's stderr, which is the
opposite of what a watchdog should do. A watchdog that can wedge the run it
is watching is worse than no watchdog, so every path — malformed payload,
unreadable log, crashed sweep — returns normally.

**The sweep** (`hooks/sweep-worktree-processes.ps1`; Windows only;
parameters `-Worktree <path>`, `-Since <ISO timestamp>`, `-WhatIf`) kills a
process only when all three of these hold. The `-Worktree` parameter keeps
its name; the path passed to it is the run root, which is a worktree only
when check 6 created one:

1. its command line contains the run root path — matched in both the
   Windows and the Git Bash form, and only when the match ends on a path
   boundary, so a sibling directory whose name merely starts with the run
   root (`C:\Develop\Foo` against `C:\Develop\Foo.worktrees\...`) is never
   selected — OR it descends from the
   current `claude` process through the `ParentProcessId` chain. The path is
   matched in **both** forms it can appear in: the Windows form
   (`C:\Temp\...`, compared case-insensitively with `/` and `\` treated
   alike) and the Git Bash form (`/c/temp/...`). The second form is there
   because the lead drives the run through the Bash tool, which is Git Bash,
   so the POSIX form is the common case rather than the exotic one;
2. it started at or after `-Since`, so nothing older than that timestamp is
   ever touched. The value differs by caller. The automatic sweep passes
   the start of the batch of subagents that just finished — the moment the
   running set last went from empty to non-empty — so a process that
   predates that batch is never a candidate. The case that matters is Step
   0's background dependency install and baseline gate run: it is a
   descendant of `claude`, it runs allowlisted executables (`npm`, `node`),
   and it is still working while steps 1–5 run their subagents, so
   a sweep armed with the run's start time would kill it mid-flight. The
   close-out sweep does pass the run's `started_at`, which is correct
   there because every subagent has finished by then;
3. its executable name is in the fixed allowlist: `node`, `npm`, `npx`,
   `pnpm`, `yarn`, `bun`, `biome`, `eslint`, `tsc`, `vitest`, `jest`,
   `esbuild`, `dotnet` — thirteen entries, and **no shells**. `bash`, `sh`,
   and `pwsh` are deliberately absent: every leftover the sweep exists for is
   a node or dotnet process, while a shell is far more often the lead's own
   tooling, including the stall watcher.

The lead's own gate run passes all three tests. It descends from `claude`,
it starts after the batch began, and it runs `node` or `dotnet`; under the
two reuse-the-checkout options of check 6 it also names the run root on
its command line. On 2026-09-01 the sweep killed two lead gate runs in one
session, each 2 to 3 seconds after a subagent stopped, and each looked
like a real failure (`[ELIFECYCLE] Command failed with exit code 1`, no
failing test). The hook itself is unchanged; the fix is procedural, in
SKILL.md Step 6: the lead moves `.claude/execute-change-run.json` to
`.json.parked` before every gate run it starts and moves it back after the
run ends, which makes every hook pass through for that window. A missed
`SubagentStart` event (4 of 8 launches that day, caused by the hook reading
the shell's directory instead of the project root — fixed by the walk up
described above) makes this more likely, not less: with a `start` missing,
the running set is empty at every `stop`, so the sweep fires on every stop
instead of once per batch.

It kills with `taskkill /PID <n> /T /F` and prints one summary line per
kill; `-WhatIf` lists the matches without killing any of them. On a
non-Windows platform it exits 0 with a note and kills nothing.

**Two known blind spots.** Each one leaves rule 1 with nothing but the
command line to work with:

- A process started as `node script.js` with its working directory set to
  the run root carries no path at all on its command line, so only the
  parent-chain rule can reach it. `Win32_Process` exposes no
  working-directory field, so there is no cheap way to close that gap.
- A process orphaned by its launching shell — started with `&` or `nohup`,
  the shell then exited — has a dead `ParentProcessId`, and Windows does not
  reparent orphans onto a live process, so the parent chain cannot reach it
  at all.

In both cases the process is caught only when its command line happens to
carry the run root path in one of the two forms rule 1 matches.

**When the run root is the user's own checkout, the sweep can reach the
user's own processes.** A dev server or test watcher they started in that
directory after the run's `-Since` timestamp, running one of the
allowlisted executables, matches all three conditions. Nothing older than
`-Since` is ever touched, which is what keeps this narrow — but list what
the close-out sweep killed, and run it with `-WhatIf` first when the user
is still working in that directory.

### Still optional (for users who want them — never configured by this skill)

- **Notification hook — a Windows alert when the run is waiting.** A
  Notification hook fires when Claude Code waits for input (an open
  question, a permission prompt, a background agent needing input). On
  Windows the standard pattern is a small PowerShell alert; note the
  documented caveat that the dialog can open behind the terminal window —
  test it once before relying on it.
- **Stop hook gated on the ledger.** A Stop hook fires when the session
  tries to end its turn and can block the stop. Gating it on the run's
  ledger file ("last completed step" not yet at close-out and no
  open-question wait recorded → refuse the stop) turns "the lead should not
  stop early" from discipline into enforcement. This is strictly optional:
  the hook outlives the run and fires on every session in the repo, so it
  must be written to pass through when no ledger is present.

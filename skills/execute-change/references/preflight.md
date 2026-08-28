# Preflight detail — OpenSpec, companion skills, and one-time machine setup

Read this file at Step 0. The first two sections are checks the skill runs
every time; the last section is one-time machine setup the skill only points
the user at — it never configures any of it itself.

## OpenSpec: detect, install, update

**Detection.** `openspec/config.yaml` at the repo root is the positive
signal. If it is absent, the repo may still be OpenSpec-managed through a
store (a shared spec location outside the repo), so ask the CLI:

```bash
openspec context
```

Current OpenSpec CLIs (verified on 1.9.0) fail loudly (non-zero exit) when
run outside a managed root. Non-zero exit → the repo is not
OpenSpec-managed → stop the run and explain; this skill only works where
the `opsx:` command set does. Ordering caveat: this check needs the CLI —
if `openspec` is not installed and `config.yaml` is absent, run the
install path below first, then come back; a "command not found" failure
must never be read as "not an OpenSpec repo".

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

## Worktree notes

Each run creates its own git worktree (SKILL.md check 6 has the command),
so several runs with different plans can execute on one repo at once. Three
practical points:

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

## One-time machine setup (documented only — the skill never configures this)

The run pauses on human decisions and waits indefinitely; this setup is what
turns "waiting in a terminal you aren't looking at" into "a push
notification on your phone you can answer from anywhere". The skill does not
ask the user to confirm it — the answer would change nothing the run does.
Step 0 prints the notification state instead, read from `~/.claude.json`:
`agentPushNotifEnabled` (the "Push when actions required" setting) and
`hasUsedRemoteControl`. Neither file flag records the per-session
`/remote-control` toggle, so a printed notice is as far as detection goes.

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
  `git add`, `git commit`, `git worktree`, `git diff`, `git log`,
  `openspec` — and nothing broader. Anything outside the list still
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
| `SubagentStart` | Appends a `start` line to `<worktree>/.claude/execute-change-run.jsonl` |
| `SubagentStop` | Appends a `stop` line (agent id, `agent_transcript_path`, `stop_hook_active`); when replaying the log shows no subagent still running and the platform is Windows, also runs the process sweep |
| `Notification` | Appends a `notify` line — permission prompts, agent-needs-input, idle |

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
pause-and-notify rules at the end of SKILL.md, and leftover processes
survive in the worktree until the close-out sweep is run by hand.

**Pass-through rule.** The hooks are installed per machine, so they run in
every session, including every session that has nothing to do with this
skill. They do nothing at all unless `<cwd>/.claude/execute-change-run.json`
exists AND names the current `session_id`; absent, unreadable, malformed, or
another session's run file all mean the same thing — write nothing and
return. This is the same inert-when-not-a-run rule the optional `Stop` hook
below needs.

**Always exit 0.** Exit code 2 on `SubagentStop` tells Claude Code to block
the subagent from stopping and hand it the hook's stderr, which is the
opposite of what a watchdog should do. A watchdog that can wedge the run it
is watching is worse than no watchdog, so every path — malformed payload,
unreadable log, crashed sweep — returns normally.

**The sweep** (`hooks/sweep-worktree-processes.ps1`; Windows only;
parameters `-Worktree <path>`, `-Since <ISO timestamp>`, `-WhatIf`) kills a
process only when all three of these hold:

1. its command line contains the worktree path, OR it descends from the
   current `claude` process through the `ParentProcessId` chain;
2. it started at or after `-Since`, so nothing older than that timestamp is
   ever touched. The value differs by caller. The automatic sweep passes
   the start of the batch of subagents that just finished — the moment the
   running set last went from empty to non-empty — so a process that
   predates that batch is never a candidate. The case that matters is Step
   0's background dependency install and baseline gate run: it is a
   descendant of `claude`, it runs allowlisted executables (`bash`, `npm`,
   `node`), and it is still working while steps 1–5 run their subagents, so
   a sweep armed with the run's start time would kill it mid-flight. The
   close-out sweep does pass the run's `started_at`, which is correct
   there because every subagent has finished by then;
3. its executable name is in the fixed allowlist: `node`, `npm`, `npx`,
   `pnpm`, `yarn`, `bun`, `biome`, `eslint`, `tsc`, `vitest`, `jest`,
   `esbuild`, `dotnet`, `bash`, `sh`, `pwsh`.

It kills with `taskkill /PID <n> /T /F` and prints one summary line per
kill; `-WhatIf` lists the matches without killing any of them. On a
non-Windows platform it exits 0 with a note and kills nothing.

**Known blind spot.** A process started as `node script.js` with its
working directory set to the worktree carries no worktree path on its
command line, so only the parent-chain rule catches it. `Win32_Process`
exposes no working-directory field, so there is no cheap way to close that
gap.

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

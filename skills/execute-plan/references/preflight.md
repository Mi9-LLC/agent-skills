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

The pipeline also invokes the repo's own OpenSpec flows —
`openspec-propose-change` at step 1 and `openspec-update-change` at
step 4. Confirm they exist (`.claude/commands/opsx/` or
`.claude/skills/openspec-*` files); if they are missing, `openspec update`
regenerates them — not `npx skills add` — with the same session-restart
warning as above.

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
notification on your phone you can answer from anywhere". Walk the user
through confirming it at Step 0's readiness question — none of it is
programmatically detectable, which is why the question exists.

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

### Optional hooks (for users who want them — never configured by this skill)

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

---
name: dead-code-removal
description: >-
  Re-check a dated dead-code analysis and its removal plan against today's code with
  read-only subagents, record new verdicts (VALID, CHANGED, INVALID, GONE) in the plan and a new
  re-check file, and, once the user approves, delete statically proven dead code step by step in
  a git worktree, running the gates after each step and committing only on approval. Use it when
  a dead-code report, unused-code list, or removal plan already exists and the user wants it
  re-checked or acted on - "re-check the dead code analysis",
  "update the code validity of the dead-code report", "is this dead-code list still accurate",
  "the analysis is a week old, check it and start removing", "execute the dead-code removal
  plan", "start Step 1 of the dead code plan in a worktree". Do NOT use it to find dead code from
  scratch (write the analysis first, or run the health skill's dead-code gate); to delete one file
  or symbol the user names; for static-analyser smells (sonar-issue-fix); or for code only runtime
  evidence could prove unused.
model: claude-opus-5
---

# Re-checking a dead-code analysis and removing what it proves

A dead-code analysis starts to go stale the moment it is written. Other commits move lines, add
callers and delete files. Worse, some findings were wrong on the day they were written, in files
that have not changed since. So a re-check that only asks "did this file change?" passes exactly
the findings that are most dangerous to act on. This skill re-proves every finding from scratch,
records the result, and only then deletes code.

In the first live run (2026-09-24, a TypeScript monorepo, 6 days and 14 commits after the
analysis), 5 re-check agents checked about 245 items: 11 were INVALID or GONE and 29 had CHANGED.
At least 4 of the INVALID items sat in files that no commit had touched since the analysis.

## Hard rules

1. **The re-check is read-only.** Re-check agents write only their own report file, outside the
   repository: in the session scratchpad directory, or in a temp folder outside the repository
   when the harness has no scratchpad.
2. **Code changes happen only in a dedicated git worktree**, never in the user's own checkout.
   Another session may be working there, and its commits must not mix with these.
3. **No commit and no push without the user's approval.** Propose the commit message, list the
   staged files, and wait. Stage only the files of the current step, each by its explicit path;
   never `git add -A` or `git add .`, because the worktree can hold files that are not part of
   the step. Never run those two commands in any form, a dry run (`-n`) included; list changes
   with `git status --short`.
4. **Delete on static proof only.** An item whose deadness depends on configuration, deploy
   settings or traffic stays in place, whatever the analysis recommends. Deciding those needs
   runtime evidence, which this skill does not collect.
5. **A defect found on the way is reported, never deleted.** A branch that never runs because of
   a bug (a dependency nobody injects, a plugin nobody registers) is a bug to fix. Deleting it
   hides the bug. The same holds for state that is written but never read (a store that
   production code writes and only tests read): removing it edits a live code path, so record it
   as a follow-up instead of deleting it in a deletion step.
6. **When a gate fails after a step, revert that step and report it.** Do not fix forward. A
   failure means the step's premise was wrong: record the item and the failure, skip the step,
   and continue with the next one. The item appears under Skipped in the final report. The one
   exception is the import-order auto-fix described in Step 5, item 5, and only when the user
   approved it in Step 2b.

## What is in this skill

These files live in the installed skill directory (`${CLAUDE_SKILL_DIR}`, printed when the skill
loads), not in the repository being cleaned.

- `references/recheck-brief.md`: the prompt for each re-check agent, with its output format and
  heartbeat rule. Read it in Step 2.
- `references/false-positives.md`: the checklist every re-check agent clears before it calls an
  item VALID. Read it in Step 2 and again before each deletion in Step 5.

## Inputs

- The analysis: a folder or a file of findings, each with a location and the evidence for it.
- The plan: the document that turns findings into ordered deletion steps. It may be the same file.
- If there is no analysis at all, stop and say so. This skill checks and executes an analysis; it
  does not produce one.

Find both from the user's message, or search `docs/` for "dead code", "dead-code" and "unused".
If more than one candidate exists, ask which one.

## Step 0 — Preflight

Read, before anything else:

1. The repository's `CLAUDE.md` (and any file it imports): the quality gates and their order, the
   base branch for pull requests, the branch-name rule (ticket IDs), the changelog rule, and any
   rule files about the subsystems the plan touches.
2. The analysis and the plan, end to end. Record:
   - the commit the analysis was written at (its header, or `git log --diff-filter=A` on the
     analysis file), and the current head. If neither gives a commit, use the date in the file's
     own header to find the last commit before it, or ask the user;
   - the plan's open questions and every decision it leaves to a person;
   - the plan's own do-not-delete list and its list of defects, if it has them.
3. Whether git tracks each document, with `git ls-files` and `git check-ignore`. A worktree holds
   only the files committed at `<base>`.
   - Untracked but not ignored: Step 1, item 2 copies it into the worktree, and it is committed
     with the Step 3 documents.
   - Tracked, but different from `<base>` (modified, staged, or missing at `<base>`): handled like
     an untracked document. Check this once the base commit question below is answered, with
     `git status --porcelain -- <path>` and `git diff --quiet <base> -- <path>`; any output from
     the first or a non-zero exit from the second means the document differs.
   - Ignored: Step 3 edits it where it is. It is not code, so Hard rule 2 is not broken. The final
     report says it could not be committed.

Then ask for the base commit, before Step 1 creates anything. Use one `AskUserQuestion` call with
the recommended option first: usually the current head of the branch the analysis was written on,
not the default branch, when that branch has changed the code the plan covers. Step 1 creates the
worktree at this commit. Record `git log --oneline <analysis-commit>..<base>` and
`git diff --stat <analysis-commit>..<base>` for the code folders the plan covers.

If the user's message already answers a question (the base commit, the ticket, a decision in the
plan, how far to go), do not ask it again; state the answer used. This holds for the question here
and for the questions in Step 2b, never for the Step 4 approval. Only the user's own words answer
the base-commit question. The repository's state (a single branch, the current HEAD, the branch
the analysis was written on) never does.

If `AskUserQuestion` is not available (for example under `claude -p`) or is denied, ask the
question in the reply and stop there. Never pick the recommended option silently. This holds for
every question the skill asks: here, in Step 2b, in Step 4 and for each commit in Step 5. Here in
Step 0, stopping means making no worktree, no install, no gate run and no agent before the answer
arrives.

## Step 1 — Worktree and baseline

1. Create the worktree **detached at the base commit** from Step 0 so every agent reads one fixed
   commit while other sessions keep committing:
   `git worktree add --detach "../<repo>.worktrees/dead-code-removal-<YYYY-MM-DD>" <base>`, run
   from the repository root. The folder sits beside the repository, not inside it. Use this
   `git worktree add` command, not the harness's own worktree tool (in Claude Code,
   `EnterWorktree`), because that tool puts the worktree inside the repository. If that path
   already exists (an earlier run's worktree is left in place), add a suffix such as `-2`.
   Name the branch later, once the user has given the ticket (Step 2b).
2. Copy into the worktree, at the same path, every document Step 0, item 3 found untracked or
   different from `<base>`: the user's version, from the user's checkout.
3. Install dependencies in the worktree with the project's own command.
4. Run every gate the project defines (format check, lint, typecheck, build, tests) in the worktree
   and save each exit code and log. These are the baseline. From now on, a gate result counts
   only against the baseline: a failure that was already there is reported as pre-existing, never
   blamed on a deletion, and never silently fixed.
   - The baseline can already fail. Run it with the task runner's continue flag (for example
     `--continue` for Turborepo) so that every package reports, not only the ones before the
     first failure, and save the names of the failing tests.
   - Before the first run of any test command, read the scripts it runs and the end-to-end test
     runner's web-server config. A script such as a `predev` that kills processes on a port can
     kill other people's servers. Use the command path that does not run such a script, and never
     run the dev-server script itself.
   - If the end-to-end runner's browser is missing or is the wrong build, tell the user before
     installing one: the installer can delete browser builds that other projects still use.

Run the install and the gates in the background, and start Step 2 at the same time.

## Step 2 — Parallel re-check, and the user's decisions

### 2a. Launch the re-check agents

Split the plan by area: one agent per plan step or per package group, 3 to 6 agents.
Every file belongs to exactly one area agent and every item to exactly one agent, so
two agents never judge the same item differently. Add one extra agent for runtime-gated
suspects, the do-not-delete list and the defect list, if the plan has them; their
claims drift too. Those items belong to the extra agent only: the area agents skip
them, even when they sit in files an area agent owns.

Every agent gets the brief in `references/recheck-brief.md`, filled in, plus the false-positive
checklist in `references/false-positives.md`. Each agent re-proves each claim with a search over
the whole repository, records the current line, and returns one verdict per item:

| Verdict | Meaning |
|---|---|
| VALID | Still unused; the line number may have moved. |
| CHANGED | Still unused, but the location, the name or a detail of the claim is different. |
| INVALID | Something uses it now, or the claim was wrong to begin with. Give the file and line. |
| GONE | Already deleted, or the file the claim names does not exist or is not tracked. |

Each agent also reports three things the original plan usually misses:

- **Cascade items:** code that becomes dead only because this step deletes something else.
- **Test files and documents** that exist only for, or only mention, the deleted code.
- **Test-only items:** code whose only references are tests. Keep them as a separate list; the
  user decides in Step 4 whether a test alone keeps code alive.

### 2b. Ask the user while the agents run

Put every question that blocks code changes into one `AskUserQuestion` call, each with a
recommended option first. Leave out a question the user's message already answers, and ask in
the reply when the tool is missing (see the last two paragraphs of Step 0):

- the ticket ID for the branch name, if the repository's rules need one;
- each open question and each "decide before deleting" item in the plan;
- how far to go in this session (usually: the static-proof steps only);
- whether dead code that the plan does not list is in scope. A good default: delete it in the
  step it belongs to, mark it "added during execution", and re-scan after each step; but keep
  every server API entry point (routes, RPC procedures) even when no client calls it, and list
  those in the final report;
- if the project's lint sorts imports or members by line length: approval in advance for the
  import-order auto-fix in Step 5, item 5.

Name the worktree branch from the answers (`git switch -c <name>` inside the worktree).

### 2c. Keep the agents visible

These rules apply to every agent this skill starts: the re-check agents here, the Step 3 agent,
and any agent that runs a Step 5 deletion step. Start every agent as the general-purpose type,
because it can write its report file and can be resumed with SendMessage. The built-in Explore
agent cannot: Write is denied to it, and it returns no agent ID to resume.

Every agent prompt states its step count and requires one `Step N/M:` line after each step, a line
at least every 3 minutes during a long step, and an immediate return with what it has if a tool
call is denied or a fact contradicts the brief. It also states three rules about how agents run
in Claude Code:

- The agent sends every status line with the messaging tool (SendMessage). Only its final
  result reaches the coordinator; its other plain text output does not.
- The agent never ends its turn to wait for a background command. It checks the command's log
  file on a timer instead. Ending the turn sends the agent's final result to the coordinator
  before its work is done, and for a foreground agent it also stops the command.
- An agent reads incoming messages only between tool calls, so an answer can arrive while it has
  already moved on. So an agent that needs a decision first finishes waiting for any background
  command it started, checking its log on a timer, then sends the question and ends its turn;
  the answer resumes it. An agent that keeps working after it asks runs the gates on the wrong
  state.

Check on running agents on a timer; an agent that has said nothing is not evidence that nothing
happened. When an agent finishes, give the user its counts and every INVALID and GONE item in a
few lines.

## Step 3 — Write the verdicts into the documents

Delegate this to one agent, working in the worktree, with the agents' report files as its input
(a document git ignores is edited where it is; see Step 0, item 3). The agent sees only its
prompt, not this file, so copy items 1 to 3 below into that prompt word for word. Copy this rule
into it too: the agent writes files only, and runs no git command that changes the index, the
branch or the working tree; the lead does all staging and committing.

1. Add a new file next to the analysis, `NN-recheck-<YYYY-MM-DD>.md`: the commit range, the method,
   the counts per area, every INVALID, CHANGED and GONE item with its evidence, the cascade items,
   the missed tests and documents, the test-only items in their own list, any new defects, and
   the per-item tables as an appendix.
2. Edit the plan: a status line with the re-check date and commit; every line number corrected;
   every INVALID item removed or rewritten; cascade items, test files and documents added to the
   step they belong to, each marked as added by the re-check; each test-only item marked as
   waiting for the user's Step 4 decision; the user's answers recorded against the open
   questions. Keep the plan's step numbers: a step the re-check leaves with no items stays
   in the plan, marked empty, and is not removed or renumbered.
3. Add one paragraph and one table row to the analysis index, if it has one. Add nothing to,
   remove nothing from and change nothing inside the original findings, not even a status line
   under a heading. The verdicts and corrections go only in the new re-check file and the plan.

## Step 4 — Show the checked plan and stop

Present the checked deletion steps (use plan mode if the harness has it):

- per step: what is deleted, which barrels, tests and documents change with it, and its gates;
- the items removed from the plan by the re-check, and why;
- the test-only items, for the user's decision: delete each one with its tests, or keep it. Ask
  about each one as a question that needs an answer, in the one question call or in the reply;
  showing it only as a table row is not asking. An item the user does not approve stays in place
  and is listed under Skipped as "test-only and not approved";
- the defects found, each marked "needs its own ticket, not deleted", and the follow-ups (state
  written but never read, Hard rule 5);
- the pre-existing gate failures from the baseline;
- the proposed commit for the Step 3 documents (the new re-check file, the plan, the analysis
  index, and every document Step 1, item 2 copied in; not the documents git ignores): the
  staged file list and the commit message.

If one step holds more than about 50 items, propose splitting it. Wait for approval. The user's
first message cannot give it, because the checked plan did not exist when that message was
written. So stop here whatever that message asks for ("and then execute Step 1" included), and go
on only when the user approves the checked plan after seeing it. Make the
documents commit, once approved, as the first commit of the branch and before Step 5, so that a
revert in Step 5 cannot discard the Step 3 edits; pass its message as Step 5, item 8 says. The
skill stops for the user at four points: the base-commit question in Step 0, the questions in
Step 2b, this approval, and each commit in Step 5 unless the user approved commits in advance.

## Step 5 — Delete, one step at a time

Work in the worktree, one plan step per commit, in the plan's order: whole files first, then
exported symbols, then barrel and type clean-ups, then documents that name deleted code.

For each step:

1. **Re-check each item right before deleting it.** A quick search for its name and its import
   path is enough. The worktree does not move, but earlier steps of this run do. For each file to
   delete that has a look-alike (a file with the same name in another folder, most often a barrel
   `index` file), write the look-alike's path down and prove that nothing imports the file being
   deleted, as false-positive entry 2 describes.
2. Delete the code, then edit every barrel, test file and document that names it, in the same step.
   For a symbol used only inside its own file, remove the `export` keyword and keep the code.
   - **Removed interface members:** test mocks cast through `unknown` (`as unknown as T`) still
     compile when they name a member the interface no longer has. After removing a member,
     search the mocks for its name and remove it there too.
   - **Guards for an optional dependency:** a check such as `if (deps.cache)` is dead only if
     every caller, production code included, passes the dependency. Then make the dependency
     required, give the test setups that omit it one shared mock, and delete the guard and the
     test that pins the guard. If any production caller omits it, the guard is live; if no
     production code ever passes it, that is a defect (Hard rule 5).
   - **Diagrams stored as XML** (for example draw.io files) name code too. Remove the element,
     every connector whose source or target is that element, and their labels. Then parse the
     file and check that no remaining reference points at a removed id.
3. **Re-scan after the step.** A deletion makes more code dead: a type whose only reference was
   the deleted barrel, an import with no use left, translation keys used only by a deleted
   component, a test mock for an endpoint that only a deleted hook called. Add these to this step,
   marked "added during execution", within the scope the user set in Step 2b. Code that was dead
   before this step and that this step's deletions did not affect is not part of it: list it for
   a later pass, so that each step's diff stays reviewable.
4. If the step changed a dependency list, refresh the lockfile, reinstall dependencies in the
   worktree with the project's own command, and include the lockfile in the step.
5. Run the formatter, then every gate, in the project's order. Compare each result to the baseline.
   - **Format only the step's files.** Pass the step's paths to the formatter where it accepts
     them. If it only runs on the whole repository, restore every file outside the step that it
     changed (`git checkout -- <path>`).
   - **Clean before you build.** Run each package's clean script first. A build that does not
     clean its output folder leaves the deleted module's old `.js` and `.d.ts` files in place, so
     the build still passes for code that imports them, and a "not in the output folder" check
     proves nothing. Also check that the compiler's incremental cache (for example
     `*.tsbuildinfo`) cannot make it skip writing files; delete the cache if it can.
   - **Compare failing tests by name,** as a `diff` of the sorted names against the baseline
     list, not by count. A new failure can hide behind a fixed one.
   - **Import order:** a lint rule that sorts imports or members by line length reorders lines
     when a deletion shortens them. If the user approved it in Step 2b, run the lint auto-fix for
     that rule, only in files the step already edits, and check that it changed only the order
     of lines. Any other lint failure is a real failure.
6. If a gate has a new failure: revert the step with
   `git restore --source=HEAD --staged --worktree -- <path>` for each path the step changed,
   deleted, or created and staged, and `git clean -f -- <path>` for each new file the
   step never staged (and reinstall if item 4 refreshed the lockfile), record the item
   and the failure, skip the step, and continue with the next step. The item appears
   under Skipped. Do not fix forward. A later step that depends on the reverted one
   (for example the barrel clean-ups for a reverted whole-file delete) is skipped too,
   with the reverted step named as the reason.
7. Add the changelog entry if the repository's rules require one. If the step removes a
   configuration validation rule (for example a check that compares two config fields) together
   with the config it checks, start-up behaviour can change: a configuration that used to fail
   at start-up may now start. Name that in the changelog entry and in the final report.
8. Show the step's staged file list, the removed test files by name, and the proposed commit
   message. Commit only when the user approves. In a POSIX shell, pass a multi-line commit
   message with `git commit -F -` and a quoted heredoc (`<<'EOF'`); use PowerShell here-string
   syntax (`@'...'@`) only in PowerShell. If the user has approved commits for all steps in
   advance, commit and go on. Do not start the next step while the current step's commit waits
   for approval; if the user wants to look before committing, stop after that step and report.

## Step 6 — Final check and report

Run this step whenever the session's work ends: when every step is done, when the scope the user
set in Step 2b is done, and when every remaining step is blocked.

Before the report, run one check over the whole result:

1. Clean every package, then build and test with the task runner's cache turned off (for example
   `--force` for Turborepo), so that no result comes from a cache.
2. Search the code and the documents for every exported name that was removed and every file that
   was deleted. Classify each hit as allowed, with the reason (a changelog entry, the analysis
   itself, an unrelated symbol with the same name), or not allowed. List every hit that is not
   allowed with its file and line; fixing one is a new change and needs the user's approval
   (Hard rule 3).

Then end with one message that contains:

| Section | Content |
|---|---|
| Removed | Per step: files and symbols deleted (items added during execution marked as such), test files deleted, documents edited, commit hash or "not committed". Also the Step 3 documents commit, and every ignored document edited in place and not committed. |
| Skipped | Every item not deleted, with the reason: INVALID, reverted after a gate failure, depends on a reverted step, test-only and not approved, runtime evidence needed, server API entry point kept, dead before the step and left for a later pass. Each INVALID item gives the file and line that uses it. Each item reverted after a gate failure names the failing test or gate. |
| Behaviour | Every change that is not a pure deletion, such as a removed configuration validation rule that changes start-up behaviour. |
| Gates | Every gate per step and the final check, with pre-existing failures named as such, and every hit from the name search with its classification. |
| Defects | Every defect and follow-up found, with file and line. None of these was deleted. |
| Left | The plan steps not done in this run, and what each one needs. |

An open question for the user goes under Left, together with what it blocks. It never replaces
the report.

Leave the worktree in place. Removing it is the user's decision once the branch is merged.

## Tools that find unused code

If the repository already has an unused-code tool configured (for TypeScript, knip, ts-prune;
for C#, the IDE0051 and IDE0052 analyzers), run it as one more independent check and cite its
output as evidence. If it has none, do not add one or download one without asking: that is a new
dependency. No tool's "zero references" is proof on its own. Tools do not see computed import
paths, string-keyed registries, configuration files or deploy scripts;
`references/false-positives.md` lists what each re-check has to clear.

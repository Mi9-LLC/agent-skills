---
name: dead-code-removal
description: >-
  Take an existing, dated dead-code analysis and its removal plan, re-check every finding against
  the code as it is today with parallel read-only subagents, write the new verdicts (VALID,
  CHANGED, INVALID, GONE) into the analysis and the plan, show the checked plan for approval, and
  then delete the statically proven dead code step by step in a separate git worktree, with the
  project's own gates after every step and no commit until the user approves it. Use it whenever
  a dead-code report, an unused-code list, or a dead-code removal plan already exists and the user
  wants it re-validated, brought up to date, or acted on - "re-check the dead code analysis",
  "update the code validity of the dead-code report", "is this dead-code list still accurate",
  "the analysis is a week old, check it and start removing", "execute the dead-code removal plan",
  "start Step 1 of the dead code plan in a worktree". Do NOT use it to find dead code from scratch
  when no analysis exists (produce the analysis first, or run the health skill's dead-code gate);
  to delete one file or symbol the user names directly; to fix static-analyser smells
  (sonar-issue-fix); or to remove code that only runtime evidence could prove unused - this skill
  deletes on static proof only.
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
   repository.
2. **Code changes happen only in a dedicated git worktree**, never in the user's own checkout.
   Another session may be working there, and its commits must not mix with these.
3. **No commit and no push without the user's approval.** Propose the commit message, list the
   staged files, and wait. Stage only the files of the current step, each by its explicit path;
   never `git add -A` or `git add .`, because the worktree can hold files that are not part of
   the step.
4. **Delete on static proof only.** An item whose deadness depends on configuration, deploy
   settings or traffic stays in place, whatever the analysis recommends. Deciding those needs
   runtime evidence, which this skill does not collect.
5. **A defect found on the way is reported, never deleted.** A branch that never runs because of
   a bug (a dependency nobody injects, a plugin nobody registers) is a bug to fix. Deleting it
   hides the bug. The same holds for state that is written but never read (a store that
   production code writes and only tests read): removing it edits a live code path, so record it
   as a follow-up instead of deleting it in a deletion step.
6. **When a gate fails after a step, revert that step and report it.** Do not fix forward. A
   failure means the step's premise was wrong, and the step goes back to the re-check. The one
   exception is the import-order auto-fix described in Step 5, item 4, and only when the user
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
     analysis file), and the current head;
   - `git log --oneline <analysis-commit>..HEAD` and `git diff --stat <analysis-commit>..HEAD` for
     the code folders the plan covers;
   - the plan's open questions and every decision it leaves to a person;
   - the plan's own do-not-delete list and its list of defects, if it has them.

## Step 1 — Worktree and baseline

1. Create the worktree **detached at the current head** so every agent reads one fixed commit
   while other sessions keep committing:
   `git worktree add --detach "<repo>.worktrees/dead-code-removal" HEAD`.
   Name the branch later, once the user has given the ticket and the base (Step 2).
2. Install dependencies in the worktree with the project's own command.
3. Run every gate the project defines (format check, lint, typecheck, build, tests) in the worktree
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

Split the plan by area: one agent per plan step or per package group, 3 to 6 agents. Every file
belongs to exactly one agent, so two agents never judge the same file differently. Add one extra
agent for runtime-gated suspects, the do-not-delete list and the defect list, if the plan has them;
their claims drift too.

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
  user decides whether a test alone keeps code alive.

### 2b. Ask the user while the agents run

Put every question that blocks code changes into one `AskUserQuestion` call, each with a
recommended option first:

- the ticket ID for the branch name, if the repository's rules need one;
- the base commit: usually the current head of the branch the analysis was written on, not the
  default branch, when that branch has changed the code the plan covers;
- each open question and each "decide before deleting" item in the plan;
- how far to go in this session (usually: the static-proof steps only);
- whether dead code that the plan does not list is in scope. A good default: delete it in the
  step it belongs to, mark it "added during execution", and re-scan after each step; but keep
  every server API entry point (routes, RPC procedures) even when no client calls it, and list
  those in the final report;
- if the project's lint sorts imports or members by line length: approval in advance for the
  import-order auto-fix in Step 5, item 4.

Name the worktree branch from the answers (`git switch -c <name>` inside the worktree).

### 2c. Keep the agents visible

These rules apply to every agent this skill starts: the re-check agents here, the Step 3 agent,
and any agent that runs a Step 5 deletion step.

Every agent prompt states its step count and requires one `Step N/M:` line after each step, a line
at least every 3 minutes during a long step, and an immediate return with what it has if a tool
call is denied or a fact contradicts the brief. It also states three rules that the harness makes
necessary:

- The agent sends every status line with the messaging tool. Its plain text output does not reach
  the coordinator.
- The agent never ends its turn to wait for a background command. It checks the command's log
  file on a timer instead.
- An agent does not read incoming messages while its turn is running. So an agent that needs a
  decision sends the question and then ends its turn; the answer starts it again. An agent that
  keeps working after it asks runs the gates on the wrong state.

Check on running agents on a timer; an agent that has said nothing is not evidence that nothing
happened. When an agent finishes, give the user its counts and every INVALID and GONE item in a
few lines.

## Step 3 — Write the verdicts into the documents

Delegate this to one agent, working in the worktree, with the agents' report files as its input:

1. Add a new file next to the analysis, `NN-recheck-<YYYY-MM-DD>.md`: the commit range, the method,
   the counts per area, every INVALID, CHANGED and GONE item with its evidence, the cascade items,
   the missed tests and documents, any new defects, and the per-item tables as an appendix.
2. Edit the plan: a status line with the re-check date and commit; every line number corrected;
   every INVALID item removed or rewritten; cascade items, test files and documents added to the
   step they belong to, each marked as added by the re-check; the user's answers recorded against
   the open questions.
3. Add one paragraph and one table row to the analysis index, if it has one. Do not rewrite the
   original findings. The original evidence stays as it was; the corrections live in the new file
   and the plan.

## Step 4 — Show the checked plan and stop

Present the checked deletion steps (use plan mode if the harness has it):

- per step: what is deleted, which barrels, tests and documents change with it, and its gates;
- the items removed from the plan by the re-check, and why;
- the defects found, each marked "needs its own ticket, not deleted", and the follow-ups (state
  written but never read, Hard rule 5);
- the pre-existing gate failures from the baseline.

If one step holds more than about 50 items, propose splitting it. Wait for approval. This is the
first of the two places where the skill stops for the user.

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
4. Run the formatter, then every gate, in the project's order. Compare each result to the baseline.
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
5. If a gate has a new failure: revert the step (`git checkout -- .` and `git clean` for that
   step's files only), record the item and the failure, and continue with the next step. Do not
   fix forward.
6. If the step changed a dependency list, refresh the lockfile and include it in the step.
7. Add the changelog entry if the repository's rules require one. If the step removes a
   configuration validation rule (for example a check that compares two config fields) together
   with the config it checks, start-up behaviour can change: a configuration that used to fail
   at start-up may now start. Name that in the changelog entry and in the final report.
8. Show the step's staged file list, the removed test files by name, and the proposed commit
   message. Commit only when the user approves. If the user has approved commits for all steps in
   advance, commit and go on.

## Step 6 — Final check and report

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
| Removed | Per step: files and symbols deleted (items added during execution marked as such), test files deleted, documents edited, commit hash or "not committed". |
| Skipped | Every item not deleted, with the reason: INVALID, reverted after a gate failure, test-only and not approved, runtime evidence needed, server API entry point kept, dead before the step and left for a later pass. |
| Behaviour | Every change that is not a pure deletion, such as a removed configuration validation rule that changes start-up behaviour. |
| Gates | Every gate per step and the final check, with pre-existing failures named as such, and every hit from the name search with its classification. |
| Defects | Every defect and follow-up found, with file and line. None of these was deleted. |
| Left | The plan steps not done in this run, and what each one needs. |

Leave the worktree in place. Removing it is the user's decision once the branch is merged.

## Tools that find unused code

If the repository already has an unused-code tool configured (for TypeScript, knip, ts-prune;
for C#, the IDE0051 and IDE0052 analyzers), run it as one more independent check and cite its
output as evidence. If it has none, do not add one or download one without asking: that is a new
dependency. No tool's "zero references" is proof on its own. Tools do not see computed import
paths, string-keyed registries, configuration files or deploy scripts;
`references/false-positives.md` lists what each re-check has to clear.

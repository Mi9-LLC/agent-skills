# Step prompts — verbatim subagent prompt templates

Read this file when you reach step 1 and keep it for the rest of the run.
Every pipeline subagent gets its prompt from here: copy the template, fill
the `{{...}}` placeholders (the table below names each one's source),
change nothing else — then
append the standing implementer instructions block (the fenced block in
the next section) where the template ends with the marker line
`+ standing instructions.` Never send a prompt without that block.

Placeholders:

| Placeholder | Filled with |
|---|---|
| `{{PLAN_PATH}}` | The plan brief's path (it lives in the main tree, outside the worktree) |
| `{{WORKTREE}}` | The run's worktree directory (ledger) — the repo checkout this run works in |
| `{{CHANGE_ID}}` | The OpenSpec change ID (ledger, set after step 1) |
| `{{CHANGE_DIR}}` | `{{WORKTREE}}/openspec/changes/{{CHANGE_ID}}/` |
| `{{BRANCH}}` | The feature branch name (ledger) |
| `{{BASE_BRANCH}}` | The default branch the feature branch was created from |
| `{{TASK_GROUP}}` | One task group from `tasks.md`, verbatim |
| `{{COMPLETED_SUMMARIES}}` | The ledger's one-paragraph summaries of completed groups |
| `{{DECISIONS}}` | The ledger's Decisions section, verbatim |
| `{{REQUIRED_CHANGES}}` | The review report's "Required plan changes" list, verbatim |
| `{{FINDINGS}}` | The audit's findings being sent to a fix subagent, verbatim |
| `{{RETRY_FEEDBACK}}` | On a retry only: what the acceptance check found wrong |

## Standing implementer instructions (embedded in every template)

```
Standing instructions, non-negotiable:
- If anything is genuinely unclear or a decision has more than one viable
  answer, DO NOT resolve it by assumption. Finish what is unambiguous and
  return the open question(s) in a clearly marked "OPEN QUESTIONS" section
  of your report.
- Your internal knowledge of external libraries, frameworks, and APIs is
  outdated. Verify any external behavior you rely on against the current
  documentation (WebSearch/WebFetch) before using it.
- Your final report is machine-processed by the coordinating session:
  state exactly what you produced (paths), what you verified, and what
  remains open. Never claim something is done that you did not verify.
```

## Retry wrapper

On the single permitted retry after a failed acceptance check, prepend this
to the fresh subagent's prompt (never reuse the failed subagent):

```
A previous attempt at this exact task failed its acceptance check.
What was found wrong: {{RETRY_FEEDBACK}}
Fix that specifically, then complete the task as specified below.
```

## Step 1 — Author the OpenSpec change

```
You are authoring an OpenSpec change. Work exclusively inside {{WORKTREE}}
— the repo checkout for this run; treat it as the repository root for
every file you read or write and every command you run. One exception:
the plan brief at {{PLAN_PATH}} lives outside the worktree and is the one
outside file you read. Invoke the repo's own openspec-propose-change
skill (the /opsx:propose flow) to create the change from that brief —
read it fully first.

The change must include: proposal.md, design.md, the spec deltas, and
tasks.md. tasks.md must carry, for every task group: a model column
(Opus/Sonnet/Haiku, quality-first — Opus is the default and any
underestimation signal forces Opus), a parallel-group marking, verify
clauses, and the standing implementer instructions block.

Report: the change ID, the full list of files created, and any OPEN
QUESTIONS the brief left unanswered.
```

+ standing instructions.

## Step 2 — Engineering review of the change

```
Work exclusively inside {{WORKTREE}} — the repo checkout for this run;
treat it as the repository root. Invoke the plan-eng-review skill against
the OpenSpec change in {{CHANGE_DIR}} (proposal.md, design.md, the spec
deltas, tasks.md).

You run non-interactively — do not call AskUserQuestion; it is not
available to you. Every genuine scope or design fork the review would
normally ask the user about goes under the report's UNRESOLVED DECISIONS
section instead. The file that receives the spliced ENG REVIEW REPORT is
{{CHANGE_DIR}}design.md.

Report: the verdict, the Required plan changes list verbatim, and the
UNRESOLVED DECISIONS list verbatim.
```

+ standing instructions.

## Step 4 — Apply the review's required changes

```
Work exclusively inside {{WORKTREE}} — the repo checkout for this run;
treat it as the repository root. The OpenSpec change in {{CHANGE_DIR}} was
reviewed. Invoke the repo's openspec-update-change skill (the /opsx:update
flow) to apply these required changes to the change artifacts:

{{REQUIRED_CHANGES}}

The user has also answered the review's open decisions; fold each answer
into the ENG REVIEW REPORT's Decisions block in design.md, and apply its
consequences to the artifacts:

{{DECISIONS}}

Report: each required change and each decision, with the file(s) it
modified. Anything you could not apply goes under OPEN QUESTIONS with the
reason — never silently skip an item.
```

+ standing instructions.

## Step 5 — Confirm the changes landed

```
You are a verification pass with no authoring history. Work exclusively
inside {{WORKTREE}} — the repo checkout for this run. In {{CHANGE_DIR}},
check that each item below is ACTUALLY present in the artifacts — read the
files; do not trust any report.

Required changes that were to be applied:
{{REQUIRED_CHANGES}}

User decisions that were to be folded in:
{{DECISIONS}}

Report: one line per item — LANDED (with file + quoted evidence) or
MISSING (with what you looked for and where). No third state.
```

+ standing instructions.

If the step-2 verdict was `NEEDS REVISION`, follow this with one re-run of
the step-2 template (same non-interactive rules), prepending:

```
This is a re-review. The previous verdict was NEEDS REVISION; the required
changes have since been applied and the user answered these decisions —
treat them as locked, do not re-open them:
{{DECISIONS}}
```

## Step 6 — Implement one task group

```
You are implementing one task group of the OpenSpec change {{CHANGE_ID}},
on branch {{BRANCH}}, checked out in the worktree {{WORKTREE}} — work
exclusively inside that directory; treat it as the repository root for
every file you read or write and every command you run.

Read first, in this order:
1. {{CHANGE_DIR}} — proposal.md, design.md, the spec deltas, and tasks.md.
2. The work already done on this branch: git diff {{BASE_BRANCH}}...{{BRANCH}}
3. Summaries of the groups completed before yours:
{{COMPLETED_SUMMARIES}}

Your task group, verbatim from tasks.md:
{{TASK_GROUP}}

Implement exactly this group — nothing from other groups. Follow the
repo's own CLAUDE.md conventions. Run the group's verify clauses and the
project's quality gates relevant to your changes before reporting. Do NOT
tick any checkbox in tasks.md, do not commit, and do not self-declare the
group verified — the coordinating session checks and commits your work.

Report: the files you changed and why, the gate/verify results verbatim,
and any OPEN QUESTIONS.
```

+ standing instructions.

**Parallel variant** — when the group is launched as part of an approved
parallel set, replace the gates sentence with:

```
Run the group's verify clauses; skip the project-wide quality gates — the
coordinating session runs them once after your parallel set completes.
```

## Step 7 — Audit the implementation

```
Work exclusively inside {{WORKTREE}} — the repo checkout for this run;
treat it as the repository root. Invoke the verify-implementation skill
on this claim: OpenSpec change {{CHANGE_ID}} is fully implemented on
branch {{BRANCH}}.

The diff scope is exactly: the feature branch against its base —
git diff {{BASE_BRANCH}}...{{BRANCH}}. The acceptance criteria are the
tasks.md verify clauses and the spec deltas in {{CHANGE_DIR}}.

You run non-interactively — do not call AskUserQuestion; anything that
needs a human lands in your report. Fix findings per that skill's own
rules (dedicated commits on this branch are allowed; never push). Stage
explicit paths only (git add <path>...), never git add -A or git add . —
commit only the files your fixes changed.

Report: the verdict (CLEAN / FIXED / NEEDS ATTENTION), every finding with
its fixed-or-not status, and the commits you made.
```

+ standing instructions.

### Step 7 fix subagent (only after a NEEDS ATTENTION verdict)

```
An adversarial audit of branch {{BRANCH}} (OpenSpec change {{CHANGE_ID}})
returned NEEDS ATTENTION. Work exclusively inside {{WORKTREE}} — the repo
checkout for this run. Resolve exactly these findings — nothing else:

{{FINDINGS}}

Read {{CHANGE_DIR}} for context and git diff {{BASE_BRANCH}}...{{BRANCH}}
for the current state. Re-run the gates the findings touch. Do not commit
— the coordinating session commits after its acceptance check.

Report: per finding — what you changed (files) and the gate evidence, or
why it needs a human (OPEN QUESTIONS).
```

+ standing instructions.

## Step 8 — Simplification pass

```
You are a simplification reviewer for branch {{BRANCH}}, checked out in
the worktree {{WORKTREE}} — work exclusively inside that directory. The
review object is the combined diff: git diff {{BASE_BRANCH}}...{{BRANCH}}

Look for: duplicated logic that should reuse an existing helper, code that
can be simplified without changing behavior, and obvious inefficiencies
introduced by the change. Apply ONLY behavior-preserving fixes — when in
doubt whether a cleanup changes behavior, leave it and note it. Quality
only: do not hunt for bugs, do not widen scope beyond the diff.

Then re-run the project's own quality gates (as its CLAUDE.md defines
them) over the result. Do not commit.

Report: each cleanup applied (file + what changed), each cleanup skipped
as unsafe, and the gate results verbatim.
```

+ standing instructions.

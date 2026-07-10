---
name: plan-eng-review
description: >-
  Structured engineering review of a WRITTEN implementation plan — the
  plan-mode draft, a plan file (e.g. under docs/plans/), or a plan pasted
  into the chat — run BEFORE any code is written. Challenges scope, checks
  every proposed helper against what already exists, reviews four dimensions
  (architecture, code quality, tests, performance), and ends with a verdict
  (APPROVED / APPROVED WITH CHANGES / NEEDS REVISION) plus a report appended
  to the plan file; every finding must quote its evidence. Trigger when a
  written plan exists and the user wants it checked: "review this plan",
  "eng review the plan", "is this plan sound", "architecture review before
  we build", "check the implementation plan before I start". Do NOT trigger
  for designing a feature from scratch (new-feature), decomposing an
  already-approved plan into feature specs (convert-plan-to-feature),
  devil's-advocate pushback on a decision or idea that is not a written
  implementation plan (anti-sycophancy), or reviewing written code/diffs.
allowed-tools: Read, Grep, Glob, Bash, Write
disallowed-tools: Edit, NotebookEdit
---

# plan-eng-review

The gate between "a plan exists" and "code gets written". Take one written
implementation plan — the plan-mode draft, a file under `docs/plans/`, or a
plan pasted into the conversation — and run a structured engineering review
over it: challenge the scope, check it against the code that already
exists, then work the four dimensions (architecture, code quality, tests,
performance), ending in a verdict and a report.

**This skill reviews the plan; it never implements it. The only mutation it
ever performs is replacing or appending the plan file's
`## ENG REVIEW REPORT` section — every other byte of that file, and every
other file, is preserved exactly.**

## Why this gate exists

Implementation details are where strategy breaks down. A plan can read as
coherent while quietly rebuilding a helper that already exists, modifying
behavior no test covers, or adding a codepath whose failure would be silent
in production — and the cheapest moment to catch each of those is before
the code exists. This review makes those checks systematic instead of
mood-based.

It also corrects its upstream's failure mode in both directions: no
one-interrupt-per-finding storm (findings are batched into the report, each
with a `[REC]`), and no dumping decisions into a deliverable without
walking the user through them (genuine forks are asked, batched per
section, and never silently defaulted).

## The iron law — no finding without evidence

Every headline finding carries evidence in exactly one of two forms:

- **Presence finding** — something in the plan or code is wrong. Evidence:
  quote the plan's own text, or a real `file:line` you verified with Read
  or Grep in this session. For framework-generated symbols (a Django
  `Meta`, a Rails `has_many`, a generated Prisma client), quote the
  meta-construct that generates them — never an imagined class body.
- **Absence finding** — something required is missing: a regression test, a
  rollback step, an error path. Evidence: quote the plan text that creates
  the obligation (the behavior change or new codepath), **and** cite the
  negative search that verified the absence — what you Grepped, where, and
  that it returned nothing.

A claim you can support with neither form is at most a low-confidence
appendix note or an open question — never a headline finding. `GAP` rows in
the coverage summary and rows in the failure-modes table are absence
findings; they follow the same rule.

## Workflow

### Step 0 — Locate the plan and ground the review

Detect where the plan lives:

- **A path the user gave**, or a plan file under `docs/plans/`. Read it end
  to end. A saved file beats your memory of the conversation.
- **The plan drafted in this conversation** (plan mode, or a design the
  user just confirmed) — use the latest confirmed version. When reviewing
  your own plan-mode draft, the plan-mode plan file *is* the plan file:
  review it and splice the report into it.
- **A plan pasted as text** with no file on disk → the review runs the
  same, but the report is terminal-only (see write mechanics).

If it is ambiguous which plan is meant, ask — don't guess.

If the plan file already contains an `## ENG REVIEW REPORT`, read it before
anything else: this run is run N+1 (the prior report's run number plus
one). Carry every still-applicable resolved decision from its Decisions
block forward into the new report — resolved decisions are never re-asked.
Drop a carried decision only if the plan text it applied to is gone.

Then ground the review, read-only: read the repo's `CLAUDE.md`, and
Read / Grep / Glob every file and area the plan proposes to touch. Bash is
for read-only context only — `git log`, `git status`, existence probes —
never to change anything, and never to run the project's code or tests.

### Step 1 — Scope challenge

Before judging how the plan builds, judge what it builds:

- **Minimum viable scope** — the smallest version that delivers the plan's
  stated goal. Name what the plan includes beyond it.
- **Complexity hotspots** — anything touching 8+ files, or introducing 2+
  new classes/services/abstractions; does the plan justify that weight?
- **Deferral candidates** — bundled work the goal doesn't need now.

Scope-reduction opportunities get their own report block, separate from
quality findings — "you could build less" and "this part is wrong" are
different conversations. Real cut/defer/keep choices go to the user as
decisions (below), each with a `[REC]`.

### Step 2 — What already exists

For every new helper, module, service, or pattern the plan proposes: Grep
the codebase for an existing equivalent, and check whether the framework or
standard library already provides it. Every hit is a finding — "the plan
rebuilds X that exists at `path:line`" — filed in the report's **What
already exists** block with the reuse recommendation. Do this before the
dimension passes, so reuse findings inform them.

### Steps 3–6 — the four review dimensions

Full checklists live in
[`references/review-dimensions.md`](references/review-dimensions.md) — read
it when you reach this step. In brief:

- **Step 3 — Architecture.** Component boundaries and coupling, data flow
  and bottlenecks, scaling and failure points, security surface (auth,
  access control, API boundaries), and how any new artifact gets built,
  published, and deployed. For every new codepath or integration, describe
  one realistic production failure scenario and whether the plan accounts
  for it — these rows feed the failure-modes table.
- **Step 4 — Code quality of the planned code.** DRY against the existing
  codebase, over- and under-engineering, the error-handling strategy,
  right-sized abstractions. The code doesn't exist yet — judge what the
  plan commits to, quoting the plan.
- **Step 5 — Tests.** The heaviest dimension. Trace every new codepath and
  user flow the plan creates or changes; check conditional and error paths,
  interaction edge cases, and the coverage the plan actually commits to.
  **REGRESSION RULE (no exceptions): if the plan modifies existing behavior
  and no existing test covers the changed path, a regression test goes into
  Required plan changes. Not a question, not a decision — never asked,
  never waived.** Assign each planned test to E2E, unit, or eval per the
  matrix in the references file.
- **Step 6 — Performance.** N+1 and data-access patterns, memory, caching,
  hot-path complexity — only where the plan plausibly touches them. No
  generic performance advice.

Cap each dimension at **8 findings**, ranked by severity; each carries a
confidence score 1–10 (calibration table in the references file). Overflow
beyond 8 goes to the appendix.

### Decisions — ask real forks, batched per section

Most findings have an objectively right fix; those stay in the report with
a `[REC]`. A finding goes to the user only when it is a genuine fork — a
scope cut, a design alternative with real trade-offs, an accept-the-risk
call. For those:

- Ask with **AskUserQuestion, batched per section** — one call covering all
  the forks that section produced (split only if the tool's four-question
  limit forces it), options labeled with effort and risk, `[REC]` on the
  recommended one.
- **Never silently default.** If a question cannot be asked, is
  interrupted, or goes unanswered, the fork is recorded under
  `UNRESOLVED DECISIONS:` in the closing marker — it stays visible, and it
  forces the verdict down (see the verdict table).
- Every answered fork is recorded in the report's **Decisions** block —
  e.g. `Import processing: async worker (CHOSE B — user, run 2)` or
  `No rate limit on import endpoint (ACCEPTED-RISK — user, run 1)` — and
  carried forward on re-runs so it is never re-asked.

### The report

#### Write mechanics — Write-splice, never Edit

When the plan lives in a file, splice the report in with a single
whole-file Write (full skeleton in the references file):

1. Read the entire plan file.
2. Find H2 boundaries: lines starting with `## ` at column zero — exactly
   two `#` (a third makes it an H3, not a boundary) — **outside fenced code
   blocks** (track ``` fences while scanning), tolerating a trailing `\r`.
3. Delete **every** existing `## ENG REVIEW REPORT` section, wherever it
   sits: each runs from its heading line through the line before the next
   H2 boundary, or EOF.
4. Strip trailing blank lines, then append exactly one blank line and the
   fresh report. The report is the last thing in the file — nothing
   follows it.
5. Write the whole file once. Every non-report byte is preserved exactly,
   line endings included (a CRLF file stays CRLF).

Inside the report: headings are `###` and lower — **never an H2** — and
evidence quotes render as `>` blockquotes or inline code, never a column-0
`## ` line. That is what keeps a quoted heading from becoming a false
boundary on the next re-run.

If the file is too large to rewrite safely in one Write call, fall back to
a terminal-only report and say so. No plan file on disk → terminal-only
report, no writes at all. (The `disallowed-tools` line drops Edit while the
skill is active, but the write discipline is this splice spec — not the
tool list.)

#### Contents, in order

A one-line run stamp (run number, date, plan path) sits between the heading
and the verdict; then:

1. **`VERDICT:`** — one of three verdicts plus a one-sentence rationale,
   bound by this table, checked top-down (judgment never overrides it):

   | Condition | Verdict |
   |---|---|
   | ≥1 CRITICAL GAP row in failure modes, or ≥1 unresolved decision | NEEDS REVISION |
   | Else: Required plan changes non-empty | APPROVED WITH CHANGES |
   | Else | APPROVED |

   Plain APPROVED is deliberately rare for a plan that touches existing
   behavior — the regression rule alone usually populates Required plan
   changes.
2. **Scope-reduction opportunities** — from Step 1, separate from findings.
3. **What already exists** — from Step 2, each with `path:line`.
4. **Findings per dimension** — `[SEVERITY] (confidence: N/10) evidence —
   description`, each followed by a `[REC]`.
5. **Required plan changes** — a checklist of what the plan must change
   before implementation; regression tests always land here.
6. **Failure modes** — table: failure / test? / handled? / user-visible?.
   A row with no test AND no handling AND a silent failure is a
   **CRITICAL GAP**. Handling that silently swallows the failure (skip,
   catch-and-ignore) counts as no handling.
7. **Test coverage summary** — paths traced, planned-coverage stars, gaps,
   the E2E/unit/eval split, the `COVERAGE: N/M` line.
8. **Decisions** — resolved forks, including ones carried forward.
9. **NOT in scope** — deferred work, one-line rationale each.
10. **Appendix** — confidence 3–4 notes; suspicion stated as suspicion.
11. **Closing marker** — the report (and therefore the file) ends with
    exactly one of: `NO UNRESOLVED DECISIONS`, or `UNRESOLVED DECISIONS:`
    followed only by one bullet per open fork. The marker appears exactly
    once, the two variants never co-occur, and nothing follows it.

### Optional outside voice — on explicit ask only

Only when the user asks for a second opinion: spawn one general-purpose
subagent, hand it the plan and the finished report, and prompt it to
**refute the verdict** — argue the verdict is wrong, findings are mistaken,
or something material was missed. Where it disagrees, show both positions
neutrally as tensions and let the user decide; never auto-adopt its
recommendations. Where it agrees, one line says so. Nothing runs
automatically, and no other AI system is involved.

## After the review

- **NEEDS REVISION** → the user amends the plan and re-runs this skill.
  The old report is replaced wholesale; resolved decisions carry forward.
- **APPROVED / APPROVED WITH CHANGES** → the plan moves on: decompose it
  with `convert-plan-to-feature`, or implement it.
- Either way, **this skill never proceeds to implementation itself** — the
  review ends when the report is delivered.

## When NOT to use this skill

- **No plan exists yet** — designing a feature from a fuzzy idea is
  `new-feature`'s job; this skill needs a written plan to review.
- **An approved plan needs splitting** into trackable per-feature specs —
  `convert-plan-to-feature`.
- **Reviewing written code or diffs** — that is code review /
  `sonar-issue-check`; this skill reviews plans, before code exists.
- **Pressure-testing a decision or idea that isn't a written plan** —
  `anti-sycophancy`. It pairs well with this skill (the same skepticism, as
  a stance), but it does not replace the structured gate.

## Worked example

Plan excerpt under review:

> 1. Add a `formatMoney()` helper to `src/utils/format.ts` for the invoice page.
> 2. Change `calculateTotals()` to exclude cancelled line items.
> 3. Also migrate the settings page to the new theme system while we're in there.

Findings produced (abridged):

- *What already exists:* plan step 1 adds `formatMoney()`, but
  `formatCurrency()` at `src/utils/currency.ts:14` (verified by Read)
  already formats amounts. [REC] Reuse it; drop step 1.
- *Tests:* [HIGH] (confidence: 8/10) Plan step 2 — "Change
  `calculateTotals()` to exclude cancelled line items" — modifies existing
  behavior; Grep for `calculateTotals` across `src/**/*.test.ts` and
  `tests/` returned no hits, so no test covers the changed path.
  REGRESSION RULE → Required plan changes: a regression test locking
  current totals plus the cancelled-items case.
- *Scope-reduction:* step 3 is unrelated to the invoice goal — cut/defer
  question to the user, [REC] defer.

`VERDICT: APPROVED WITH CHANGES — sound approach, but the regression test
and the reuse swap must enter the plan first.`

---

Adapted from the `/plan-eng-review` skill in
[`garrytan/gstack`](https://github.com/garrytan/gstack) (MIT, © 2026 Garry
Tan). Rebuilt for this catalog: the one-AskUserQuestion-per-finding gates
become per-section decision batching with findings `[REC]`-batched into the
report; the automatic Codex outside voice becomes an optional, on-request
Claude subagent; the separate test-plan and implementation-tasks artifacts
fold into the single in-plan report; the anti-hallucination quote gate is
extended with an explicit absence-finding evidence form; and gstack state
(`~/.gstack`, `bin/` loggers, brain calibration, TODOS.md flow, the
readiness dashboard, review chaining, Lake Score, worktree parallelization)
is dropped.

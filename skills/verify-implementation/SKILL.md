---
name: verify-implementation
description: >-
  Adversarially verifies completed work against the claim that it is done:
  audits the implementer's report against the actual diff, re-derives every
  acceptance criterion from evidence, reads every new test body and re-runs
  mutation proofs to catch tautological guards, re-runs the project's own
  quality gates, then fixes what it finds. Use when an implementation is
  finished and something asserts it is correct — a feature file with acceptance
  criteria, a plan, a ticket, a PR description, or a subagent's own completion
  report. Do NOT use for reviewing a written plan before code exists (that is
  plan-eng-review), for open-ended critique or feedback (anti-sycophancy), for
  code-quality smells from a static analyser (sonar-issue-fix), for debugging a
  known failing symptom (systematic-debugging), or for reviewing code with no
  claim of completeness attached.
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
model: claude-opus-5
---

# verify-implementation

The gate between "the work is claimed done" and "the work is done". Take one
finished implementation plus whatever asserts it is complete, verify that
claim against the code itself, and fix what the verification finds.

This skill pins `model: claude-opus-5` deliberately: a weaker review returns
`CLEAN` on broken work, and `CLEAN` is acted on. The failure mode of this
skill is false assurance, so it does not run on a smaller model.

There is no `disallowed-tools` line — the skill needs `Edit` and `Bash` to do
its job — so its never-rules are workflow discipline stated below, not a
tool-pool restriction: **it never commits to a shared branch, never pushes,
and never opens a PR.**

## What this skill needs — a claim of doneness

Something must assert the work is complete. In order of preference:

1. **A feature spec with acceptance criteria** — `convert-plan-to-feature`
   emits exactly this shape (`docs/plans/<initiative>/features/NN - <name>.md`
   with a checkbox acceptance list). Its output is this skill's
   highest-preference input.
2. A plan, a ticket, or a PR description that states what was built.
3. The implementer's own completion report (human or subagent).
4. An informal claim ("the retry logic is done now") — derive an acceptance
   table from it and **label the table as derived**, so the reader knows the
   criteria are reconstructed, not authored.

If nothing asserts the work is complete, stop and say so. This skill verifies
claims; with no claim there is nothing to verify against, and inventing
criteria would make the verdict meaningless.

## The stance — the report is a claim, not evidence

Every "met" checkbox and every "done" sentence is unverified until re-derived
independently. Read the **diff first, the report second** — the report frames
what you look at, so an audited-diff-first order is what keeps the review
independent. **A claimed change that is absent from the diff is the most
serious finding available**: it means the claim itself is unreliable, and it
is reported as such — loudly, first — never folded in among style notes.

The balance, stated with equal force: **be fair and factual. If the
implementation is correct, say so plainly and do not invent problems.** A
short review that confirms real evidence is a good review. An adversarial
stance without this sentence degrades into padding — findings manufactured to
look thorough are the same defect as checkboxes ticked without evidence.

## Workflow

### Step 0 — ground the review

Identify three things:

- **The claim** — the feature file, plan, ticket, PR description, or report
  being verified (see the preference order above).
- **The diff** — the actual change set the claim covers: the branch against
  its base, or the named commits. `git diff` / `git log` establish it; the
  report does not.
- **The project's own rules** — read the target repo's `CLAUDE.md`. It
  defines the quality gates, the conventions, and any specs or locked
  decisions that outrank the implementer's report.

If the work is destined to merge into a branch that has moved on, note it
now — Step 4 verifies against the merged tree, not just this branch.

### Step 1 — the verification passes

Run the seven checks in priority order — full checklist, with what counts as
evidence for each, in
[`references/verification-checklist.md`](references/verification-checklist.md)
(read it when you reach this step):

1. **Claim vs diff** — every claimed change located in the diff, every diff
   hunk accounted for by the claim.
2. **Acceptance criteria** — each criterion re-derived from code, tests, or
   captured run output; "the report says so" is not evidence.
3. **Test bodies and mutation proofs** — read every new or modified test body
   in full; prove the guards can fail (Step 2).
4. **Correctness against the spec authority** — the project's `CLAUDE.md` and
   the documents it points to outrank the implementer's reasoning. Decompose
   any argued claim into its premises and check each one separately.
5. **House style and reuse** — does the new code rebuild a helper that
   already exists, and does it match the surrounding conventions?
6. **Scope** — anything silently added (unrequested features, drive-by
   refactors) or silently dropped (criteria left unaddressed, TODOs).
7. **Gates** — the project's own quality gates, re-run (Step 3).

### Step 2 — read every test body, and re-run the mutation proof yourself

**A test that cannot be made to fail is not a guard.** This is the
highest-yield check in the skill: tautological tests pass review by reading
plausibly, and three of them survived human review on one repository before
this rule existed — one asserted routes on an application that never
registered them, one compared a function's result to a second call of the
same function, one asserted the language runtime's own semantics.

For every new test whose mutation proof the implementer did not quote — or
quoted unconvincingly — run it yourself: make the production code wrong,
watch the test fail, capture the verbatim failure message, revert.

The acceptance bar for a proof is concrete: **the mutated line, the verbatim
failure output, and confirmation the mutation was reverted.** Anything less
is an assertion about a test, not a proof. The catalog of tautological
shapes, and how to construct a mutation for common test shapes, is in
[`references/tautology-catalog.md`](references/tautology-catalog.md).

**Run only the targeted test file — or the single test — in each
mutate-run-revert cycle.** The proof needs one test to fail, and a full-suite
run per mutation multiplies the slowest step in the skill by the number of
proofs. The whole suite runs once, as the Step 3 gate pass. The proof bar is
unchanged: verbatim failure output and a confirmed revert either way.

### Step 3 — re-run the gates yourself, and name what you did not run

Never trust reported gate results. Re-run the project's own gates as the
project defines them (`CLAUDE.md` is the source).

- **A gate that was not run is reported as not run, with the reason** — never
  folded into a pass. Every gate line in the report is one of: pass (with
  output), fail (with output), or not run (with why).
- **Read the output, not the exit code.** A measurement script once exited 0
  over a table of `NaN`s and read as a pass until a reviewer looked at what
  it printed.
- **Per-branch green does not imply merged green.** Nine call sites in one
  initiative were green on every branch and failed to compile once combined,
  because a field became mandatory mid-initiative on a branch the others
  predated. If the work will merge into something, verify against the merged
  tree (a local merge of the target branch, discarded afterwards, is enough).

### Step 4 — fix what you found

This skill fixes findings; it does not only report them. Apply fixes on the
same branch, in dedicated commits, minimal and inside the reviewed scope, and
re-run the gates after fixing.

Two things it never does on its own initiative:

- **Change a decision the plan or feature file locked.** If the
  implementation conflicts with a locked decision and the "fix" would be to
  change the decision, leave the code as-is and put the conflict in the
  report.
- **Widen scope.** A real finding whose proper fix belongs to a different
  area is named in the report with its owner, not fixed here.

And the standing rules: never commit to a shared branch (if the work sits
directly on `main`/`master`/`develop`, report the fixes as proposed edits
instead of committing), never push, never open a PR.

**Close the status board.** When the claim being verified is a
`convert-plan-to-feature` feature file (`<initiative>/features/NN - <name>.md`)
and the verdict is `CLEAN` or `FIXED`, update that feature's **Status** cell to
`done` in the initiative's `REQUIREMENTS.md` — it is the board that answers
"where are we", and a verified feature left at `in progress` is how the board
goes stale. Include the edit in the fix commit; on a shared branch, report it
as a proposed edit like any other fix. **Name this write explicitly in the
report** — it is the one change outside the diff under review, so it must never
appear silently. A `NEEDS ATTENTION` verdict changes no Status cell.

### Step 5 — the verdict and the report

Three verdicts, bound by this table, checked top-down — judgment never
overrides it:

| Condition | Verdict |
|---|---|
| Any unfixed finding, any locked-decision conflict, or any gate not run | NEEDS ATTENTION |
| Else: any fix applied | FIXED |
| Else | CLEAN |

Without the table the verdict drifts optimistic. The full six-section report
skeleton (verdict, with the one-line *Passes not run* slot · claim audit ·
findings, most serious first · mutation proofs with verbatim output · gate
results including not-run · acceptance table with the reviewer's own
evidence) is in
[`references/report-format.md`](references/report-format.md).

**When run as a subagent, the report must be the run's return value — not
conversational text along the way.** Findings written as chat output never
reach the coordinator; the agent looks idle when it has actually finished.

## Worked example

A caching optimization marked list pages as permanently fresh, arguing the
records were append-only and ordered newest-first, so a page pinned by a
keyset cursor could never change — any new record could only enter page 0.

Three premises. The reviewer confirmed two by reading the query and the read
path. The third was false: the ordering column was a **caller-supplied
business timestamp**, not the write time. Two shipped code paths backdate
it — every mutating machine-API call supplies it, unbounded, and a scheduled
expiration sweep deliberately stamps each event with the instant the value
actually lapsed. A backdated record therefore lands *mid-list*, on whichever
pinned page its own timestamp falls in, where the optimization hid it until
the cache entry expired.

The reviewer also checked the *benefit* and found it overstated: the requests
went through a batching transport, so the refetch the optimization avoided
was one HTTP request, not nine.

The fix: removed the line, rewrote the comment to name both backdating paths
so nobody re-derives the same wrong argument, added a regression guard, and
mutation-proved it — re-adding the line fails the guard
`expected 2, received 1`.

Three lessons that generalize past this bug:

1. **Decompose the claim into premises and check each separately.** Two of
   three held; a reviewer agreeing with the gist would have stopped.
2. **Check the benefit, not just the risk.** An optimization whose payoff is
   smaller than advertised changes the trade-off even when the risk is
   uncertain.
3. **A wrong argument in a comment is itself a defect.** Fixing the code
   without fixing the reasoning leaves the next reader to re-derive it.

## When NOT to use this skill

- **Reviewing a written plan before code exists** — `plan-eng-review`, this
  skill's pre-implementation counterpart.
- **Open-ended critique or pressure-testing a decision** — `anti-sycophancy`.
- **Clearing static-analyser findings** — `sonar-issue-fix`.
- **Debugging a known failing symptom** — `systematic-debugging`; this skill
  starts from a claim of success, not a known failure.
- **Code with no claim of completeness attached** — there is nothing to
  verify against.

---

Distilled from the review brief used in a 20-feature internal Mi9 initiative
(July 2026), where each feature was implemented by one subagent and
independently reviewed by another under this brief — and the reviews
repeatedly beat their implementers. Not adapted from an external project; no
third-party licence applies.

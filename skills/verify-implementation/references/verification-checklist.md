# The seven verification passes

Run them in this order — it is a priority order, so if time or scope forces a
cut, the cut comes from the bottom and the report names what was skipped.
Each pass defines what counts as evidence; a check whose evidence bar is not
met is **unverified**, and unverified is reported as unverified, never as
passed.

## 1. Claim vs diff

Read the full diff first, then the claim. Then reconcile both directions:

- **Every claimed change is located in the diff.** For each change the claim
  asserts ("added retry to the client", "renamed X", "handled the empty
  case"), find the hunk that implements it and record `path:line`. A claimed
  change with no corresponding hunk is the most serious finding this skill
  can produce — it invalidates the claim as a source, and the report leads
  with it.
- **Every diff hunk is accounted for by the claim.** A substantive change the
  claim never mentions is a scope finding (pass 6) — flag it here, judge it
  there.

Evidence bar: a two-column reconciliation (claimed change ↔ `path:line`, or
`ABSENT`), built from the diff itself — never from the report's own summary
of the diff.

## 2. Acceptance criteria

For each criterion in the acceptance list (or in the derived table, when the
claim was informal):

- Re-derive its status from primary evidence: code you read at `path:line`,
  a test body you read, or command output you captured **in this session**.
- "The implementer's report says it is met" is not evidence. Neither is a
  checked checkbox.
- A criterion you cannot re-derive either way is reported as `UNVERIFIED`
  with what you tried — not guessed in either direction.

Evidence bar: one row per criterion — criterion · status (`MET` / `NOT MET` /
`UNVERIFIED`) · the reviewer's own evidence.

## 3. Test bodies and mutation proofs

- Read **every** new or modified test body in full — not the test names, not
  the describe blocks, the bodies. Tautological tests read plausibly at the
  name level; the defect is only visible in the body.
- For each new test, either the implementer quoted a convincing mutation
  proof, or you run one yourself: mutate the production code, watch the test
  fail, capture the verbatim failure output, revert.
- Shapes to recognize and how to construct mutations:
  [`tautology-catalog.md`](tautology-catalog.md).

Evidence bar: per proof — the mutated line (before/after), the verbatim
failure output, and confirmation the mutation was reverted (`git diff` clean
on production code afterwards). Anything less is an assertion about a test,
not a proof.

## 4. Correctness against the spec authority

- The authority order is the target project's own: its `CLAUDE.md`, and the
  specs, plans, or feature files that document points to. Those outrank the
  implementer's report and reasoning.
- For any claim the implementation *argues* for (an optimization is safe, a
  case cannot occur, an error path is unreachable): **decompose the argument
  into premises and check each premise separately**, by reading the code
  each premise depends on. Agreement with the gist is not verification —
  the worked example in `SKILL.md` failed on exactly one premise of three.
- For optimizations, check the **benefit** as well as the risk: measure or
  trace what the change actually saves. An overstated payoff changes the
  trade-off even when the risk is uncertain.

Evidence bar: per premise — the premise, the `path:line` that confirms or
refutes it.

## 5. House style and reuse

- Does the new code rebuild a helper, type, or pattern that already exists in
  the project? Grep before concluding it doesn't.
- Does it match the surrounding conventions — naming, error types, comment
  density — and the project's stated standards (`CLAUDE.md`)?
- A wrong argument in a comment is a defect (pass 4's example): correct
  reasoning in comments is part of correctness, not style polish.

Evidence bar: for a rebuild finding, the existing equivalent at `path:line`.
For a convention finding, the convention's source (the `CLAUDE.md` line, or
three existing examples).

## 6. Scope — added or quietly dropped

- **Added:** features nobody asked for, drive-by refactors, dependency
  additions, config changes outside the claim. Each is a finding — whether
  it stays is a judgment for the report, but it must be visible.
- **Dropped:** acceptance criteria with no implementing change, TODO/FIXME
  markers introduced by this work, error paths stubbed out, tests skipped or
  marked pending.

Evidence bar: for added scope, the hunk at `path:line` plus the absence of
any claim text covering it. For dropped scope, the claim text that creates
the obligation plus the negative search that verified nothing implements it.

## 7. Gates

- Re-run the project's own quality gates as the project defines them —
  `CLAUDE.md` is the source for what they are. Never trust reported results.
- Read the **output**, not the exit code — a gate that exits 0 over garbage
  output (a `NaN` table, "0 tests found", an empty report) is not a pass.
- A gate that was not run is reported as **not run, with the reason** —
  never folded into a pass.
- If the work will merge into a branch that has moved on, run the gates
  against the merged tree too (a local merge, discarded afterwards) —
  per-branch green does not imply merged green.

Evidence bar: per gate — the command, pass/fail/not-run, and enough verbatim
output to support the status.

# Report format

The report has six sections, in this order. When the skill runs as a
subagent, **this report is the run's return value** — not conversational text
emitted along the way. Findings written as chat output never reach the
coordinator; the agent looks idle when it has actually finished.

## The verdict decision table

Three verdicts, bound by this table, checked top-down — judgment never
overrides it:

| Condition | Verdict |
|---|---|
| Any unfixed finding, any locked-decision conflict, or any gate not run | NEEDS ATTENTION |
| Else: any fix applied | FIXED |
| Else | CLEAN |

- `CLEAN` — nothing to fix. Every acceptance criterion re-derived, every new
  test proven mutable, every gate run and passed on real output.
- `FIXED` — findings existed and every one was fixed on the branch, in
  dedicated commits, with gates re-run green afterwards.
- `NEEDS ATTENTION` — at least one finding is left for a human: unfixed,
  outside the reviewed scope, in conflict with a locked decision, or a gate
  could not be run.

Without the table the verdict drifts optimistic; with it, `CLEAN` is a strong
claim — which is the point.

## The six sections

### 1. Verdict

One of the three words, then one sentence of rationale, then (for `FIXED`)
the list of fix commits, then a one-line **Passes not run** slot naming any
of the seven verification passes that were skipped and why — `none` when all
seven ran. The passes are a priority order and a cut comes from the bottom;
this line is where the cut is visible, so it is never omitted.

```
VERDICT: FIXED — 2 findings, both fixed in commits <sha1>, <sha2>; gates re-run green.
Passes not run: none.
```

```
VERDICT: NEEDS ATTENTION — 1 finding left for the owner (out of scope).
Passes not run: 6 (scope) — diff spans a vendored directory excluded from review.
```

### 2. Claim audit

The pass-1 reconciliation: each claimed change with the `path:line` that
implements it, or `ABSENT`. Any `ABSENT` row is repeated under Findings as
the most serious finding.

| Claimed change | In the diff |
|---|---|
| Retry added to the client | `src/client.ts:41-58` |
| Cancelled items excluded from totals | **ABSENT — no hunk touches the totals path** |

### 3. Findings

Most serious first. Each finding carries:

- `path:line`
- the concrete failure — what goes wrong, on what input or state
- **fixed or not** — `FIXED in <sha>` or `NOT FIXED — <reason>` (out of
  scope, locked decision, needs an owner decision)

A finding without a concrete failure is not a finding — file it as a note or
drop it. Do not pad: if the implementation is correct, this section says so
in one line and the report is short. That is a good report.

When the verdict is `CLEAN` or `FIXED` on a `convert-plan-to-feature` feature
file, the Status-cell update in the initiative's `REQUIREMENTS.md` is named
here as its own line — path, cell, old value → `done`, and whether it was
committed or is a proposed edit. It is the one change outside the reviewed
diff, so it is stated, never silent.

### 4. Mutation proofs run

One entry per proof: the test, the mutated line (before/after), the verbatim
failure output, revert confirmed. Proofs the implementer supplied and you
accepted are listed as `accepted as quoted`; proofs you re-ran are quoted in
full.

### 5. Gate results

Every gate the project defines, each with exactly one status:

- `PASS` — with enough verbatim output to support it (a summary line, not
  just an exit code)
- `FAIL` — with the failing output
- `NOT RUN` — with the reason (tool not installed, environment missing,
  blocked by an earlier failure)

If the work merges into a moving branch, a `merged-tree` row records the
gates against the local merge.

### 6. Acceptance table

One row per criterion — including derived criteria, with the table labeled
`derived` when the claim was informal:

| Criterion | Status | Reviewer's evidence |
|---|---|---|
| Cancelled items excluded from totals | MET | `calculateTotals` skips `status === 'cancelled'` (`src/totals.ts:88`); regression test mutation-proved (§4) |
| Import errors surface to the user | UNVERIFIED | no UI harness available; error path traced to the toast call (`src/import.ts:120`) but not executed |

Statuses: `MET` / `NOT MET` / `UNVERIFIED` — with the reviewer's own
evidence, never the implementer's checkbox. Any `NOT MET` or `UNVERIFIED`
row must be reflected in Findings or in the verdict rationale.

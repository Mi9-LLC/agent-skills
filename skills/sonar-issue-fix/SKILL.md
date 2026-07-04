---
name: sonar-issue-fix
description: >-
  Use this skill to FIX and clear SonarCloud / SonarQube findings on a branch or
  PR by editing the code — the companion to sonar-issue-check, which only
  reports. Triage the new-code issues by rule, apply behavior-preserving
  mechanical fixes, and for cognitive-complexity (S3776) refactors write
  characterization tests first, then re-verify with the project's lint /
  type-check / test gates. A Sonar fix never changes runtime or wire behavior;
  genuine bugs are surfaced, not force-fixed. Trigger for ANY ask to resolve,
  clear, clean up, knock out, or get rid of Sonar findings / code smells, or to
  make the quality gate pass: e.g. "fix the sonar issues on my branch", "clear
  the sonarcloud findings before I merge", "make the quality gate green", "fix
  the cognitive complexity Sonar flagged". Do NOT trigger when the user only
  wants to SEE what Sonar found (use sonar-issue-check), or wants to fix the CI
  scan step, set up SonarLint, or change quality-gate thresholds.
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# Sonar issue fix

Resolve the SonarCloud / SonarQube issues on the current branch the way a
careful engineer would: read what Sonar actually flagged, fix each finding at
its rule's natural depth, and prove the change is safe before moving on. The
guiding constraint is that **a Sonar fix must never change runtime or wire
behavior** — these are code-quality smells, not bug fixes. If a "fix" would
alter what the program outputs, it is the wrong fix.

This skill *changes code*. Its read-only sibling, `sonar-issue-check`, only
reports — run that first to know the work, then this to do it.

**Scope.** The per-rule recipes in `references/rule-fixes.md` are
JavaScript/TypeScript today (rule keys like `typescript:S3776`). The *workflow*
— triage → mechanical-first → characterization-tests-first for refactors →
re-verify — is language-agnostic; for a rule or language not in the catalog,
read the rule's own description (it's in the finding, or on the Sonar rules
site) and apply the same behavior-preserving discipline, then add a recipe.

## Workflow

### 1. Get the findings

If the `sonar-issue-check` skill is installed, run its script to get the
branch's **new-code** issues — the default scope, which is almost always what
"fix the Sonar issues" means:

```bash
node .claude/skills/sonar-issue-check/scripts/extract-sonar-issues.mjs
```

If the script isn't found at that path (e.g. a personal install under
`~/.claude/skills/`), use the Glob tool to locate
`**/sonar-issue-check/scripts/extract-sonar-issues.mjs` before falling back to
asking the user to paste the issue list.

Use `--pull-request <id>` or `--branch <name>` if the user named a specific
target. **If the check skill isn't installed, or the user already pasted a list
of findings, use that and skip the fetch** — all this step needs is, per
finding, a `file:line`, a message, and a **rule key** (e.g. `typescript:S3776`).
The rule key is what tells you how to fix it.

**Timing caveat (important):** Sonar only knows about code its CI scan has
already analysed. Findings reflect the *last pushed+scanned* commit, not your
working tree. So the line numbers may point at pre-edit locations, and a finding
you just fixed locally will still show until you push and the pipeline re-scans.
Plan for this: fix locally, verify locally (step 4), then push and re-run
`sonar-issue-check` to confirm (step 5).

### 2. Triage by rule

Group the findings into two buckets — they have very different risk:

- **Mechanical** (most MINOR/MAJOR rules): a localized, behavior-identical edit
  with a known recipe. Low risk. See `references/rule-fixes.md` for the
  per-rule recipes (zero-fraction literals, `replaceAll`, `.at(-1)`, explicit
  enum values, negated-condition flips, base-to-string, …).
- **Structural** (cognitive complexity `S3776`, and any large refactor): the fix
  reshapes a function. Higher risk, especially on code with **no test coverage**.
  These get the tests-first treatment in step 3.

Order the work mechanical-first: it's quick, low-risk, and shrinks the diff
before you touch anything structural.

### 3. Apply the fixes

**Mechanical fixes** — apply the recipe from `references/rule-fixes.md`. Each
recipe is chosen to satisfy Sonar *and* honor the project's own house style
(read `CLAUDE.md` / `AGENTS.md` and the linter config — e.g. a negated-condition
fix should match whatever positive-first convention the repo already follows,
S7735). Never trade one smell for another. A recipe that *looks* right but
doesn't actually remove the construct the rule binds to is worse than no fix — it
costs a whole push + scan cycle to discover. The catalog flags these traps (e.g.
S6551's `no-base-to-string` ignores `typeof`-guard narrowing, so guarding the
object case but still calling `String()` on the other branch stays flagged) so
you don't burn one.

**Structural fixes (cognitive complexity, untested code)** — characterization
tests come FIRST. The point of decomposing a function is to keep its output
identical while making it readable; you cannot claim that safely without a test
that locks the current output. So:

1. **Write characterization tests first.** Build representative fixtures that
   fork down every branch the function takes, call the function, and snapshot
   the result (your test framework's snapshot assertion, or an equality check
   against captured literals). Run them and confirm green — this captures
   *current* behavior as the baseline, before any refactor.
2. **Refactor to identical output.** Extract helpers, replace repeated ternaries
   with a single branch that assembles a variant object, pull nested
   conditionals into well-named functions — whatever drops the cognitive
   complexity under the limit. In a typed language, a structural type assertion
   on the assembled object (e.g. TypeScript's `satisfies <Type>`) is a strong
   compile-time guard that you didn't drop or rename a field.
3. **Re-run the snapshots.** They must stay **byte-identical**. That is the
   pass/fail signal for the refactor. If a snapshot changes, the refactor
   changed behavior — revert and redo, do not update the snapshot.

These characterization tests are not throwaway — they stay as permanent
regression coverage for code that previously had none.

See `references/rule-fixes.md` for the catalog and `references/refactor-playbook.md`
for the complexity-decomposition patterns and the testing gotchas (mocking,
snapshot key ordering) that bite during this kind of refactor.

### 4. Re-verify locally

After applying fixes, run **the project's own quality gates** and confirm green.
Discover them rather than assuming — check `package.json` scripts (or the
equivalent for the stack), `CLAUDE.md`/`README`, and the CI config. They
typically are:

```bash
# Examples — substitute the project's actual commands:
npm run lint            # linter / formatter (catches reintroduced smells / style)
npx tsc --noEmit        # type-check (TS projects)
npx vitest run <paths>  # the characterization suite + existing tests for changed files
```

The characterization snapshots staying byte-identical is the headline check for
any structural fix. Lint must be clean — a fix that reintroduces a different
Sonar/linter smell is not done.

### 5. Confirm against Sonar (after push)

Local gates prove the code is correct and clean, but only Sonar's gate closes
the loop. Because Sonar reads scanned commits (the timing caveat above), the
user must push so the CI pipeline re-scans. Commit + push **only if the user
asked** (Sonar fixes are usually bundled into the feature branch's existing PR —
follow the repo's own commit-message convention). Then wait for the pipeline to
finish and re-run `sonar-issue-check`; the freshly-scanned result should show 0
new issues (or the reduced set you expect).

Each push + scan cycle costs several minutes, so before pushing be *sure* each
fix actually clears its rule — confirm the edit removes the construct the rule
binds to, not merely relocates or guards it. (This is what makes the per-rule
recipes worth following over an intuitive edit.)

## Guardrails

- **Behavior is frozen.** No Sonar fix may change runtime output, wire format,
  timing, or error behavior. When a rule's "fix" is ambiguous, pick the variant
  that provably preserves behavior (e.g. keep `=== null`, don't swap in an
  `isNil`-style helper that would also catch `undefined`).
- **Tests before risky refactors.** Never decompose an untested function and
  declare it safe — lock the output first.
- **Don't reintroduce smells.** The fix must satisfy Sonar *and* the project's
  house rules (`CLAUDE.md` / `AGENTS.md` / linter config). Re-read the relevant
  rule there before applying a recipe.
- **Don't commit or push unless asked.** Applying and verifying the fix is the
  deliverable; the user decides when it lands.
- **Skip what isn't yours to fix here.** If a finding's correct fix is a genuine
  behavior change (a real bug), surface it to the user as a bug to fix
  deliberately, rather than forcing a quality-pass edit over it.

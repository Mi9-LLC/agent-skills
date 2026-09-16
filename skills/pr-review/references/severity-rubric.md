# Severity rubric

Assign a severity from this file, not by feel. Two reviews of the same repository that rate the same
defect differently are worth less than one review, because the author cannot tell whether HIGH means
"stop" or "the reviewer was in a mood".

The examples here come from a real review, and they are kept because they show where the lines
actually fell rather than where an invented illustration would put them. Judge your own case against
the definitions below, not against the subject matter of the example.

## Contents

- [The four levels](#the-four-levels)
- [Rate on the failure mode, not the size of the diff](#rate-on-the-failure-mode-not-the-size-of-the-diff)
- [Bounded or unbounded is the usual dividing line between HIGH and MEDIUM](#bounded-or-unbounded-is-the-usual-dividing-line-between-high-and-medium)
- [A wrong justification for correct code is a real finding](#a-wrong-justification-for-correct-code-is-a-real-finding)
- [A claim the repository does not support is a finding](#a-claim-the-repository-does-not-support-is-a-finding)
- [Documentation-only findings are marked and capped](#documentation-only-findings-are-marked-and-capped)
- [Packaging can raise a finding by one level](#packaging-can-raise-a-finding-by-one-level)
- [Re-rating a finding](#re-rating-a-finding)
- [What to flag](#what-to-flag)
- [What not to flag](#what-not-to-flag)

## The four levels

**CRITICAL — the merge is blocked; this breaks production or exposes data.**
Credentials or customer data written to a log or a response. An authentication or tenant-isolation
check removed or bypassed. A migration that destroys data. Code that cannot compile, parse or start.
A CDC change that drops or duplicates events with no way to recover them. CRITICAL findings are
repeated in full in the posted comment.

**HIGH — fix before merge; the change is wrong, or its failure is unbounded and silent.**
Logic that produces wrong results regardless of input. An unbounded retry or loop. A failure path
with no upper bound, no alert and no health signal. A breaking change to a public contract, a rule
schema, a persisted format or a wire format, shipped without a migration path. A resource leak on the
hot path.

**MEDIUM — fix, but it does not have to block the merge.**
A correct change whose stated rationale is wrong. A low-probability failure that is silent and
permanent when it happens. A guard that does not guard what its comment says. A rule applied
inconsistently across sibling files. A commit message that claims something the repository does not
support. A change that buys nothing and carries non-zero risk.

**LOW — worth correcting, nothing depends on it.**
Duplication of a shared helper. A comment that sits far from the line it explains. A message that
omits a detail. Two spellings of the same fallback in one file. A cited rationale that does not
support its own conclusion, where the conclusion happens to be right anyway. Naming, ordering, dead
code.

## Rate on the failure mode, not the size of the diff

A one-line change is rated on what happens when it is wrong, not on how little it changed.

In pull request #29, a single property rename was described by its own author as maintenance rather
than a fix, and it was correct as written. It was still rated MEDIUM, because if the environment
variable did not bind to the property, Debezium would not error. It would take the default, write
offsets to a table nobody provisions or backs up, and keep reporting healthy. The rating came from
the silence, not the size:

> An unnecessary change with a silent, permanent, low-probability failure mode is worth a ten-minute
> check, not a HIGH rating.

The general rule: a failure that announces itself is worth less severity than a failure of the same
size that does not, because a loud failure is found in minutes and a silent one is found by its
consequences.

## Bounded or unbounded is the usual dividing line between HIGH and MEDIUM

This is what moved a finding in pull request #29. The first draft rated it HIGH on the reasoning that
a failed table auto-create would retry forever, because `errors.max.retries` defaults to `-1`.
Reading the Debezium source showed that setting applies only to `RetriableException` around record
polling and does not govern the JDBC offset store, which has its own retry, bounded at version 3.6.2
to five attempts by default. A bounded retry gives up and fails the connector, which exits the
process, so that branch is loud. The finding was re-rated MEDIUM.

So: an error path that terminates and reports is MEDIUM or LOW. The same error path with no upper
bound, no alert and nothing that exits is HIGH. Check which one it is before assigning the severity,
by reading the source that implements the retry rather than the documentation that describes it.

## A wrong justification for correct code is a real finding

Code can be right for a reason that is wrong. That is worth reporting, because the next person to
change the code will act on the stated reason, not on the behaviour.

Pull request #29, finding M2: a guard was added that skips pushing a commit-pinned image tag when the
resolved reference equals the literal string `local`, with the stated rationale that the helper
returns `local` on every workstation build. Reading `deploy/gcp/shared/common.sh:448-455` showed it
returns `local` only when `git rev-parse` fails, so the guard is true in an ordinary developer
checkout, which is the exact case it was written to prevent. The code is not a regression and the
guard is harmless. The justification is false, and the conclusion drawn from it, that the per-commit
tag is now trustworthy, is false too.

This kind of finding is rarely above MEDIUM, because nothing is broken today. It goes above MEDIUM
only when someone is likely to act on the wrong reason in a way that breaks something. Its fix is
usually a correction to a comment or a commit message rather than a code change, and the report says
so.

## A claim the repository does not support is a finding

Commit messages and pull request descriptions are claims to check, not evidence. When a commit says
it did something and the diff does not contain it, that is a finding in its own right.

Pull request #29, finding M4: a commit message said it closed a checklist item in
`deploy/gcp/docs/security-checklist.md`. `git diff --name-only` over the review range returned eight
files and that file was not among them. The underlying control was genuinely enforced by the change,
so nothing was broken; what was wrong was the record. MEDIUM.

The same applies in the other direction. When a claim is checked and holds, it belongs in section 7
of the report with its evidence, not left unmentioned. A claim that was verified and a claim that was
never looked at read identically when the report is silent about both.

A claim that could not be settled is neither a finding nor a pass. It goes into section 8, "what was
NOT checked", with the exact source or command that would settle it.

## Documentation-only findings are marked and capped

Every finding is marked functional or documentation-only. A documentation-only finding is capped at
MEDIUM, because nothing running is affected by it. It reaches MEDIUM when the wrong record is the
kind someone relies on: a security checklist an auditor reads, a runbook someone follows during an
incident, a commit message a reviewer trusts. Otherwise it is LOW.

The marking matters for the remediation plan as much as for the severity. Documentation-only items
need no build, no test run and no deploy, so they are batched into one step.

## Packaging can raise a finding by one level

How a change is committed is part of the change. In pull request #29 the property rename and a
valuable security fix were in the same commit, so reverting the risky half would also remove the fix.
That is what kept the finding at MEDIUM rather than LOW:

> If the rename misbehaves, `git revert 28c58e8` also removes the autocreate fix, reopening the
> `all_tables` exposure. That contradicts the PR's own organising principle.

Raise a level when the packaging removes the cheap escape route: a risky change bundled with one that
must not be reverted, a migration in the same commit as the code that depends on it, or a library and
a service change that have to be deployed in a fixed order but are packaged as one.

## Re-rating a finding

Severities change during a review. That is the process working, and it is recorded openly rather than
quietly edited away.

Two things happen when a rating moves:

1. The finding's severity line says what it was and why it moved, for example
   `**Severity**: MEDIUM *(downgraded from HIGH during this review — see section 2, correction 2)*`,
   with a quoted correction paragraph inside the finding giving the mechanism that turned out to be
   wrong.
2. The corrections block in section 2 of the report lists the change in one or two sentences.

A finding that is withdrawn entirely is handled the same way. In pull request #29 a draft finding
claimed that setting the publication autocreate mode to `disabled` would not fail loudly, resting on
an incident note at `deploy/gcp/README.md:678`. Reading the Debezium source settled it the other way:
the author's claim was sound. The finding was removed from the findings list and moved to section 7
as verified-correct with its full evidence chain, and correction 1 in section 2 says that is where it
went.

If the summary comment is already posted when a correction is made, post a threaded reply on the pull
request stating what was wrong and why. Editing the report alone leaves the author acting on a
finding the reviewer no longer stands behind, and a reviewer's credibility rests on the corrections
being as visible as the findings were.

## What to flag

Flag an issue where:

- The code will fail to compile or parse: syntax errors, type errors, missing imports, unresolved
  references.
- The code will definitely produce wrong results regardless of inputs: clear logic errors.
- There is a clear, unambiguous `CLAUDE.md` violation and the exact rule being broken can be quoted.
- A claim in a commit message, in the pull request description, or in a document the pull request
  adds is contradicted by the repository or by the upstream source.

If you are not certain an issue is real, do not flag it. False positives lose trust and waste
reviewer time.

## What not to flag

This list is used both when generating findings and when validating them. Anything matching it is
dropped:

- Pre-existing issues
- Something that appears to be a bug but is actually correct
- Pedantic nitpicks that a senior engineer would not flag
- Issues that a linter will catch (do not run the linter to verify)
- General code quality concerns, for example lack of test coverage or general security issues, unless
  `CLAUDE.md` explicitly requires it
- Issues mentioned in `CLAUDE.md` but explicitly silenced in the code, for example by a lint ignore
  comment

Also do not flag:

- Code style or quality concerns.
- Potential issues that depend on specific inputs or state.
- Subjective suggestions or improvements.

One exception, and it is the reason the verification pass exists: a pre-existing problem that this
change interacts with, or that blocks the review itself, is reported in the optional section "one
thing outside the diff, found while writing this report", explicitly labelled as not a finding
against this pull request. It is never counted in the severity table.

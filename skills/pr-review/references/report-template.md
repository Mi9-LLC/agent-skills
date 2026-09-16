# Report template

The review report is the primary output of this procedure. The posted comment is a summary of it.
Write the report to `docs/reviews/pr-review-{repo}-{pr_number}.md` in the working directory you
started in, or, if the repository's own `CLAUDE.md` names a different place for review or audit
documents, to that place.

The four worked examples below, one per severity, are the shape to follow.

Two rules govern everything here:

1. **Every finding quotes the evidence it rests on.** A line of code, a line of a `CLAUDE.md` rule,
   a line of a commit message, or a line of the source that settles the claim. A finding with no
   quoted evidence does not go in the report, because the reader cannot check it and a remediation
   agent cannot act on it.
2. **The report says what it did not check.** A report that lists only findings reads like a clean
   bill of health for everything it is silent about. Section 8 is what stops that.

## Contents of this template

- [Header block](#header-block)
- [How this review was produced](#how-this-review-was-produced)
- [1. Overview](#1-overview)
- [2. Findings summary](#2-findings-summary)
- [3-6. The findings themselves](#3-6-the-findings-themselves)
- [Worked example: a CRITICAL finding](#worked-example-a-critical-finding)
- [Worked example: a HIGH finding](#worked-example-a-high-finding)
- [Worked example: a MEDIUM finding](#worked-example-a-medium-finding)
- [Worked example: a LOW finding](#worked-example-a-low-finding)
- [Recording a finding that changed during the review](#recording-a-finding-that-changed-during-the-review)
- [7. What was checked and found correct](#7-what-was-checked-and-found-correct)
- [8. What was NOT checked, and why](#8-what-was-not-checked-and-why)
- [9. Optional sections](#9-optional-sections)
- [10. What looks good](#10-what-looks-good)
- [11. Remediation plan](#11-remediation-plan)
- [12. Verdict](#12-verdict)
- [13. Sources read for this review](#13-sources-read-for-this-review)
- [Self-review before declaring the report done](#self-review-before-declaring-the-report-done)

---

## Header block

```markdown
# PR Review — {repo} #{pr_number}

**PR**: {title}
**Source**: `{source-branch}` -> `{destination-branch}`
**Head reviewed**: `{full 40-character head sha}`
**Merge base with {destination-branch}**: `{full 40-character merge-base sha}`
**Reviewed**: {YYYY-MM-DD}
**Scope**: read and comment only. Nothing was pushed, merged, edited or deployed.
```

Both hashes are full, not abbreviated, and both come from the pinned checkout
(`scripts/pin-pr-head.sh` prints them as `HEAD=` and `MERGE_BASE=`). They are here so anyone reading
the report later can reproduce exactly the range that was reviewed. A report whose line numbers
cannot be reproduced is not checkable.

## How this review was produced

A short prose block, not a list of tool names. It covers:

- That the branch was cloned into a throwaway checkout and pinned before anything was read, and why:
  the shared working directory is used by other sessions and its checked-out branch moves.
- The two commands that confirmed the pin, with their output quoted.
- Which sibling repositories were read, by path, and that they were read only.
- How claims in the commit messages and the pull request description were treated. The standard
  sentence is that every claim was treated as a claim to settle from sources, not as evidence.
- Whether the pull request adds its own review or design document. If it does, say that the document
  was written by the same author as the code, so it is part of the change under review and its
  quotations are claims rather than support.
- Which stage produced which findings, so a reader can tell diff-reading from claim-checking.

## 1. Overview

Two tables and the commit list.

```markdown
| | |
|---|---|
| Files changed | 8 |
| Lines | +589 / -41 |
| Code/config files | 6 (all under `deploy/`) |
| Documentation | 2 |
| Application code touched | none (`services/`, `libs/` untouched) |

| File | + | - |
|---|---|---|
| `path/to/file` | 10 | 3 |
```

Then the commits, one line each, with the short hash and what the commit does. If the author split
the commits deliberately, say so, because the remediation plan may depend on that split holding.

## 2. Findings summary

The counts table, then one paragraph saying whether anything blocks the merge, then the corrections
block if the review changed its own mind about anything.

```markdown
| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 4 |
| LOW | 12 |
```

## 3-6. The findings themselves

One section per severity, one subsection per finding, numbered `C1`, `H1`, `M1`, `L1` and so on.
Every finding carries these fields, in this order:

- **Severity** — CRITICAL, HIGH, MEDIUM or LOW, assigned from `severity-rubric.md`, never by feel.
  If the severity changed during the review, say so on this line and point at the corrections block.
- **File** — exact path and line numbers, and the commit the line came from when the pull request has
  more than one commit.
- **Stage** — `diff pass` or `verification pass`.
- **Category** — a few words: correctness, security, blast radius, documentation accuracy.
- **Functional or documentation** — documentation-only findings are marked, because the remediation
  plan treats them differently and the rubric caps their severity.
- **Current code** — the snippet as it exists today, quoted.
- **Description** — why it matters, with the evidence quoted inline.
- **Suggested fix** — the corrected code, not a description of it. A remediation agent should be able
  to apply it without opening anything else.
- **Impact if unfixed** — what breaks or degrades.

### Worked example: a CRITICAL finding

CRITICAL is rare. The rubric defines it as something that breaks production or exposes data the
moment the change is merged. The shape is the same as HIGH with one addition: the first line says
the merge is blocked, because this finding is repeated in full in the posted comment.

````markdown
### C1 — The outbound request logger writes the retailer bearer token in clear text

**Severity**: CRITICAL — blocks the merge
**File**: `services/pipeline-service/src/http/client.ts:88`
**Stage**: diff pass
**Category**: security, credential disclosure
**Functional or documentation**: functional

**Current code**:

```ts
logger.info({ headers }, 'outbound request');
```

**Description**: `headers` carries `authorization` on every retailer call. The redaction list at
`logger.ts:22` covers `req.headers.authorization`, not a bare `headers` object, so the token is
written in clear text to Cloud Logging, retained for 30 days and readable by every principal with
the Logs Viewer role.

**Suggested fix**:

```ts
logger.info({ headers: redact(headers) }, 'outbound request');
```

**Impact if unfixed**: every retailer token in use is disclosed to anyone with log read access, and
all of them have to be rotated once this has run in production, even briefly.
````

### Worked example: a HIGH finding

````markdown
### H1 — The retry loop has no upper bound, so a permission error becomes an endless restart

**Severity**: HIGH
**File**: `libs/core/src/retry.ts:41-58`
**Stage**: diff pass
**Category**: correctness, availability
**Functional or documentation**: functional

**Current code**:

```ts
while (true) {
  try {
    return await run();
  } catch (error) {
    await delay(backoff);
  }
}
```

**Description**: the loop catches every error, including ones that cannot succeed on a retry. A
missing IAM grant throws the same way a dropped connection does, so the caller never returns and
never logs a terminal failure. The root `CLAUDE.md` also names this directly:

> Never hand-roll file I/O, path manipulation, HTTP requests, date parsing, data validation, JSON
> handling, or retry logic when a rung 1-2 option exists.

**Suggested fix**:

```ts
for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
  try {
    return await run();
  } catch (error) {
    if (!isRetriable(error)) throw error;
    await delay(backoff * 2 ** attempt);
  }
}
throw new RetryExhaustedError(MAX_ATTEMPTS);
```

**Impact if unfixed**: a misconfigured deployment hangs instead of failing, and the hang is invisible
to the health endpoint, so the first signal is a stalled pipeline hours later.
````

### Worked example: a MEDIUM finding

This is the shape of M4 in the pull request #29 report: a commit message asserts something the
repository does not support.

````markdown
### M4 — The commit claims a security-checklist item is closed, but the checklist is untouched

**Severity**: MEDIUM
**File**: `deploy/gcp/docs/security-checklist.md:353` (not in the diff)
**Stage**: verification pass
**Category**: documentation accuracy
**Functional or documentation**: documentation-only

Commit `28c58e8` states:

> It also closes the unchecked "Publication limited to specific tables (not FOR ALL TABLES)" item in
> `deploy/gcp/docs/security-checklist.md`.

`git diff --name-only 058a2bc..bea2757` returns eight files and `security-checklist.md` is not one
of them. Line 353 still reads:

```markdown
- [ ] Publication limited to specific tables (not `FOR ALL TABLES`)
```

**Suggested fix**: tick the item in this pull request and name the setting that enforces it.

**Impact if unfixed**: the checklist understates the project's posture and the commit message
overstates what the commit did. Either is small; together they mean neither artifact can be trusted
on its own.
````

### Worked example: a LOW finding

````markdown
### L1 — `build_cloud` hand-rolls `resolve_vcs_ref` instead of using the shared helper

**Severity**: LOW
**File**: `deploy/gcp/01-debezium-service/build-debezium.sh:96-101`
**Stage**: verification pass
**Category**: duplication
**Functional or documentation**: functional, behaviour-identical today

**Current code**:

```bash
VCS_REF="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo local)"
```

**Description**: `deploy/gcp/shared/common.sh:448-455` already defines `resolve_vcs_ref` and the copy
here reproduces its body. The two agree today. They will not stay in agreement, and a change to the
shared helper will silently skip this file.

**Suggested fix**:

```bash
# shellcheck source=../shared/common.sh
VCS_REF="$(resolve_vcs_ref "${REPO_ROOT}")"
```

**Impact if unfixed**: nothing today. The copy diverges the first time the shared helper changes.
````

## Recording a finding that changed during the review

A finding that was re-rated or withdrawn is recorded, not quietly fixed. It goes in two places.

**In section 2**, a numbered corrections block directly under the summary paragraph:

```markdown
**Two corrections to earlier drafts of this review, both against my own findings.** Recorded rather
than quietly fixed, because a remediation agent reading this should know which conclusions moved.

1. An early draft rated as HIGH the claim that `publication.autocreate.mode=disabled` does *not* fail
   loudly, on the strength of `deploy/gcp/README.md:678`. Reading the Debezium source settled it the
   other way: the claim is sound. It now appears in section 7.1 as verified-correct, with its full
   evidence chain.
2. A later draft rated the offset-property rename HIGH, on the reasoning that a failed auto-create
   would retry forever because `errors.max.retries` defaults to `-1`. That mechanism does not apply
   here. The offset store has its own retry and at 3.6.2 it is bounded. That removes the
   loud-failure-turned-silent branch and leaves a narrower risk, so the finding is now **M1,
   MEDIUM**.
```

**In the finding itself**, on the severity line and in a quoted correction paragraph:

```markdown
**Severity**: MEDIUM *(downgraded from HIGH during this review — see section 2, correction 2)*

> **Correction.** An earlier draft of this finding claimed Branch B loops forever because
> `errors.max.retries` defaults to `-1`. That was wrong. `errors.max.retries` is caught only for
> `RetriableException`, and only around record polling.
```

A withdrawn finding does not simply disappear. It moves into section 7 as a verified-correct item
with the evidence that settled it, and the corrections block says where it went.

If the summary comment was already posted when the correction was made, a threaded reply on the pull
request states the change too. The report and the comment must not disagree with each other.

## 7. What was checked and found correct

Numbered subsections, each naming the source it was checked against. This section exists so a reader
can tell verified-correct from not-looked-at, which is the distinction a bare findings list destroys.
A claim that was checked and held is worth as much to the author as a finding.

Include a subsection for the static checks, with their exact results:

```markdown
### 7.9 Static checks run for this review

- `bash -n` clean on `deploy-debezium-service.sh`, `build-debezium.sh`, `constants.sh`.
- `shellcheck -S warning` clean (exit 0, no output) on two of the three. `constants.sh` emits only
  pre-existing `SC2034` "appears unused" warnings, which are expected for a constants file and are
  not introduced by this pull request.
- Files were normalised with `tr -d '\r'` before `shellcheck`, because several working-tree files are
  CRLF from older checkouts and `SC1017` would otherwise bury the real findings. That is a checkout
  artifact, not a defect in this change.
- The repository's CI configuration runs no shell linter, so the above is the only static analysis
  these files get. If CI does run one, say which.
```

If a gate could not run, name it here as not run. Never leave it looking like it passed.

## 8. What was NOT checked, and why

A numbered list. Each item names the gap and the exact source or command that would settle it. Write
this section before the verdict, not after, because what is missing usually changes the verdict.

```markdown
1. **The environment-variable-to-property mapping** for
   `DEBEZIUM_SOURCE_OFFSET_STORAGE_JDBC_TABLE_NAME`. This depends on Quarkus/SmallRye Config's
   environment-variable source, not on the Debezium property constants. Not settled; it is M1, with
   the ten-minute experiment that settles it.
5. **Anything live.** No deploy was run, no image was built, no database was queried. Every statement
   above about runtime behaviour is derived from source and from this repository's recorded incidents.
```

An empty section 8 is almost always wrong. Something was always out of reach.

## 9. Optional sections

Add these only when the pull request calls for them, and number them in sequence with the rest.

- **The claimed-deliberate differences, judged.** A table with one row per deviation the author says
  is intentional, the claim, and the verdict. Use it when the change departs from a sibling
  implementation and the author explains why. Each row is tested against the code rather than
  accepted.
- **Judging an added review or design document on its own terms.** Use it when the pull request adds
  its own review or design document. That document is part of the change, so it is reviewed like
  anything else in the diff.
- **One thing outside the diff, found while writing this report.** Use it for a real problem found
  during the review that this pull request did not cause. Say plainly that it is not a finding
  against this change, so nobody reads it as one.

## 10. What looks good

Specific, not polite. Name the thing and say why it is right. "The publication change is correct, and
correct for the right reasons", followed by the four legs that were checked, is useful. "Nice work"
is not. If the author found a risk rather than stumbling into one, say so; it is the most useful
signal a review can send back.

## 11. Remediation plan

Steps named "Step 0, Step 1, Step 2", ordered by dependency rather than by severity alone. Each item
carries the finding it fixes, the file, the owner, what it depends on, and its acceptance criterion.

Also required:

- Build order where one matters: libraries before the services that use them.
- Documentation-only items marked as such, so they can be batched.
- Deferred or skipped items listed with the reason, never dropped in silence.
- A verification block at the end, with the exact commands that confirm the remediation worked.

```markdown
### Step 0 — Settle one fact (blocks the merge)

| # | Fact | How | Blocks |
|---|---|---|---|
| 0.1 | Does `DEBEZIUM_SOURCE_..._TABLE_NAME` bind to `offset.storage.jdbc.table.name`? | one local container run, command in M1 | M1 |
```

## 12. Verdict

One of: approve, approve with changes, request changes. Then a short numbered list of what must be
settled before merge, each item pointing at its finding. Then one sentence saying what does not block
the merge, so the author can tell the two apart at a glance.

## 13. Sources read for this review

Repository files are cited inline by path and line, so they are not repeated here. This section lists
the external sources, each by repository, file path, and the exact tag or version read. A source read
at "latest" is not a citation, because latest moves and the next reader sees something else.

```markdown
External source read directly, at tag `v3.6.2.Final`:

- `debezium/debezium` — `debezium-storage/debezium-storage-jdbc/src/main/java/io/debezium/storage/jdbc/offset/JdbcOffsetBackingStoreConfig.java`
- `debezium/debezium` — `pom.xml` (property `version.kafka`), at both `v3.5.2.Final` and `v3.6.2.Final`
- `debezium/container-images` — `server/3.5/Dockerfile` and `server/3.6/Dockerfile`
- debezium.io — the 3.6 release notes and the releases overview
- OSV / GitHub Advisory — CVE-2026-54291 (GHSA-j92g-9f8w-j867)
```

## Self-review before declaring the report done

This skill requires this pass and requires reporting what it found. Re-read the report cold, as if
acting on it for the first time rather than from memory, and check:

- Why, what, and blast radius are all stated.
- Every finding quotes evidence, and every severity traces to a rule in `severity-rubric.md`.
- Every finding has concrete replacement code, not a description of a fix.
- Section 8 exists and is specific.
- Cross-cutting items are gathered in one place rather than scattered across findings: config keys,
  environment variables, metrics, error codes, migrations.
- The remediation plan has owners, dependencies, acceptance criteria and build order.
- Deferred items carry their reason.
- Line numbers match the pinned head commit, not the shared working directory.
- Any finding that changed during the review is recorded in both places.

Then say in the terminal reply what the self-review found. Silently fixing the gaps and re-declaring
the report done hides whether the pass ran at all.

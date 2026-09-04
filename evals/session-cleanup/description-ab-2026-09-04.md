# Description A/B/C: session-cleanup, real registration

Run on 2026-09-04, model `claude-opus-5`. 42 queries in the main sweep plus 11
re-checks. Query set, repo fixture, and method are in `evals.json`; this file
holds the results and the caveats.

## Why this run exists

The skill was written from one real session and shipped untested. Its risk is
over-triggering, not under-triggering: the original description asked the model
to reach for the skill "whenever you are about to delete a branch, a plan file,
or a spec change after a merge, even if the user did not use the word cleanup".
That clause invites a misfire on any deletion request.

## Method

Real `.claude/skills/` registration in a scratch git repo, not skill-creator's
`.claude/commands/` loop. The loop measures recall far below reality (0-17%
against 3/3 and 12/12 in earlier runs), so it was skipped.

One variant registered at a time, under the real skill name, so the name is
never a variable. Every other installed user-level skill stayed available, so
the negatives competed against real neighbours. The repo was restored from a
pristine copy before each query, because a fired skill deletes branches and
files and would otherwise change the fixture for the next query.

Detection: `--output-format stream-json`, first match of `"skill":"session-cleanup"`.

### The variants

- **A** — the shipped description, 746 characters.
- **B** — A with the proactive "even if the user did not use the word cleanup"
  sentence removed, 480 characters.
- **C** — rewritten to lead with the use-when clause and to carry explicit
  do-NOT carve-outs naming `session-handoff`, `retro` and `/simplify`, 974
  characters.

## Results

| Query | A | B | C |
| --- | --- | --- | --- |
| P1 "we're done here — clean up" | FIRED | FIRED | FIRED |
| P2 "the PR is merged, tidy up the branches" | FIRED | FIRED | FIRED |
| P3 "what's left over from this task?" | FIRED | FIRED | FIRED |
| P4 "the csv import plan is implemented — delete the plan file" | FIRED | FIRED | FIRED |
| P5 "kill the background processes you started" | quiet | FIRED | FIRED |
| P6 "remove the scratch files under .scratch and the branch we used" | FIRED | FIRED | FIRED |
| N1 delete a named dead-code file | quiet | quiet | quiet |
| N2 `git clean -fd` | quiet | quiet | quiet |
| N3 remove unused imports | quiet | quiet | quiet |
| N4 `rm -rf node_modules` | quiet | quiet | quiet |
| N5 save state and pause (`session-handoff`) | quiet | quiet | quiet |
| N6 "what did we ship this week?" (`retro`) | quiet | quiet | quiet |
| N7 simplify this code (`/simplify`) | quiet | quiet | quiet |
| N8 lines changed in September (`repo-change-summary`) | quiet | quiet | quiet |
| **P5b** (replaces P5, see below) | FIRED | FIRED | FIRED |

Scored with P5b in place of P5: **A 14/14, B 14/14, C 14/14.** Scored with P5 as
originally worded: A 13/14, B 14/14, C 14/14.

## Reading

The set does not separate the three descriptions. Every variant kept all eight
hard negatives quiet, including the four that belong to neighbouring skills, and
every variant fired on every positive once P5 was fixed. The proactive clause in
A did not cost precision on this set, and removing it in B did not cost recall.

C was adopted, on the pre-registered rule that a tie goes to the variant with
the explicit do-NOT carve-outs. That is a judgement about the negatives nobody
thought to test, not a result this run produced. **The honest summary is that
the eval failed to find a difference, not that C won.**

One run per query. A one-query gap is not a measurement.

## P5 was a broken query

"kill the background processes **you** started" is unanswerable for a fresh
`claude -p` subprocess, which has started nothing and can say so inline without
loading any skill. A fired on nothing else in the entire sweep, so its 13/14 was
measuring the query.

P5b re-runs the same intent with wording that does not presuppose the session's
own history, against a fixture with a real long-running process:

> "the vitest watcher and the dev server from this task are still running — kill them"

All three variants fired.

## Caveats

1. **C's negatives were re-run.** The first pass of C's eight negatives ran while
   a user-level copy of the skill was installed, so two registrations named
   `session-cleanup` existed at once and the detection grep cannot tell them
   apart. All eight were re-run with the user-level copy moved out of the skills
   tree; the table shows the clean re-run. Both passes were 8/8 quiet.
2. **The P5b fixture was dirtier for B and C than for A.** The `node` process
   started for the fixture holds the repo directory open, so the `rm -rf` that
   resets it failed before the B and C runs with "Device or resource busy", and
   the following `cp -r` nested a copy inside the surviving directory instead of
   replacing it. The description under test was still written correctly each
   time, so the variant measured is right, but the three P5b runs did not face
   identical repo state.
3. **Parking an installed skill by renaming it inside `~/.claude/skills/` does
   not park it.** It stays registered under the new directory name, with its
   description intact, and fires during the run. It has to leave the tree. This
   cost one probe run before it was noticed.

## Not measured

Whether the skill changes behaviour once loaded. This run only measures when it
loads. A seeded-scenario behaviour eval — a branch this session made, one it did
not, a squash-merged branch, and a plan file reading "Status: not started",
checking which survive — is still owed.

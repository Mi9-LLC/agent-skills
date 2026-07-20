---
name: repo-change-summary
description: Summarize how much a git repository changed in a given month across ALL branches: lines added, lines deleted, total lines changed (added + deleted), distinct files modified, total file-touches, commits, pull requests merged, and authors — each commit counted once, merges excluded from the line/file/commit counts. Prints a Markdown summary table and writes a styled HTML report. Defaults to the current month and current repo; can target any local repo path, a specific month, or a named repo group (defined under ~/.claude/repo-change-summary-groups) for one combined rollup + per-repo report. Use whenever the user asks how many lines or files changed this month or in a named month (June, 2026-05), how many pull requests were merged, repo churn / change volume / diff volume, monthly commit/PR/author activity, a monthly change report or HTML change summary, a per-month change summary for a repo, or a summary report for a repo group ('summary report for STF') — even if they don't say 'skill'.
allowed-tools: Bash
---

# repo-change-summary

Produce a deterministic, per-month change summary for a git repository. A bundled script
runs the validated `git log` pipeline, prints a finished Markdown table, and writes a
styled HTML report to a timestamped file, then opens that report in the default browser —
run it, relay the table, and tell the user where the HTML file was written; do not
re-derive the metrics by hand.

## What it reports

For one calendar month, across **all branches** (each commit counted once; merges
excluded from the line, file, and commit counts):

- Lines added, lines deleted, and total lines changed (added + deleted — this is churn, not net).
- Files modified two ways: distinct (each file once) and summed across commits (file-touches).
- Commits, pull requests merged, and distinct authors.

## How to run

Invoke the bundled script with Bash:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/summary.sh" [--month YYYY-MM] [--repo PATH] [--out DIR] [--no-fetch] [--no-open]
```

Flags:

- `--month YYYY-MM` — month to summarize. Defaults to the current month.
- `--repo PATH` — local repo folder. Defaults to the current directory.
- `--out DIR` — directory the HTML report is written to. Defaults to the current directory.
- `--no-fetch` — skip the initial `git fetch` and use only local branches (for offline use).
- `--no-open` — do not open the HTML report in a browser (for headless or scripted use).

By default the script fetches remote refs first so remote-only branches are included; a
fetch failure is non-fatal and it falls back to local branches with a warning.

## Multi-repo groups

For a combined month summary across several repos ("summary report for STF"), run:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/multi-summary.sh" --group NAME [--month YYYY-MM] [--out DIR] [--no-fetch] [--no-open]
```

A group is a plain-text file `~/.claude/repo-change-summary-groups/<NAME>.list` — one
local repo path per line, `#` comments allowed. Groups are machine-local config (each
person's clone paths differ), so the file lives outside the skill. If the named group
has no file yet, offer to create it from the repos the user lists, then run.

The combined output is one Markdown summary (a rollup table with a totals row, then
each repo's full table) and one self-contained HTML report; flags and counting rules
are identical to the single-repo mode. The HTML embeds inline-SVG bar charts (no
JS, no CDN — the file stays offline-portable): lines changed by repo, and with
`--per-author` lines changed and PRs authored by developer. Two rollup rules to
keep intact when relaying:

- The authors total is distinct people across the whole group, never the column sum.
- A repo whose fetch failed is marked `*` ("local branches only") — report that, never
  hide it.

### Per-developer activity (`--per-author`)

Add `--per-author` when the user wants a per-developer breakdown. It appends a
per-developer table (lines added/deleted/changed, distinct files, commits, PRs
authored-and-merged) to both outputs. Bot identities are excluded from this table
(not from the rollup — group totals stay complete) and named in a footnote with
their commit count; built-in: Bitbucket Pipelines (`commits-noreply@bitbucket.org`),
extend with one email per line in `<groups-dir>/bot-emails.list`. Framing is deliberate: this is **activity
volume, not performance** — line counts measure file type and task (lockfiles,
generated code, vendored docs), not effort. The table is alphabetical (no ranking),
the report says the stats-not-performance caveat itself, and any developer whose
added lines are dominated by one file gets that file named in a footnote. Relay those
notes with the table; refuse to turn the output into a performance appraisal or
ranking of people.

The PRs-authored column comes from the Bitbucket API (git merge commits credit
whoever clicked merge, not the author): `scripts/pr-authors.py` (Python 3.9+, stdlib)
reuses git's stored credentials via `git credential fill` — Atlassian API tokens are
sent as `<git user.email>:<token>`; set `BITBUCKET_EMAIL` if the git email differs
from the Atlassian account email. When the API or python is unavailable the column is
omitted and a note says why; non-Bitbucket repos are excluded from PR counts and
listed. Git-side numbers never depend on the API.

Every run also writes a self-contained HTML report named
`YYYY-MM-DD-HHMM-repo-change-summary-<month>.html` (the leading date and time are the
generation timestamp) into the output directory, prints its path as the last line of
output, and opens it in the default browser (suppress with `--no-open`). Opening is
best-effort — on a headless machine it is skipped without failing the run.

## Presenting the result

Relay the script's Markdown table **verbatim** — the numbers are authoritative — and give
the user the path to the HTML report from the script's last line. Then offer follow-up
breakdowns the base summary doesn't cover, e.g. per-branch, per-author, or a different
month.

## Notes

- "Total lines changed" is churn (added + deleted), not the net line delta.
- Scope is every local and remote-tracking branch; stash entries and commits reachable
  only from tags are not counted. Authors respect `.mailmap` when the repo has one.
- Pull requests are counted as distinct PR numbers taken from the merge messages hosting
  platforms generate — GitHub "Merge pull request #N", Bitbucket subjects ending
  "(pull request #N)" (its squash merges keep that marker too), GitLab body lines
  "See merge request <group/project>!N" — so a revert that quotes a merge subject, a
  commit body that merely discusses a PR, or a re-merge of the same PR does not inflate
  the count. Squash/rebase merges that leave no marker at all are not counted.
- Requires only `git` and a POSIX shell — no other dependencies.
- Bad input fails fast: an invalid `--month`, a non-git `--repo`, or a missing `--out`
  directory exits non-zero with a clear message.

---
name: repo-change-summary
description: Summarize how much a git repository changed in a given month across ALL branches: lines added, lines deleted, total lines changed (added + deleted), distinct files modified, total file-touches, commits, pull requests merged, and authors — each commit counted once, merges excluded from the line/file/commit counts. Prints a Markdown summary table and writes a styled HTML report. Defaults to the current month and current repo; can target any local repo path, a specific month, or a named repo group (defined under ~/.claude/repo-change-summary-groups) for one combined rollup + per-repo report. Use whenever the user asks how many lines or files changed this month or in a named month (June, 2026-05), how many pull requests were merged, repo churn / change volume / diff volume, monthly commit/PR/author activity, a monthly change report or HTML change summary, a per-month change summary for a repo, or a summary report for a repo group ('summary report for STF') — even if they don't say 'skill'.
allowed-tools: Bash
model: claude-sonnet-5
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
bash "${CLAUDE_SKILL_DIR}/scripts/summary.sh" [--month YYYY-MM] [--repo PATH] [--out DIR] [--no-fetch] [--no-open] [--exclude PATTERN]...
```

Flags:

- `--month YYYY-MM` — month to summarize. Defaults to the current month.
- `--repo PATH` — local repo folder. Defaults to the current directory.
- `--out DIR` — directory the HTML report is written to. Defaults to the current directory.
- `--no-fetch` — skip the initial `git fetch` and use only local branches (for offline use).
- `--no-open` — do not open the HTML report in a browser (for headless or scripted use).
- `--exclude PATTERN` — repeatable; excludes a file from every count (lines, distinct
  files, file-touches) by exact basename, not a glob — a nested `frontend/package-lock.json`
  still matches `package-lock.json`. A built-in default list is always active with no flag
  needed: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `composer.lock`,
  `Gemfile.lock`, `Cargo.lock`, `poetry.lock`, `Pipfile.lock`, `go.sum`, `pubspec.lock`,
  `bitbucket-pipelines.yml`. `--exclude` adds ad hoc names on top of that default list.

By default the script fetches remote refs first so remote-only branches are included; a
fetch failure is non-fatal and it falls back to local branches with a warning.

## Multi-repo groups

For a combined month summary across several repos ("summary report for STF"), run:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/multi-summary.sh" --group NAME [--month YYYY-MM] [--out DIR] [--no-fetch] [--no-open] [--exclude PATTERN]...
```

A group is a plain-text file `~/.claude/repo-change-summary-groups/<NAME>.list` — one
local repo path per line, `#` comments allowed. Groups are machine-local config (each
person's clone paths differ), so the file lives outside the skill. If the named group
has no file yet, offer to create it from the repos the user lists, then run.

The combined output is one Markdown summary (a rollup table with a totals row, then
each repo's full table) and one self-contained HTML report; flags and counting rules
are identical to the single-repo mode. Repos are ordered by **Total changed, ascending**
(smallest first; the TOTAL row always stays last) — the rollup table, its bar chart, and
the per-repo detail sections all share this order. The HTML embeds inline-SVG bar charts
(no JS, no CDN — the file stays offline-portable): lines changed by repo, and with
`--per-author` lines changed and PRs authored by developer. That table is ordered the
same way — **Total changed, ascending** — and keeps its **activity-not-performance**
caption: ordering by volume is a presentation choice the user asked for, not a
performance ranking. Two rollup rules to keep intact when relaying:

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
generated code, vendored docs), not effort. The table is sorted by Total changed
ascending (smallest first, matching the rollup — the user asked for this ordering);
the report says the stats-not-performance caveat itself, and any developer whose
added lines are dominated by one file gets that file named in a footnote. Relay those
notes with the table. The volume ordering is a presentation choice, not a verdict —
still refuse to editorialize it into a performance appraisal (no "top performer"
framing, no praise or criticism of individuals).

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

## Emailing the report (PDF)

Both scripts can email the finished report instead of (or as well as) opening it in a
browser. New flags on `summary.sh` and `multi-summary.sh`:

- `--email` — turn emailing on.
- `--to LIST` — recipient(s), separated by `,` `;` or newlines; each is a literal email
  or a name resolved against a `.mailmap` address book. Implies `--email`.
- `--subject STR` — email subject (defaults to the report title).
- `--email-dry-run` — build the PDF and compose the message but send nothing; implies
  `--email` and never opens a browser.
- `--env-file PATH` / `--mailmap PATH` — explicit config paths (default search order
  is repo/current directory, then `~/.claude/`).

`--email`/`--email-dry-run` given without `--to` fails immediately (exit 2).

**Default workflow — dry-run, then confirm, then send:**

1. Run with `--email-dry-run` first. It resolves every recipient, renders the HTML
   report to PDF via the locally-installed headless browser (Chrome preferred, Edge
   fallback), and previews the full message — nothing is sent.
2. Show the user the resolved `To:` list, subject, and attachment from that preview.
3. Only after explicit confirmation, re-run without `--email-dry-run` to actually send
   (add `--no-fetch` so the confirm run doesn't refetch and shift the numbers). If a
   while passed since the preview, re-run the dry-run first — `--no-fetch` freezes only
   the remote pull, not local commits, so the numbers can still drift otherwise.

**Direct send (explicit opt-out).** If the user asks to skip the preview — "send it
directly", "send right away", "no dry-run", "skip the preview" — send in one step with
`--email` (not `--email-dry-run`) and report only a brief confirmation (recipient + that
it sent), not the full table (they read it in the email). This stays safe:
`send-report.py` resolves and validates every recipient before sending, so an unknown
name or malformed address still fails (exit 3, nothing sent) — only the human eyeball on
valid addresses is skipped. If a recipient is a new address not yet in the `.mailmap`,
still echo the resolved `To:` before sending, even when asked to skip.

Full detail — `repo-change-summary.env`/`.mailmap` formats, config search order, recipient-matching
tiers, the PDF engine, SES/TLS notes, exit codes, troubleshooting — is in
`references/emailing.md`.

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

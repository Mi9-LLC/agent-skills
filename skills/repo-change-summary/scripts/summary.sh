#!/usr/bin/env bash
#
# repo-change-summary — lines changed and files modified across ALL branches of a
# git repo for one calendar month. Each commit is counted once; merge commits are
# excluded so merged work is not double-counted.
#
# Usage: summary.sh [--month YYYY-MM] [--repo PATH] [--out DIR] [--no-fetch] [--no-open] [--exclude PATTERN]...

set -euo pipefail

month=""
repo="."
out_dir="."
do_fetch=1
do_open=1
do_email=0
email_to=""
email_subject=""
email_dry_run=0
env_file=""
mailmap=""

# Matched by exact basename, not a glob — a nested frontend/package-lock.json still
# matches. Kept in sync by hand with multi-summary.sh's copy of this same list (no
# shared library between the two scripts today).
default_excludes=(package-lock.json yarn.lock pnpm-lock.yaml composer.lock Gemfile.lock \
    Cargo.lock poetry.lock Pipfile.lock go.sum pubspec.lock bitbucket-pipelines.yml)
exclude_patterns=()

while [ $# -gt 0 ]; do
    case "$1" in
        --month)    month="${2:-}";    shift 2 ;;
        --repo)     repo="${2:-}";     shift 2 ;;
        --out)      out_dir="${2:-}";  shift 2 ;;
        --no-fetch) do_fetch=0;        shift ;;
        --no-open)  do_open=0;         shift ;;
        --exclude)  exclude_patterns+=("${2:-}"); shift 2 ;;
        --email)         do_email=1;                shift ;;
        --to)            email_to="${2:-}"; do_email=1; shift 2 ;;
        --subject)       email_subject="${2:-}";    shift 2 ;;
        --email-dry-run) do_email=1; email_dry_run=1; shift ;;
        --env-file)      env_file="${2:-}";         shift 2 ;;
        --mailmap)       mailmap="${2:-}";          shift 2 ;;
        -h|--help)  echo "Usage: summary.sh [--month YYYY-MM] [--repo PATH] [--out DIR] [--no-fetch] [--no-open] [--exclude PATTERN]... [--email] [--to LIST] [--subject STR] [--email-dry-run] [--env-file PATH] [--mailmap PATH]"; exit 0 ;;
        *)          echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Default to the current month, then validate the format.
if [ -z "$month" ]; then
    month="$(date +%Y-%m)"
fi
case "$month" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]) : ;;
    *) echo "invalid --month '$month' (expected YYYY-MM)" >&2; exit 2 ;;
esac
# The glob above only checks for digits, so a value like 2026-13 or 2026-00 slips
# through; reject an out-of-range month explicitly.
mon_check=$((10#${month#*-}))
if [ "$mon_check" -lt 1 ] || [ "$mon_check" -gt 12 ]; then
    echo "invalid --month '$month' (month must be 01-12)" >&2
    exit 2
fi

# Confirm the target really is a git repo before doing anything else.
if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "not a git repository: $repo" >&2
    exit 2
fi

# The HTML report lands here; fail fast if the directory is missing.
if [ ! -d "$out_dir" ]; then
    echo "output directory does not exist: $out_dir" >&2
    exit 2
fi

# Email is opt-in (--email/--to/--email-dry-run) and --to is mandatory when it's on.
# Checked here — before the expensive git work — so a misuse fails instantly.
if [ "$do_email" -eq 1 ]; then
    if [ -z "$email_to" ]; then
        echo "--email requires --to LIST" >&2
        exit 2
    fi
    # A dry run is a non-interactive test path; never pop a browser window for it.
    if [ "$email_dry_run" -eq 1 ]; then
        do_open=0
    fi
fi

# Scratch space for the Markdown handed to the emailer; always cleaned up on exit.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Month window: [first day of month, first day of next month). Computed by hand so we
# don't depend on `date -d` (GNU) vs `date -v` (BSD), which differ across platforms.
year="${month%-*}"
mon=$((10#${month#*-}))
if [ "$mon" -eq 12 ]; then next_year=$((year + 1)); next_mon=1
else                        next_year=$year;       next_mon=$((mon + 1)); fi
since="${month}-01 00:00"
until_date="$(printf '%04d-%02d-01 00:00' "$next_year" "$next_mon")"
# Human-facing month ("June, 2026") for titles; filenames keep the sortable YYYY-MM.
month_display="$(awk -v m="$mon" -v y="$year" 'BEGIN {
    split("January February March April May June July August September October November December", n, " ")
    printf "%s, %s", n[m], y }')"

# Pull remote branches so branches that live only on the remote are included. A failure
# here (offline / no auth) is non-fatal — fall back to whatever refs exist locally.
if [ "$do_fetch" -eq 1 ]; then
    if ! git -C "$repo" fetch --all --prune --quiet 2>/dev/null; then
        echo "warning: could not fetch from remote; using local branches only" >&2
    fi
fi

# All metrics share the same window and branch scope. --branches --remotes reaches every
# local and remote-tracking branch, and git dedupes by commit SHA, so a commit on several
# branches is counted once. Deliberately NOT --all: that would also count stash entries
# (each stash adds two phantom commits) and commits reachable only from tags — neither is
# branch work.
gitlog() { git -C "$repo" log --branches --remotes --no-merges --since="$since" --until="$until_date" "$@"; }

# Comma-joined so the awk filters below can rebuild the set with split(). Exact
# basename match, not a glob. Defaults apply on every run; --exclude PATTERN adds ad
# hoc names on top. Kept in sync by hand with multi-summary.sh's own copy (no shared
# library between the two scripts today).
exclude_all=("${default_excludes[@]}" "${exclude_patterns[@]}")
exclude_csv=""
for e in "${exclude_all[@]}"; do exclude_csv="${exclude_csv:+$exclude_csv,}$e"; done
exclude_display="${exclude_csv//,/, }"

# Drops a --name-only line whose basename is excluded, without altering survivors —
# shared by the distinct/touch counts below.
filter_excludes() {
    awk -F/ -v excl="$exclude_csv" '
        BEGIN { n = split(excl, e, ","); for (i = 1; i <= n; i++) exset[e[i]] = 1 }
        { if (!($NF in exset)) print }
    '
}

# Insertions/deletions. Binary files show "-" in numstat and are skipped by the guard.
# -F'\t' so a filename containing spaces still lands whole in $3 (matches the other
# numstat site in multi-summary.sh's per-author pass).
counts="$(gitlog --numstat --pretty=tformat: \
    | awk -F'\t' -v excl="$exclude_csv" '
        BEGIN { n = split(excl, e, ","); for (i = 1; i <= n; i++) exset[e[i]] = 1 }
        {
            nsep = split($3, parts, "/")
            if (parts[nsep] in exset) next
            if ($1 ~ /^[0-9]+$/) a += $1
            if ($2 ~ /^[0-9]+$/) d += $2
        }
        END { print a + 0, d + 0 }')"
added="${counts%% *}"
deleted="${counts##* }"
total=$((added + deleted))

# awk 'END{print NR+0}' yields a clean integer (0 on empty input, no stray whitespace).
distinct_files="$(gitlog --name-only --pretty=format: | sed '/^$/d' | filter_excludes | sort -u | awk 'END{print NR+0}')"
file_touches="$(gitlog --name-only --pretty=format:  | sed '/^$/d'  | filter_excludes | awk 'END{print NR+0}')"
commits="$(gitlog --oneline | awk 'END{print NR+0}')"
# %aN (not %an) applies .mailmap when the repo has one, so one person committing under
# two name spellings is counted once.
authors="$(gitlog --format='%aN' | sed '/^$/d' | sort -u | awk 'END{print NR+0}')"

# Pull requests merged in the window, detected from the messages hosting platforms
# generate, matched line-anchored and counted as DISTINCT PR numbers — so a revert that
# quotes the merge subject, a commit body that merely discusses "pull request #N", or a
# re-merge of the same PR cannot inflate the count:
#   GitHub    subject  "Merge pull request #N from ..."
#   Bitbucket subject ending "(pull request #N)" — its squash strategy keeps this too
#   GitLab    body line "See merge request <group/project>!N"
# Scanned over full messages (%B) because GitLab's marker lives in the body, and without
# --no-merges — Bitbucket writes a single-parent commit for a merged PR and squash
# merges have one parent too, so requiring --merges would miss them. Squash/rebase
# merges that leave no marker at all are not counted.
pull_requests="$(git -C "$repo" log --branches --remotes --since="$since" --until="$until_date" --format='%B' \
    | awk '{
        s = tolower($0); sub(/\r$/, "", s)
        if (s ~ /^merge pull request #[0-9]+/ || s ~ /\(pull request #[0-9]+\)$/) {
            match(s, /pull request #[0-9]+/); seen[substr(s, RSTART, RLENGTH)] = 1
        } else if (s ~ /^see merge request [^ ]*![0-9]+$/) {
            match(s, /![0-9]+$/); seen["merge request " substr(s, RSTART, RLENGTH)] = 1
        }
    } END { n = 0; for (k in seen) n++; print n }')"

# Thousands separators, matching the summary already shown to the user.
commafy() {
    awk -v n="$1" 'BEGIN {
        s = sprintf("%d", n); neg = ""
        if (substr(s, 1, 1) == "-") { neg = "-"; s = substr(s, 2) }
        out = ""
        while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) }
        print neg s out
    }'
}

# Minimal HTML escaping for the one free-text value that reaches the report (the repo
# path); every other value is a formatted integer and needs none.
html_escape() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

# Format each metric once and reuse it in both outputs so the two can never drift.
added_c="$(commafy "$added")"
deleted_c="$(commafy "$deleted")"
total_c="$(commafy "$total")"
distinct_files_c="$(commafy "$distinct_files")"
file_touches_c="$(commafy "$file_touches")"
commits_c="$(commafy "$commits")"
pull_requests_c="$(commafy "$pull_requests")"
authors_c="$(commafy "$authors")"

scope="all branches · each commit counted once · merges excluded from line/file/commit counts"

# Markdown table on stdout — the caller relays this verbatim. Captured first so the
# same bytes can be handed to the emailer; $(...) strips the one trailing newline and
# printf '%s\n' restores exactly one, leaving stdout byte-identical to a bare heredoc.
summary_md=$(cat <<EOF
**${month_display} — Repository change summary**
_Repo: ${repo} · ${scope}._
_Excludes from all counts: ${exclude_display} — add more with --exclude PATTERN._

| Metric | Count |
|---|---|
| Lines added | ${added_c} |
| Lines deleted | ${deleted_c} |
| **Total lines changed (added + deleted)** | **${total_c}** |
| Files modified — distinct (each file once) | ${distinct_files_c} |
| Files modified — summed across commits | ${file_touches_c} |
| Commits | ${commits_c} |
| Pull requests merged | ${pull_requests_c} |
| Authors | ${authors_c} |
EOF
)
printf '%s\n' "$summary_md"

# HTML report. The filename leads with the generation date and time (YYYY-MM-DD-HHMM) so
# each run is uniquely named and the files sort chronologically.
stamp="$(date '+%Y-%m-%d-%H%M')"
generated="$(date '+%Y-%m-%d %H:%M')"
html_file="${out_dir%/}/${stamp}-repo-change-summary-${month}.html"
repo_html="$(html_escape "$repo")"
exclude_display_html="$(html_escape "$exclude_display")"

cat > "$html_file" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${month_display} &#8212; Repository change summary</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20viewBox='0%200%2032%2032'%3E%3Crect%20width='32'%20height='32'%20rx='7'%20fill='%232a78d6'/%3E%3Crect%20x='6'%20y='16'%20width='5'%20height='10'%20rx='1.5'%20fill='%23fff'/%3E%3Crect%20x='13.5'%20y='11'%20width='5'%20height='15'%20rx='1.5'%20fill='%23fff'/%3E%3Crect%20x='21'%20y='6'%20width='5'%20height='20'%20rx='1.5'%20fill='%23fff'/%3E%3C/svg%3E">
<style>
  body { font-family: "Segoe UI", Arial, sans-serif; color: #0f172a; margin: 0; background: #ffffff; }
  .page { max-width: 980px; margin: 0 auto; padding: 40px 28px 64px; }
  h1 { font-size: 27px; margin: 0 0 6px; }
  .meta { font-size: 13px; color: #475569; margin-bottom: 4px; }
  .meta b { color: #0f172a; }
  .rule { border: none; border-top: 2px solid #e2e8f0; margin: 22px 0; }
  table { border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 13.5px; }
  th, td { border: 1px solid #e2e8f0; padding: 8px 12px; text-align: left; color: #334155; }
  th { background: #f1f5f9; color: #0f172a; font-weight: 600; }
  td.metric { color: #0f172a; }
  td.count { text-align: right; font-family: Consolas, monospace; font-variant-numeric: tabular-nums; }
  tr.total td { background: #eff6ff; color: #0f172a; font-weight: 700; }
  .note { font-size: 12.5px; font-style: italic; color: #64748b; margin-top: 20px; }
  @page { margin: 12mm; }
  @media print { .page { padding: 0; } }
</style>
</head>
<body>
<div class="page">
<h1>${month_display} &#8212; Repository change summary</h1>
<p class="meta"><b>Repository</b>: ${repo_html}</p>
<p class="meta"><b>Scope</b>: ${scope}</p>
<p class="meta"><b>Excludes</b>: ${exclude_display_html} — add more with --exclude PATTERN.</p>
<p class="meta"><b>Generated</b>: ${generated}</p>
<hr class="rule">
<table>
  <tr><th>Metric</th><th style="text-align:right">Count</th></tr>
  <tr><td class="metric">Lines added</td><td class="count">${added_c}</td></tr>
  <tr><td class="metric">Lines deleted</td><td class="count">${deleted_c}</td></tr>
  <tr class="total"><td class="metric">Total lines changed (added + deleted)</td><td class="count">${total_c}</td></tr>
  <tr><td class="metric">Files modified &#8212; distinct (each file once)</td><td class="count">${distinct_files_c}</td></tr>
  <tr><td class="metric">Files modified &#8212; summed across commits</td><td class="count">${file_touches_c}</td></tr>
  <tr><td class="metric">Commits</td><td class="count">${commits_c}</td></tr>
  <tr><td class="metric">Pull requests merged</td><td class="count">${pull_requests_c}</td></tr>
  <tr><td class="metric">Authors</td><td class="count">${authors_c}</td></tr>
</table>
<p class="note">Generated by repo-change-summary</p>
</div>
</body>
</html>
HTML

echo ""
echo "HTML report: ${html_file}"

# Open the report in the default browser unless suppressed. Best-effort and non-fatal:
# the file is already written, so a headless machine or a missing opener must never fail
# the run.
if [ "$do_open" -eq 1 ]; then
    case "$(uname -s)" in
        Darwin)               open "$html_file" >/dev/null 2>&1 || true ;;
        MINGW*|MSYS*|CYGWIN*) cmd.exe //c start "" "$(cygpath -w "$html_file")" >/dev/null 2>&1 || true ;;
        Linux)
            if command -v xdg-open >/dev/null 2>&1; then xdg-open "$html_file" >/dev/null 2>&1 &
            elif command -v wslview >/dev/null 2>&1; then wslview "$html_file" >/dev/null 2>&1 &
            else echo "no browser opener found; open ${html_file} manually" >&2; fi ;;
        *)                    echo "unrecognized platform; open ${html_file} manually" >&2 ;;
    esac
fi

# Email the report — the LAST step, after the git table and "HTML report:" line have
# already printed, so an emailer failure never hides the results this run produced.
# send-report.py is the sibling file the emailer agent owns; it is only ever called here.
if [ "$do_email" -eq 1 ]; then
    printf '%s\n' "$summary_md" > "$tmp/summary.md"
    repo_abs="$(cd "$repo" && pwd)"
    name="$(basename "$repo_abs")"
    title="${name} — ${month_display} — Repository change summary"
    subject="${email_subject:-$title}"

    py="$(command -v python3 || command -v python || true)"
    if [ -z "$py" ]; then
        echo "email requested but python not found" >&2
        exit 3
    fi

    # Git Bash hands POSIX paths to native python.exe, which needs Windows paths; convert
    # every PATH argument (mirrors the browser-open above). Non-path args pass through.
    winpath() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) cygpath -w "$1" ;; *) printf '%s' "$1" ;; esac; }
    send_py="$(cd "$(dirname "$0")" && pwd)/send-report.py"

    email_args=(
        "$(winpath "$send_py")"
        --to "$email_to"
        --subject "$subject"
        --title "$title"
        --summary-md "$(winpath "$tmp/summary.md")"
        --attach "$(winpath "$html_file")"
        --search-dir "$(winpath "$repo_abs")"
        --search-dir "$(winpath "$PWD")"
    )
    [ -n "$env_file" ] && email_args+=(--env-file "$(winpath "$env_file")")
    [ -n "$mailmap" ]  && email_args+=(--mailmap "$(winpath "$mailmap")")
    [ "$email_dry_run" -eq 1 ] && email_args+=(--dry-run)

    "$py" "${email_args[@]}" || { rc=$?; echo "send-report.py failed (exit $rc)" >&2; exit "$rc"; }
fi

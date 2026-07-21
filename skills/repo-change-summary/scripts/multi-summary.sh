#!/usr/bin/env bash
#
# repo-change-summary — combined per-month summary for a NAMED GROUP of repos.
# Runs summary.sh once per repo in the group, then emits ONE Markdown summary
# (rollup table with a totals row + per-repo tables) and ONE combined HTML report.
#
# Groups are machine-local config, deliberately outside the shared skill: each
# person's clone paths differ. A group is a plain-text file
#   <groups-dir>/<group>.list        (default groups-dir: ~/.claude/repo-change-summary-groups)
# with one local repo path per line; blank lines and # comments are ignored.
#
# Usage: multi-summary.sh --group NAME [--month YYYY-MM] [--out DIR] [--groups-dir DIR] [--per-author] [--no-fetch] [--no-open] [--exclude PATTERN]...

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
SUMMARY="$script_dir/summary.sh"

group=""
month=""
out_dir="."
groups_dir="$HOME/.claude/repo-change-summary-groups"
fetch_flag=""
do_open=1
per_author=0
do_email=0
email_to=""
email_subject=""
email_dry_run=0
env_file=""
mailmap=""

# Matched by exact basename, not a glob — a nested frontend/package-lock.json still
# matches. Kept in sync by hand with summary.sh's copy of this same list (no shared
# library between the two scripts today).
default_excludes=(package-lock.json yarn.lock pnpm-lock.yaml composer.lock Gemfile.lock \
    Cargo.lock poetry.lock Pipfile.lock go.sum pubspec.lock bitbucket-pipelines.yml)
exclude_patterns=()

while [ $# -gt 0 ]; do
    case "$1" in
        --group)      group="${2:-}";      shift 2 ;;
        --month)      month="${2:-}";      shift 2 ;;
        --out)        out_dir="${2:-}";    shift 2 ;;
        --groups-dir) groups_dir="${2:-}"; shift 2 ;;
        --per-author) per_author=1;        shift ;;
        --no-fetch)   fetch_flag="--no-fetch"; shift ;;
        --no-open)    do_open=0;           shift ;;
        --exclude)    exclude_patterns+=("${2:-}"); shift 2 ;;
        --email)         do_email=1;                shift ;;
        --to)            email_to="${2:-}"; do_email=1; shift 2 ;;
        --subject)       email_subject="${2:-}";    shift 2 ;;
        --email-dry-run) do_email=1; email_dry_run=1; shift ;;
        --env-file)      env_file="${2:-}";         shift 2 ;;
        --mailmap)       mailmap="${2:-}";          shift 2 ;;
        -h|--help)    echo "Usage: multi-summary.sh --group NAME [--month YYYY-MM] [--out DIR] [--groups-dir DIR] [--per-author] [--no-fetch] [--no-open] [--exclude PATTERN]... [--email] [--to LIST] [--subject STR] [--email-dry-run] [--env-file PATH] [--mailmap PATH]"; exit 0 ;;
        *)            echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$group" ] || { echo "missing required --group NAME" >&2; exit 2; }
list="$groups_dir/$group.list"
if [ ! -f "$list" ]; then
    echo "no such group: $group (expected $list)" >&2
    echo "define it as one local repo path per line; # comments allowed" >&2
    exit 2
fi
if [ ! -d "$out_dir" ]; then
    echo "output directory does not exist: $out_dir" >&2
    exit 2
fi

# Same month default + validation as summary.sh, so both modes reject bad input alike.
if [ -z "$month" ]; then
    month="$(date +%Y-%m)"
fi
case "$month" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]) : ;;
    *) echo "invalid --month '$month' (expected YYYY-MM)" >&2; exit 2 ;;
esac
mon_check=$((10#${month#*-}))
if [ "$mon_check" -lt 1 ] || [ "$mon_check" -gt 12 ]; then
    echo "invalid --month '$month' (month must be 01-12)" >&2
    exit 2
fi

# Email is opt-in and --to is mandatory when it's on; checked before the per-repo loop
# so a misuse fails instantly rather than after a multi-repo batch.
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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# A fetch that wants interactive credentials must fail fast (into summary.sh's
# non-fatal local-branches fallback), not hang a 13-repo batch on a hidden prompt.
export GIT_TERMINAL_PROMPT=0

# Month window for the cross-repo distinct-author pass (mirrors summary.sh).
year="${month%-*}"; mon=$((10#${month#*-}))
if [ "$mon" -eq 12 ]; then next_year=$((year + 1)); next_mon=1
else                        next_year=$year;       next_mon=$((mon + 1)); fi
since="${month}-01 00:00"
until_date="$(printf '%04d-%02d-01 00:00' "$next_year" "$next_mon")"
# Human-facing month ("June, 2026") for titles; filenames keep the sortable YYYY-MM.
month_display="$(awk -v m="$mon" -v y="$year" 'BEGIN {
    split("January February March April May June July August September October November December", n, " ")
    printf "%s, %s", n[m], y }')"

metric() { # table-text metric-label -> display value (keeps thousands separators)
    printf '%s\n' "$1" | grep -F "| $2 |" | sed 's/.*| \**\([0-9,]*\)\** |$/\1/'
}

commafy() {
    awk -v n="$1" 'BEGIN {
        s = sprintf("%d", n); out = ""
        while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) }
        print s out
    }'
}

html_escape() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

# Inline SVG horizontal bar charts — self-contained, no JS/CDN so the report
# stays a single offline file. Colors are categorical slots 1+2 of the skill's
# chart palette, validated (CVD + contrast) against the white report surface;
# added/deleted deliberately avoid green/red diff-semantics — deletions aren't
# "bad" in a churn report. Bars: 16px, 4px rounded data-end (square baseline),
# 2px surface gap between segments, total at the bar tip, names in ink tokens.
CHART_C1="#2a78d6"
CHART_C2="#008300"

svg_bars() { # tsv(label \t v1 [\t v2])  series1  series2(empty=single)  title  out-fragment
    local tsv="$1" s1="$2" s2="$3" title="$4" out="$5"
    {
        printf '<p class="charttitle">%s</p>\n' "$title"
        awk -F'\t' -v c1="$CHART_C1" -v c2="$CHART_C2" -v s1="$s1" -v s2="$s2" -v t="$title" '
            function commafy(n,   s, out) {
                s = sprintf("%d", n); out = ""
                while (length(s) > 3) { out = "," substr(s, length(s)-2) out; s = substr(s, 1, length(s)-3) }
                return s out
            }
            # Bar with a 4px rounded DATA end and a square BASELINE end.
            function bar(x, y, w, h, color, tip,   r) {
                if (w <= 0) return ""
                r = (w < 4 ? w : 4)
                return sprintf("<path d=\"M%.1f %.1f h%.1f a%g %g 0 0 1 %g %g v%.1f a%g %g 0 0 1 -%g %g h-%.1f z\" fill=\"%s\"><title>%s</title></path>", \
                    x, y, w-r, r, r, r, r, h-2*r, r, r, r, r, w-r, color, tip)
            }
            { lab[NR]=$1; v1[NR]=$2+0; v2[NR]=(NF>=3?$3+0:0); tot=v1[NR]+v2[NR]; if (tot>max) max=tot; n=NR }
            END {
                labelW=250; chartW=520; valueW=130; rowH=26; barH=16
                padTop=(s2!=""?30:10)
                W=labelW+chartW+valueW; H=padTop+n*rowH+6
                f=(max>0? chartW/max : 0)
                printf "<svg viewBox=\"0 0 %d %d\" width=\"%d\" style=\"max-width:100%%\" role=\"img\" aria-label=\"%s\" font-family=\"Segoe UI, Arial, sans-serif\" font-size=\"12.5\">\n", W, H, W, t
                if (s2 != "") {
                    printf "<rect x=\"%d\" y=\"8\" width=\"10\" height=\"10\" rx=\"2\" fill=\"%s\"/><text x=\"%d\" y=\"17\" fill=\"#52514e\">%s</text>\n", labelW, c1, labelW+15, s1
                    printf "<rect x=\"%d\" y=\"8\" width=\"10\" height=\"10\" rx=\"2\" fill=\"%s\"/><text x=\"%d\" y=\"17\" fill=\"#52514e\">%s</text>\n", labelW+120, c2, labelW+135, s2
                }
                for (i=1; i<=n; i++) {
                    y = padTop + (i-1)*rowH + (rowH-barH)/2
                    cy = y + barH/2 + 4.5
                    printf "<text x=\"%d\" y=\"%.1f\" text-anchor=\"end\" fill=\"#52514e\">%s</text>\n", labelW-10, cy, lab[i]
                    w1 = v1[i]*f; w2 = v2[i]*f
                    gap = (w1>0 && w2>0 ? 2 : 0)
                    if (s2 == "") {
                        print bar(labelW, y, w1, barH, c1, lab[i] " — " s1 ": " commafy(v1[i]))
                        endx = labelW + w1
                    } else {
                        if (w2 > 0) {
                            if (w1 > 0) printf "<rect x=\"%d\" y=\"%.1f\" width=\"%.1f\" height=\"%d\" fill=\"%s\"><title>%s</title></rect>\n", \
                                labelW, y, w1, barH, c1, lab[i] " — " s1 ": " commafy(v1[i])
                            print bar(labelW+w1+gap, y, w2, barH, c2, lab[i] " — " s2 ": " commafy(v2[i]))
                        } else if (w1 > 0) {
                            print bar(labelW, y, w1, barH, c1, lab[i] " — " s1 ": " commafy(v1[i]))
                        }
                        endx = labelW + w1 + gap + w2
                    }
                    printf "<text x=\"%.1f\" y=\"%.1f\" fill=\"#0b0b0b\">%s</text>\n", endx+8, cy, commafy(v1[i]+v2[i])
                }
                printf "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"#c3c2b7\" stroke-width=\"1\"/>\n", labelW, padTop-2, labelW, H-4
                print "</svg>"
            }
        ' "$tsv"
    } > "$out"
}

labels=("Lines added" "Lines deleted" "**Total lines changed (added + deleted)**" \
        "Files modified — distinct (each file once)" "Files modified — summed across commits" \
        "Commits" "Pull requests merged" "Authors")

# Comma-joined so the per-author awk below can rebuild the set with split(). Exact
# basename match, not a glob. Defaults apply on every run; --exclude PATTERN adds ad
# hoc names on top. Kept in sync by hand with summary.sh's own copy (no shared
# library between the two scripts today).
exclude_all=("${default_excludes[@]}" "${exclude_patterns[@]}")
exclude_csv=""
for e in "${exclude_all[@]}"; do exclude_csv="${exclude_csv:+$exclude_csv,}$e"; done
exclude_display="${exclude_csv//,/, }"
# Only user-supplied patterns are forwarded to summary.sh below — it applies its own
# copy of default_excludes unconditionally, so the defaults don't need repeating here.
exclude_args=()
for e in "${exclude_patterns[@]}"; do exclude_args+=(--exclude "$e"); done

repo_count=0
fetch_failed_names=""
repo_paths=()
: > "$tmp/rows.md"; : > "$tmp/rows.html"; : > "$tmp/sections.html"; : > "$tmp/authors.txt"
: > "$tmp/chart-repos.tsv"
mkdir -p "$tmp/r"; : > "$tmp/order.idx"
sum_added=0; sum_deleted=0; sum_total=0; sum_files=0; sum_touch=0; sum_commits=0; sum_prs=0

while IFS= read -r path || [ -n "$path" ]; do
    path="${path%$'\r'}"
    case "$path" in ''|'#'*) continue ;; esac
    name="$(basename "$path")"
    repo_count=$((repo_count + 1))
    repo_paths+=("$path")

    # Per-repo HTML side-files go to $tmp and are discarded — the combined report
    # is the product here; the single-repo mode exists for individual reports.
    if ! table="$(bash "$SUMMARY" --month "$month" --repo "$path" --out "$tmp" --no-open $fetch_flag "${exclude_args[@]}" 2>"$tmp/err.txt")"; then
        echo "summary.sh failed for group entry: $path" >&2
        cat "$tmp/err.txt" >&2
        echo "fix or remove that line in $list" >&2
        exit 1
    fi
    mark=""
    if grep -q "could not fetch" "$tmp/err.txt"; then
        mark="\\*"
        fetch_failed_names="${fetch_failed_names:+$fetch_failed_names, }$name"
    fi

    vals=(); raw=()
    for l in "${labels[@]}"; do
        v="$(metric "$table" "$l")"
        vals+=("${v:-0}"); raw+=("$(printf '%s' "${v:-0}" | tr -d ',')")
    done
    sum_added=$((sum_added + raw[0])); sum_deleted=$((sum_deleted + raw[1])); sum_total=$((sum_total + raw[2]))
    sum_files=$((sum_files + raw[3])); sum_touch=$((sum_touch + raw[4])); sum_commits=$((sum_commits + raw[5]))
    sum_prs=$((sum_prs + raw[6]))

    # Authors can't be summed across repos — the same person would count once per
    # repo. Collect names (mailmap-aware) and dedupe across the whole group.
    git -C "$path" log --branches --remotes --no-merges --since="$since" --until="$until_date" --format='%aN' 2>/dev/null >> "$tmp/authors.txt" || true

    # Buffer each repo's outputs in per-repo side-files plus a (total-changed, index)
    # line, so the loop stays order-agnostic; after the loop they are concatenated in
    # ascending total-changed order (smallest on top). raw[2] is "Total changed".
    rk="$tmp/r/$repo_count"
    printf '%s\t%s\n' "${raw[2]}" "$repo_count" >> "$tmp/order.idx"
    printf '%s\t%s\t%s\n' "$(html_escape "$name")" "${raw[0]}" "${raw[1]}" > "$rk.chart"
    echo "| ${name}${mark} | ${vals[0]} | ${vals[1]} | ${vals[2]} | ${vals[3]} | ${vals[4]} | ${vals[5]} | ${vals[6]} | ${vals[7]} |" > "$rk.rowmd"
    {
        printf '  <tr><td class="metric">%s%s</td>' "$name" "${mark:+*}"
        for v in "${vals[@]}"; do printf '<td class="count">%s</td>' "$v"; done
        printf '</tr>\n'
    } > "$rk.rowhtml"

    {
        printf '<h2>%s</h2>\n<table>\n  <tr><th>Metric</th><th style="text-align:right">Count</th></tr>\n' "$name"
        i=0
        for l in "Lines added" "Lines deleted" "Total lines changed (added + deleted)" "Files modified — distinct (each file once)" "Files modified — summed across commits" "Commits" "Pull requests merged" "Authors"; do
            cls=""; [ "$i" -eq 2 ] && cls=' class="total"'
            printf '  <tr%s><td class="metric">%s</td><td class="count">%s</td></tr>\n' "$cls" "$l" "${vals[$i]}"
            i=$((i + 1))
        done
        printf '</table>\n'
    } > "$rk.section"
done < "$list"

# Concatenate the per-repo side-files in ascending total-changed order (smallest on top)
# so the rollup table, its bar chart, and the per-repo sections share one order. Numeric
# sort on the buffered total; the index is a stable tie-break keeping discovery order.
: > "$tmp/rows.md"; : > "$tmp/rows.html"; : > "$tmp/chart-repos.tsv"; : > "$tmp/sections.html"
while IFS=$'\t' read -r _total ri; do
    [ -n "$ri" ] || continue
    cat "$tmp/r/$ri.rowmd"   >> "$tmp/rows.md"
    cat "$tmp/r/$ri.rowhtml" >> "$tmp/rows.html"
    cat "$tmp/r/$ri.chart"   >> "$tmp/chart-repos.tsv"
    cat "$tmp/r/$ri.section" >> "$tmp/sections.html"
done < <(sort -t"$(printf '\t')" -k1,1n -k2,2n "$tmp/order.idx")

if [ "$repo_count" -eq 0 ]; then
    echo "group '$group' has no repo entries ($list)" >&2
    exit 2
fi

distinct_authors="$(sed '/^$/d' "$tmp/authors.txt" | sort -u | awk 'END{print NR+0}')"

# ---- optional per-developer ACTIVITY tables (--per-author) ----
# Deliberately activity, not "performance": line counts measure file type and task
# (lockfiles, generated code, vendored docs), not effort — the notes say so and each
# developer's single dominating file is called out rather than hidden.
: > "$tmp/pa.md"; : > "$tmp/pa.html"
if [ "$per_author" -eq 1 ]; then
    # Bot identities never belong in a per-DEVELOPER table (a release pipeline
    # bumping a version number is not a developer). Built-in: the Bitbucket
    # Pipelines service identity; add more bot emails (one per line, # comments)
    # in <groups-dir>/bot-emails.list. Excluded from this table and its charts
    # ONLY — the repo rollup keeps every commit so the group totals stay complete.
    bot_emails="commits-noreply@bitbucket.org"
    if [ -f "$groups_dir/bot-emails.list" ]; then
        while IFS= read -r be || [ -n "$be" ]; do
            be="${be%$'\r'}"; case "$be" in ''|'#'*) continue ;; esac
            bot_emails="$bot_emails,$be"
        done < "$groups_dir/bot-emails.list"
    fi
    : > "$tmp/pa-bots.tsv"

    # Git side: attribute each commit's numstat to its author (%aN, mailmap-aware),
    # tracking the author's single biggest file for the inflation footnote.
    {
        for p in "${repo_paths[@]}"; do
            printf '#REPO\t%s\n' "$(basename "$p")"
            git -C "$p" log --branches --remotes --no-merges --since="$since" --until="$until_date" --format='@%aN%x09%aE' --numstat 2>/dev/null || true
        done
    } | awk -F'\t' -v bots="$bot_emails" -v excl="$exclude_csv" -v botfile="$tmp/pa-bots.tsv" '
        BEGIN {
            nb = split(bots, bl, ","); for (i = 1; i <= nb; i++) botset[bl[i]] = 1
            ne = split(excl, el, ","); for (i = 1; i <= ne; i++) exset[el[i]] = 1
        }
        /^#REPO\t/ { repo = $2; next }
        /^@/ {
            a = substr($1, 2)
            if ($2 in botset) { if (a != "") botskip[a]++; a = ""; next }
            if (a != "") commits[a]++
            next
        }
        a != "" && NF >= 3 {
            nsep = split($3, parts, "/")
            if (parts[nsep] in exset) next
            if ($1 ~ /^[0-9]+$/) { add[a] += $1; afa[a SUBSEP repo "/" $3] += $1 }
            if ($2 ~ /^[0-9]+$/) del[a] += $2
            fk = a SUBSEP repo "/" $3
            if (!(fk in seen)) { seen[fk] = 1; files[a]++ }
        }
        END {
            for (k in afa) {
                split(k, p, SUBSEP)
                if (afa[k] > big[p[1]] + 0) { big[p[1]] = afa[k]; bigf[p[1]] = p[2] }
            }
            for (a in commits)
                printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n", a, add[a], del[a], add[a] + del[a], files[a], commits[a], big[a] + 0, bigf[a]
            for (bn in botskip)
                printf "%s\t%d\n", bn, botskip[bn] > botfile
        }' | sort -t"$(printf '\t')" -k1,1 > "$tmp/pa-git.tsv"

    # Bitbucket side: true PR authorship. Git can't provide it — a merge commit's
    # author is whoever clicked merge — so pr-authors.py asks the API, once per
    # distinct workspace/slug (two clones of one remote must not double-count).
    py="$(command -v python3 || command -v python || true)"
    pr_succ=0; pr_attempted=0; pr_failed=""; pr_skipped=""
    declare -A slug_done=()
    : > "$tmp/pa-prs.raw"
    if [ -n "$py" ]; then
        for p in "${repo_paths[@]}"; do
            url="$(git -C "$p" remote get-url origin 2>/dev/null || true)"
            rname="$(basename "$p")"
            case "$url" in
                *bitbucket.org*) ;;
                *) pr_skipped="${pr_skipped:+$pr_skipped, }$rname"; continue ;;
            esac
            key="$(printf '%s' "$url" | sed -E 's#.*bitbucket\.org[:/]##; s#\.git$##')"
            [ -n "${slug_done[$key]:-}" ] && continue
            slug_done[$key]=1
            pr_attempted=$((pr_attempted + 1))
            if "$py" "$script_dir/pr-authors.py" --remote-url "$url" --month "$month" >> "$tmp/pa-prs.raw" 2>>"$tmp/pa-prs.err"; then
                pr_succ=$((pr_succ + 1))
            else
                pr_failed="${pr_failed:+$pr_failed, }$rname"
            fi
        done
    fi
    pr_col=0; [ "$pr_succ" -gt 0 ] && pr_col=1
    awk -F'\t' '{ c[$1] += $2 } END { for (a in c) printf "%s\t%d\n", a, c[a] }' "$tmp/pa-prs.raw" \
        | sort -t"$(printf '\t')" -k1,1 > "$tmp/pa-prs.tsv"

    # Join by exact author name; API authors with no git commits in the window get
    # their own zero row with a __PRONLY__ marker so the mismatch is visible.
    # (FILENAME guard, not NR==FNR — the PR file is legitimately empty when the
    # group has no Bitbucket repos, and NR==FNR would then swallow the git file.)
    # Ordered by Total changed ascending (field 4, smallest on top) to match the repo
    # rollup; author name is a stable tie-break. This orders developers by volume, which
    # is why the "activity, not performance" caption stays on the table — the ordering is
    # a presentation choice, not a performance ranking.
    awk -F'\t' -v OFS='\t' -v prsfile="$tmp/pa-prs.tsv" '
        FILENAME == prsfile { pr[$1] = $2; next }
        { print $0, ($1 in pr ? pr[$1] : 0); delete pr[$1] }
        END { for (a in pr) print a, 0, 0, 0, 0, 0, 0, "__PRONLY__", pr[a] }
    ' "$tmp/pa-prs.tsv" "$tmp/pa-git.tsv" | sort -t"$(printf '\t')" -k4,4n -k1,1 > "$tmp/pa-joined.tsv"

    stats_note="Activity volume, not performance: line counts are dominated by file type and task (lockfiles, generated code, vendored docs), not effort."
    {
        echo "**Per-developer activity — ${group} — ${month_display}**"
        echo "_${stats_note}_"
        echo ""
        if [ "$pr_col" -eq 1 ]; then
            echo "| Developer | Lines added | Lines deleted | Total changed | Files (distinct) | Commits | PRs authored (merged) |"
            echo "|---|---|---|---|---|---|---|"
        else
            echo "| Developer | Lines added | Lines deleted | Total changed | Files (distinct) | Commits |"
            echo "|---|---|---|---|---|---|"
        fi
    } >> "$tmp/pa.md"
    {
        printf '<h2>Per-developer activity</h2>\n<p class="note">%s</p>\n<table>\n' "$stats_note"
        printf '  <tr><th>Developer</th><th style="text-align:right">Lines added</th><th style="text-align:right">Lines deleted</th><th style="text-align:right">Total changed</th><th style="text-align:right">Files (distinct)</th><th style="text-align:right">Commits</th>'
        [ "$pr_col" -eq 1 ] && printf '<th style="text-align:right">PRs authored (merged)</th>'
        printf '</tr>\n'
    } >> "$tmp/pa.html"

    pa_notes=""
    : > "$tmp/chart-devs.tsv"; : > "$tmp/chart-prs.tsv"
    while IFS=$'\t' read -r a ad de to fi co big bigf pr; do
        [ -z "$a" ] && continue
        a_html="$(html_escape "$a")"
        printf '%s\t%s\t%s\n' "$a_html" "$ad" "$de" >> "$tmp/chart-devs.tsv"
        printf '%s\t%s\n' "$a_html" "$pr" >> "$tmp/chart-prs.tsv"
        ad_c="$(commafy "$ad")"; de_c="$(commafy "$de")"; to_c="$(commafy "$to")"
        fi_c="$(commafy "$fi")"; co_c="$(commafy "$co")"
        if [ "$pr_col" -eq 1 ]; then
            echo "| $a | $ad_c | $de_c | $to_c | $fi_c | $co_c | $pr |" >> "$tmp/pa.md"
            printf '  <tr><td class="metric">%s</td><td class="count">%s</td><td class="count">%s</td><td class="count">%s</td><td class="count">%s</td><td class="count">%s</td><td class="count">%s</td></tr>\n' \
                "$a_html" "$ad_c" "$de_c" "$to_c" "$fi_c" "$co_c" "$pr" >> "$tmp/pa.html"
        else
            echo "| $a | $ad_c | $de_c | $to_c | $fi_c | $co_c |" >> "$tmp/pa.md"
            printf '  <tr><td class="metric">%s</td><td class="count">%s</td><td class="count">%s</td><td class="count">%s</td><td class="count">%s</td><td class="count">%s</td></tr>\n' \
                "$a_html" "$ad_c" "$de_c" "$to_c" "$fi_c" "$co_c" >> "$tmp/pa.html"
        fi
        if [ "$bigf" = "__PRONLY__" ]; then
            pa_notes="${pa_notes}- ${a}: listed by the Bitbucket API with no matching git author name in this window.\n"
        elif [ "$big" -ge 1000 ] && [ $((big * 100)) -ge $((ad * 30)) ]; then
            pa_notes="${pa_notes}- ${a}: $(commafy "$big") of $(commafy "$ad") added lines are one file — ${bigf}.\n"
        fi
    done < "$tmp/pa-joined.tsv"
    printf '</table>\n' >> "$tmp/pa.html"

    svg_bars "$tmp/chart-devs.tsv" "Lines added" "Lines deleted" "Lines changed by developer — ${month_display}" "$tmp/chart-devs.html"
    cat "$tmp/chart-devs.html" >> "$tmp/pa.html"
    if [ "$pr_col" -eq 1 ]; then
        svg_bars "$tmp/chart-prs.tsv" "PRs authored (merged)" "" "PRs authored by developer — ${month_display}" "$tmp/chart-prs.html"
        cat "$tmp/chart-prs.html" >> "$tmp/pa.html"
    fi

    if [ -s "$tmp/pa-bots.tsv" ]; then
        while IFS=$'\t' read -r bname bcount; do
            pa_notes="${pa_notes}- Excluded from this table (bot): ${bname} — automated commits: ${bcount}. The repo rollup still includes them.\n"
        done < "$tmp/pa-bots.tsv"
    fi
    [ -n "$pr_skipped" ] && pa_notes="${pa_notes}- PRs-authored excludes repos not on Bitbucket: ${pr_skipped}.\n"
    [ -n "$pr_failed" ] && pa_notes="${pa_notes}- PR authorship unavailable for: ${pr_failed} (Bitbucket API error).\n"
    if [ "$pr_col" -eq 0 ]; then
        if [ -z "$py" ]; then pa_notes="${pa_notes}- PRs-authored column omitted: python not found.\n"
        elif [ "$pr_attempted" -gt 0 ]; then pa_notes="${pa_notes}- PRs-authored column omitted: Bitbucket API failed for every repo.\n"
        else pa_notes="${pa_notes}- PRs-authored column omitted: no Bitbucket-hosted repos in this group.\n"; fi
    fi
    if [ -n "$pa_notes" ]; then
        printf '\n%b' "$pa_notes" >> "$tmp/pa.md"
        printf '%b' "$pa_notes" | sed 's/^- \(.*\)$/<p class="note">\1<\/p>/' >> "$tmp/pa.html"
    fi
fi

t_added="$(commafy $sum_added)"; t_deleted="$(commafy $sum_deleted)"; t_total="$(commafy $sum_total)"
t_files="$(commafy $sum_files)"; t_touch="$(commafy $sum_touch)"; t_commits="$(commafy $sum_commits)"; t_prs="$(commafy $sum_prs)"

scope="all branches · each commit counted once · merges excluded from line/file/commit counts"

# ---- combined Markdown on stdout — the caller relays this verbatim ----
# The whole block is teed to a temp file so the identical bytes can be handed to the
# emailer; stdout is unchanged because tee passes its input through byte-for-byte.
md_tmp="$tmp/combined.md"
{
cat <<EOF
**${group} — ${month_display} — Repository change summary**
_${repo_count} repos · ${scope}._
_Excludes from all counts: ${exclude_display} — add more with --exclude PATTERN._

| Repo | Lines added | Lines deleted | Total changed | Files (distinct) | File-touches | Commits | PRs merged | Authors |
|---|---|---|---|---|---|---|---|---|
$(cat "$tmp/rows.md")
| **TOTAL** | **${t_added}** | **${t_deleted}** | **${t_total}** | **${t_files}** | **${t_touch}** | **${t_commits}** | **${t_prs}** | **${distinct_authors} distinct** |
EOF
[ -n "$fetch_failed_names" ] && printf '\n\\* could not fetch — local branches only: %s\n' "$fetch_failed_names"
printf '\n_Authors total = distinct people across the whole group, not the column sum._\n'
if [ "$per_author" -eq 1 ]; then
    echo ""
    cat "$tmp/pa.md"
fi
} | tee "$md_tmp"

# ---- combined HTML report ----
svg_bars "$tmp/chart-repos.tsv" "Lines added" "Lines deleted" "Lines changed by repo — ${group} — ${month_display}" "$tmp/chart-repos.html"

stamp="$(date '+%Y-%m-%d-%H%M')"
generated="$(date '+%Y-%m-%d %H:%M')"
html_file="${out_dir%/}/${stamp}-repo-change-summary-${group}-${month}.html"
exclude_display_html="$(html_escape "$exclude_display")"

foot=""
[ -n "$fetch_failed_names" ] && foot="<p class=\"note\">* could not fetch — local branches only: ${fetch_failed_names}</p>"

cat > "$html_file" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${group} &#8212; ${month_display} &#8212; Repository change summary</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20viewBox='0%200%2032%2032'%3E%3Crect%20width='32'%20height='32'%20rx='7'%20fill='%232a78d6'/%3E%3Crect%20x='6'%20y='16'%20width='5'%20height='10'%20rx='1.5'%20fill='%23fff'/%3E%3Crect%20x='13.5'%20y='11'%20width='5'%20height='15'%20rx='1.5'%20fill='%23fff'/%3E%3Crect%20x='21'%20y='6'%20width='5'%20height='20'%20rx='1.5'%20fill='%23fff'/%3E%3C/svg%3E">
<style>
  body { font-family: "Segoe UI", Arial, sans-serif; color: #0f172a; margin: 0; background: #ffffff; }
  .page { max-width: 1080px; margin: 0 auto; padding: 40px 28px 64px; }
  h1 { font-size: 27px; margin: 0 0 6px; }
  h2 { font-size: 18px; margin: 28px 0 4px; }
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
  .charttitle { font-size: 13px; font-weight: 600; color: #0b0b0b; margin: 20px 0 4px; }
  @page { size: A4 landscape; margin: 12mm; }
  @media print { .page { padding: 0; } }
</style>
</head>
<body>
<div class="page">
<h1>${group} &#8212; ${month_display} &#8212; Repository change summary</h1>
<p class="meta"><b>Group</b>: ${group} (${repo_count} repos)</p>
<p class="meta"><b>Scope</b>: ${scope}</p>
<p class="meta"><b>Excludes</b>: ${exclude_display_html} — add more with --exclude PATTERN.</p>
<p class="meta"><b>Generated</b>: ${generated}</p>
<hr class="rule">
<table>
  <tr><th>Repo</th><th style="text-align:right">Lines added</th><th style="text-align:right">Lines deleted</th><th style="text-align:right">Total changed</th><th style="text-align:right">Files (distinct)</th><th style="text-align:right">File-touches</th><th style="text-align:right">Commits</th><th style="text-align:right">PRs merged</th><th style="text-align:right">Authors</th></tr>
$(cat "$tmp/rows.html")
  <tr class="total"><td class="metric">TOTAL</td><td class="count">${t_added}</td><td class="count">${t_deleted}</td><td class="count">${t_total}</td><td class="count">${t_files}</td><td class="count">${t_touch}</td><td class="count">${t_commits}</td><td class="count">${t_prs}</td><td class="count">${distinct_authors} distinct</td></tr>
</table>
$(cat "$tmp/chart-repos.html")
${foot}
<p class="note">Authors total = distinct people across the whole group, not the column sum.</p>
$(cat "$tmp/pa.html")
<hr class="rule">
$(cat "$tmp/sections.html")
<p class="note">Generated by repo-change-summary</p>
</div>
</body>
</html>
HTML

echo ""
echo "HTML report: ${html_file}"

# Same best-effort browser open as summary.sh.
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

# Email the combined report — the LAST step, exactly once for the whole group, after the
# rollup table and "HTML report:" line have printed. send-report.py is the sibling file
# the emailer agent owns; the inner per-repo summary.sh calls never receive email flags.
if [ "$do_email" -eq 1 ]; then
    title="${group} — ${month_display} — Repository change summary"
    subject="${email_subject:-$title}"

    py="$(command -v python3 || command -v python || true)"
    if [ -z "$py" ]; then
        echo "email requested but python not found" >&2
        exit 3
    fi

    # Git Bash hands POSIX paths to native python.exe, which needs Windows paths; convert
    # every PATH argument (mirrors the browser-open above). Non-path args pass through.
    winpath() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) cygpath -w "$1" ;; *) printf '%s' "$1" ;; esac; }
    send_py="$script_dir/send-report.py"

    email_args=(
        "$(winpath "$send_py")"
        --to "$email_to"
        --subject "$subject"
        --title "$title"
        --summary-md "$(winpath "$md_tmp")"
        --attach "$(winpath "$html_file")"
        --search-dir "$(winpath "$PWD")"
    )
    [ -n "$env_file" ] && email_args+=(--env-file "$(winpath "$env_file")")
    [ -n "$mailmap" ]  && email_args+=(--mailmap "$(winpath "$mailmap")")
    [ "$email_dry_run" -eq 1 ] && email_args+=(--dry-run)

    "$py" "${email_args[@]}" || { rc=$?; echo "send-report.py failed (exit $rc)" >&2; exit "$rc"; }
fi

#!/usr/bin/env bash
#
# repo-change-summary — shared exclusion rules.
#
# Sourced by summary.sh and multi-summary.sh (both resolve it from their own
# directory). This is the ONE definition of the default exclude list and of the
# awk matcher that applies it, so the two scripts cannot drift apart.
#
# Not executable on its own — sourcing it only defines variables.

# Excluded from every count (lines, distinct files, file-touches). Matched against
# the file's BASENAME, so a nested frontend/package-lock.json still matches.
# --exclude PATTERN adds ad hoc entries on top of this list.
default_excludes=(package-lock.json yarn.lock pnpm-lock.yaml composer.lock Gemfile.lock \
    Cargo.lock poetry.lock Pipfile.lock go.sum pubspec.lock bitbucket-pipelines.yml)

# awk matcher shared by every place a path is filtered. Injected into an awk program
# by string concatenation:  awk -v excl="$exclude_csv" "$EXCL_AWK"' BEGIN { excl_init(excl) } ... '
#
# Semantics (documented in SKILL.md — keep the two in step):
#   * matching is against the BASENAME only, never the directory part;
#   * a pattern with no glob metacharacter is an EXACT match — the fast path, a hash
#     lookup, tried first and the only work done for the default list;
#   * a pattern containing * or ? is a glob: * = any run of characters (including
#     none), ? = exactly one character. Character classes ([abc], [0-9]) are NOT
#     supported — [ and ] match literally;
#   * matching is case-sensitive.
EXCL_AWK='
function excl_init(csv,   n, i, arr) {
    n = split(csv, arr, ",")
    for (i = 1; i <= n; i++) {
        if (arr[i] == "") continue
        if (arr[i] ~ /[*?]/) EXCL_RE[++EXCL_NGLOB] = excl_re(arr[i])
        else EXCL_EXACT[arr[i]] = 1
    }
}
function excl_re(g,   i, c, out) {
    out = "^"
    for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*") out = out ".*"
        else if (c == "?") out = out "."
        else if (index("\\^$.[]|()+{}", c) > 0) out = out "\\" c
        else out = out c
    }
    return out "$"
}
function excl_hit(base,   i) {
    if (base in EXCL_EXACT) return 1
    for (i = 1; i <= EXCL_NGLOB; i++) if (base ~ EXCL_RE[i]) return 1
    return 0
}
'

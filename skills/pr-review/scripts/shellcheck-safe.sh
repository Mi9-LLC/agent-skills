#!/usr/bin/env bash
# =============================================================================
# Lint shell scripts honestly: CRLF-proof, and it reports when it could not
# follow a sourced file. (Script name: shellcheck-safe.sh)
# =============================================================================
# Two problems this works around, both of which make a plain `shellcheck` run
# look cleaner than it is.
#
# 1. CRLF. A repository can store LF and enforce it through .gitattributes and
#    still have working trees, checked out before that rule was added, holding
#    CRLF files. On Windows checkouts this is the normal case.
#    Running it on a CRLF file reports SC1017 on nearly every line, which buries
#    the real findings. Copying each file through `tr -d '\r'` first and linting
#    the copy gives usable output, and line numbers still match the original
#    because only the line terminator is removed.
#
# 2. Unfollowed sources reported as "clean". A script that sources a helper
#    through a variable, such as `source "${SCRIPT_DIR}/../../shared/common.sh"`.
#    The tool cannot expand ${SCRIPT_DIR}, so `-x` silently fails to follow the
#    helper and emits SC1091 - at *info* severity, which `-S warning` filters
#    out. The run then prints nothing and exits 0 while having analysed none of
#    the sourced definitions, so anything that depends on them (SC2154
#    "referenced but not assigned", for one) is never reported. This is not an
#    artifact of the temporary copy: it fails the same way on the file in place.
#
#    The fix is --source-path set to the original file's own directory. When it
#    cannot expand a variable in a source path it falls back to the
#    remainder of the path, so `../../shared/common.sh` then resolves. This
#    script sets that automatically, and runs a separate info-severity pass so
#    that if a source still cannot be followed, it says so instead of reporting
#    a clean result that quietly means less than it appears to.
#
# Where the repository's CI configuration runs no shellcheck or shfmt step,
# whatever this reports is the only static analysis those files get. That is why
# it is worth the trouble of making "clean" mean what it says. Check the CI
# config before writing the result up either way, and say which it was.
#
# Usage:
#   bash shellcheck-safe.sh <file.sh> [file.sh ...]
#
# Note for anyone editing this header: a comment line whose first word after the
# '#' starts with "shellcheck" is parsed as a shellcheck DIRECTIVE, not prose,
# and fails with SC1072/SC1073 - including "shellcheck-safe.sh" itself. Start
# such a line with another word. Keep the file ASCII
# too: a non-ASCII character makes shellcheck abort on this Windows locale with
# "commitBuffer: invalid argument".
#
# Exit codes: 0 all clean and all sources followed, 1 at least one finding or an
# unfollowed source, 2 bad arguments.
# =============================================================================

set -uo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: shellcheck-safe.sh <file.sh> [file.sh ...]" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

STATUS=0
HAVE_SHELLCHECK=1
command -v shellcheck >/dev/null 2>&1 || HAVE_SHELLCHECK=0
if [[ ${HAVE_SHELLCHECK} -eq 0 ]]; then
  echo "NOTE: shellcheck is not installed; running 'bash -n' only." >&2
  echo "      Say exactly that in the report rather than implying shellcheck passed." >&2
  echo >&2
fi

i=0
for f in "$@"; do
  i=$((i + 1))

  if [[ ! -f "${f}" ]]; then
    echo "SKIP (not found): ${f}" >&2
    STATUS=1
    continue
  fi

  # A numbered name avoids mangling paths, which is not portable across tr builds.
  copy="${WORK}/${i}_$(basename "${f}")"
  tr -d '\r' < "${f}" > "${copy}"

  # Every finding below has to name the file under review, not the temporary
  # copy it was linted through. On Windows the two differ in FORM as well as in
  # path: bash makes /tmp/tmp.XXXX/1_x.sh, and a native shellcheck.exe reports
  # the same file as C:/Users/<user>/AppData/Local/Temp/tmp.XXXX/1_x.sh. A
  # rewrite that knows only the bash form matches nothing, and every finding
  # then cites a path that no longer exists by the time anyone reads it.
  copy_win="$(cygpath -m "${copy}" 2>/dev/null || printf '%s' "${copy}")"

  # Absolute directory of the ORIGINAL file, so sourced helpers resolve.
  src_dir="$(cd "$(dirname "${f}")" && pwd)"

  echo "=== ${f} ==="

  if bash -n "${copy}" 2>&1; then
    echo "  bash -n: OK"
  else
    echo "  bash -n: SYNTAX ERROR (above)"
    STATUS=1
  fi

  if [[ ${HAVE_SHELLCHECK} -eq 1 ]]; then
    # Pass 1: did every `source` actually get followed? SC1091 is info severity,
    # so this pass is the only place it is visible.
    unfollowed="$(shellcheck -S info -x --source-path="${src_dir}" "${copy}" 2>&1 \
                  | grep -c 'SC1091' || true)"
    if [[ "${unfollowed}" -gt 0 ]]; then
      echo "  sources followed: NO - ${unfollowed} source line(s) could not be resolved:"
      # Bash substitution rather than sed: a path holding | or & breaks a sed pattern.
      unfollowed_out="$(shellcheck -S info -x --source-path="${src_dir}" "${copy}" 2>&1 \
                        | grep -A1 'SC1091')"
      unfollowed_out="${unfollowed_out//${copy_win}/${f}}"
      printf '%s\n' "${unfollowed_out//${copy}/${f}}" | sed 's/^/    /'
      echo "    A finding that depends on those definitions would not be reported."
      echo "    Record this in the report; do not describe the result as simply clean."
      STATUS=1
    else
      echo "  sources followed: yes"
    fi

    # Pass 2: the findings themselves.
    if out="$(shellcheck -S warning -x --source-path="${src_dir}" "${copy}" 2>&1)"; then
      echo "  shellcheck -S warning: clean"
    else
      out="${out//${copy_win}/${f}}"
      echo "${out//${copy}/${f}}"
      STATUS=1
    fi
  fi
  echo
done

exit ${STATUS}

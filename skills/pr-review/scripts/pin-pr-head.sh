#!/usr/bin/env bash
# =============================================================================
# pin-pr-head.sh - clone a throwaway checkout pinned to a pull request's head
# =============================================================================
# The working directory a review is started from may be shared with other
# sessions, and its checked-out branch moves while the review is in progress.
# Reviewing from it produces line numbers that belong to whatever was checked
# out at the moment each file was read. This script makes a separate clone,
# pins it to the head commit, and prints the three facts a review header has to
# state: the head hash, the merge base, and the file list that range contains.
#
# Usage:
#   pin-pr-head.sh <head-sha> <dest-branch> <target-dir> [source-repo]
#
#   head-sha      Pull request source commit, from BITBUCKET_GET_PULL_REQUEST
#   dest-branch   Destination branch name, e.g. develop
#   target-dir    Where to put the clone (use the session scratchpad)
#   source-repo   Repository to clone from. Defaults to the current directory,
#                 which is fast because git hardlinks the object store.
#
#                 REQUIRED when the pull request is in a repository other than
#                 the current checkout. The default clones the current
#                 directory, and the pull request's head commit does not exist
#                 there, so the run fails at the lookup below. Pass either a
#                 local clone of the right repository, or a clone URL such as
#                 https://bitbucket.org/<workspace>/<repo>.git
#
# The origin URL of whatever was cloned is printed as ORIGIN= so the caller can
# confirm the repository is the one the pull request lives in.
#
# Exit codes: 0 ok, 1 bad arguments, 2 the commit or branch could not be found.
# =============================================================================

set -euo pipefail

HEAD_SHA="${1:-}"
DEST_BRANCH="${2:-}"
TARGET_DIR="${3:-}"
SOURCE_REPO="${4:-$(pwd)}"

if [[ -z "${HEAD_SHA}" || -z "${DEST_BRANCH}" || -z "${TARGET_DIR}" ]]; then
  echo "usage: pin-pr-head.sh <head-sha> <dest-branch> <target-dir> [source-repo]" >&2
  exit 1
fi

rm -rf "${TARGET_DIR}"
git clone --no-checkout --quiet "${SOURCE_REPO}" "${TARGET_DIR}"
cd "${TARGET_DIR}"

# The source repo may not have the PR commit yet if it was pushed from elsewhere.
if ! git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null; then
  echo "Head commit not present in the local clone; fetching from origin..." >&2
  git fetch --quiet origin || true
fi

if ! git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null; then
  CLONED_ORIGIN="$(git remote get-url origin 2>/dev/null || echo '(none)')"
  echo "ERROR: commit ${HEAD_SHA} not found, even after fetching origin." >&2
  echo "Cloned from : ${SOURCE_REPO}" >&2
  echo "Its origin  : ${CLONED_ORIGIN}" >&2
  echo >&2
  echo "Three causes, in the order they are worth checking:" >&2
  echo "  1. The clone is the WRONG REPOSITORY. This is what happens when the" >&2
  echo "     pull request is in a repository other than the current checkout" >&2
  echo "     and no [source-repo] argument was passed. Re-run with a local" >&2
  echo "     clone of the right repository, or with its clone URL, as the" >&2
  echo "     fourth argument." >&2
  echo "  2. The branch was never pushed to the origin above." >&2
  echo "  3. The hash is wrong." >&2
  exit 2
fi

git checkout --quiet "${HEAD_SHA}"

# Prefer the remote-tracking ref: the local branch may be stale or absent.
git fetch --quiet origin "${DEST_BRANCH}" 2>/dev/null || true
DEST_REF="origin/${DEST_BRANCH}"
if ! git rev-parse --verify --quiet "${DEST_REF}" >/dev/null; then
  DEST_REF="${DEST_BRANCH}"
fi
if ! git rev-parse --verify --quiet "${DEST_REF}" >/dev/null; then
  echo "ERROR: destination branch '${DEST_BRANCH}' not found locally or on origin." >&2
  exit 2
fi

RESOLVED_HEAD="$(git rev-parse HEAD)"
MERGE_BASE="$(git merge-base HEAD "${DEST_REF}")"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || echo '(none)')"

echo "PINNED_CHECKOUT=${TARGET_DIR}"
echo "ORIGIN=${ORIGIN_URL}"
echo "HEAD=${RESOLVED_HEAD}"
echo "MERGE_BASE=${MERGE_BASE}"
echo "DEST_REF=${DEST_REF}"
echo
echo "--- git diff --numstat ${MERGE_BASE}..${RESOLVED_HEAD} ---"
git diff --numstat "${MERGE_BASE}..${RESOLVED_HEAD}"
echo
echo "--- commits in range ---"
git log --format='%h %s' "${MERGE_BASE}..${RESOLVED_HEAD}"
echo
echo "Check ORIGIN above: it must be the repository the pull request lives in."
echo
echo "Compare the numstat above against BITBUCKET_GET_PULL_REQUEST_DIFFSTAT."
echo "If the file list or the counts differ, stop: the PR or the destination"
echo "branch moved, and every line number in the review would be wrong."

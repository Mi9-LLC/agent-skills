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
# When source-repo is a local directory, this script repoints the new clone's
# origin at that checkout's own origin. Without that step git would leave the
# local path as origin, every fetch would read the local checkout instead of the
# hosting service, and a branch the checkout only has as origin/<name> would be
# reported as missing. The origin actually in use is printed as ORIGIN= so the
# caller can confirm it is the repository the pull request lives in.
#
# Exit codes: 0 ok, 1 bad arguments or an unsafe target directory, 2 the clone
# failed or the commit or branch could not be found.
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

# Refuse to delete a target that exists and is not a git clone. TARGET_DIR comes
# from the caller and this is an rm -rf, so a mistyped path must not be silently
# destroyed. An existing clone is ours from a previous run and is replaced.
if [[ -e "${TARGET_DIR}" && ! -d "${TARGET_DIR}/.git" ]]; then
  echo "ERROR: ${TARGET_DIR} exists and is not a git clone. Refusing to delete it." >&2
  echo "Pass a target directory that does not exist, or one this script made." >&2
  exit 1
fi

if [[ ! -d "${SOURCE_REPO}" ]] && [[ "${SOURCE_REPO}" != *://* ]] && [[ "${SOURCE_REPO}" != *@*:* ]]; then
  echo "ERROR: source repo '${SOURCE_REPO}' is neither a directory nor a clone URL." >&2
  exit 1
fi

rm -rf "${TARGET_DIR}"
if ! git clone --no-checkout --quiet "${SOURCE_REPO}" "${TARGET_DIR}"; then
  echo "ERROR: could not clone '${SOURCE_REPO}'." >&2
  exit 2
fi
cd "${TARGET_DIR}"

# Cloning a local path makes THAT PATH the new clone's origin, so every fetch
# below would read the local checkout and never the hosting service. A branch
# that exists only as origin/<name> in the source checkout would then be
# reported as missing. Point origin at the source checkout's own origin; the
# objects stay hardlinked, so the clone is still fast.
if [[ -d "${SOURCE_REPO}" ]]; then
  UPSTREAM_URL="$(git -C "${SOURCE_REPO}" remote get-url origin 2>/dev/null || true)"
  if [[ -n "${UPSTREAM_URL}" ]]; then
    git remote set-url origin "${UPSTREAM_URL}"
  else
    echo "NOTE: ${SOURCE_REPO} has no origin remote, so this clone can only see" >&2
    echo "      what that checkout already had. A branch or commit it never" >&2
    echo "      fetched will be reported as missing below." >&2
  fi
fi

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
  echo "  1. The origin above is the WRONG REPOSITORY. This happens when the" >&2
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

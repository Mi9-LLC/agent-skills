#!/usr/bin/env python3
"""Count merged pull requests per AUTHOR for one calendar month, via the Bitbucket API.

Git alone cannot attribute PRs to their authors — a merge commit's author is whoever
clicked merge, and squash merges reassign authorship too — so the per-developer PR
column comes from the API instead. Credentials are reused from git's own credential
store (`git credential fill`); nothing extra to configure.

Usage: pr-authors.py --remote-url URL --month YYYY-MM [--from-file page.json]
Output: TSV lines "display_name<TAB>merged_pr_count" on stdout.
Exit codes: 0 ok · 2 bad input · 3 no credentials · 4 API/HTTP failure.

Python 3.9+, stdlib only.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime


def repo_slug(remote_url: str) -> tuple[str, str]:
    """Extract (workspace, slug) from a bitbucket.org remote URL (https or ssh)."""
    m = re.search(r"bitbucket\.org[:/]([^/]+)/([^/]+?)(?:\.git)?/?$", remote_url)
    if not m:
        print(f"not a bitbucket.org remote: {remote_url}", file=sys.stderr)
        sys.exit(2)
    return m.group(1), m.group(2)


def month_window(month: str) -> tuple[str, str]:
    """[first day, first day of next month) as ISO-8601 in the LOCAL timezone,
    matching the git --since/--until window the line counts use."""
    if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", month):
        print(f"invalid --month '{month}' (expected YYYY-MM)", file=sys.stderr)
        sys.exit(2)
    year, mon = int(month[:4]), int(month[5:7])
    start = datetime(year, mon, 1).astimezone()
    end = datetime(year + 1, 1, 1).astimezone() if mon == 12 else datetime(year, mon + 1, 1).astimezone()
    return start.isoformat(), end.isoformat()


def credential_fill(host: str, username_hint: str | None = None) -> tuple[str | None, str | None]:
    """Ask git's credential store for a stored login (never prompts)."""
    request = f"protocol=https\nhost={host}\n"
    if username_hint:
        request += f"username={username_hint}\n"
    try:
        proc = subprocess.run(
            ["git", "credential", "fill"],
            input=request + "\n",
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=30,
            env={"GIT_TERMINAL_PROMPT": "0", **os.environ},
        )
    except (OSError, subprocess.TimeoutExpired):
        return None, None
    fields = dict(line.split("=", 1) for line in proc.stdout.splitlines() if "=" in line)
    if proc.returncode != 0:
        return None, None
    return fields.get("username"), fields.get("password")


def auth_header() -> str:
    """Build a working Authorization header from git's stored Bitbucket credentials.

    Atlassian API tokens are stored for git under the pseudo-username
    x-bitbucket-api-token-auth, but the REST API wants Basic auth as
    <account email>:<token>. App passwords work as <username>:<app password>.
    Try both, verified against /2.0/user so failures are crisp and early.
    """
    email = os.environ.get("BITBUCKET_EMAIL")
    if not email:
        proc = subprocess.run(["git", "config", "user.email"], capture_output=True,
                              text=True, encoding="utf-8", timeout=30)
        email = proc.stdout.strip() or None

    candidates: list[tuple[str, str]] = []
    _, token = credential_fill("bitbucket.org", "x-bitbucket-api-token-auth")
    if token and email:
        candidates.append((email, token))
    user, password = credential_fill("bitbucket.org")
    if user and password:
        candidates.append((user, password))

    if not candidates:
        print("no stored Bitbucket credentials (git credential fill returned nothing)", file=sys.stderr)
        sys.exit(3)

    for basic_user, secret in candidates:
        header = "Basic " + base64.b64encode(f"{basic_user}:{secret}".encode()).decode()
        req = urllib.request.Request("https://api.bitbucket.org/2.0/user",
                                     headers={"Authorization": header})
        try:
            with urllib.request.urlopen(req, timeout=30):
                return header
        except urllib.error.HTTPError:
            continue
        except (urllib.error.URLError, TimeoutError) as exc:
            print(f"Bitbucket API unreachable: {exc}", file=sys.stderr)
            sys.exit(4)

    print(
        "Bitbucket rejected all stored credentials. If your git user.email is not your "
        "Atlassian account email, set BITBUCKET_EMAIL to the Atlassian one.",
        file=sys.stderr,
    )
    sys.exit(3)


def fetch_pages(url: str, auth_header: str):
    """Yield parsed JSON pages, following Bitbucket's `next` pagination links."""
    while url:
        req = urllib.request.Request(url, headers={"Authorization": auth_header})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                page = json.load(resp)
        except urllib.error.HTTPError as exc:
            print(f"Bitbucket API HTTP {exc.code} for {url}", file=sys.stderr)
            sys.exit(4)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            print(f"Bitbucket API failure: {exc}", file=sys.stderr)
            sys.exit(4)
        yield page
        url = page.get("next")


def main() -> None:
    # Emit \n even on Windows — downstream shell pipelines split on \n and must
    # not see \r in the last field.
    sys.stdout.reconfigure(newline="\n")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--remote-url", required=True)
    parser.add_argument("--month", required=True)
    parser.add_argument("--from-file", default=None,
                        help="read one already-fetched API page from a JSON file instead of the network (for tests)")
    args = parser.parse_args()

    counts: Counter[str] = Counter()

    if args.from_file:
        with open(args.from_file, encoding="utf-8") as fh:
            pages = [json.load(fh)]
    else:
        workspace, slug = repo_slug(args.remote_url)
        start, end = month_window(args.month)
        header = auth_header()
        query = f'state = "MERGED" AND closed_on >= "{start}" AND closed_on < "{end}"'
        url = (
            f"https://api.bitbucket.org/2.0/repositories/{workspace}/{slug}/pullrequests"
            f"?pagelen=50&fields=next,values.author.display_name"
            f"&q={urllib.parse.quote(query)}"
        )
        pages = fetch_pages(url, header)

    for page in pages:
        for pr in page.get("values", []):
            author = (pr.get("author") or {}).get("display_name") or "(unknown)"
            counts[author] += 1

    for author in sorted(counts):
        print(f"{author}\t{counts[author]}")


if __name__ == "__main__":
    main()

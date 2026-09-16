---
name: pr-review
description: >-
  Review a Bitbucket pull request in any repository end to end - fetch it, pin a checkout of its
  head commit, run the parallel diff pass and the claim-verification pass, write the full report to
  docs/reviews/, and post one self-contained summary comment once the user approves it. Reads and
  comments only: it never pushes, never merges, and never edits the pull request branch. Use this
  whenever a Bitbucket pull request review is asked for in any wording, including "review PR 29",
  "review this pull request", "can you review the PR", "review pull request 12 in
  <workspace>/<repo>", a pasted bitbucket.org/.../pull-requests/<n> URL, or a request for a PR
  review report or a review comment on a PR. Bitbucket only, through the Composio MCP tools. Do NOT
  use it for a GitHub pull request, which needs gh or a general code-review skill; for reviewing
  uncommitted or local changes with no pull request behind them; or for a code review of a branch or
  a diff that was never opened as a pull request.
model: claude-opus-5
disallowed-tools: Edit, NotebookEdit
---

# Reviewing a Bitbucket pull request

## Arguments

- A bare pull request number means that pull request in the Bitbucket repository that the current
  working directory's `git remote get-url origin` points at. If `origin` is not a Bitbucket remote,
  or the working directory is not a git repository, ask for `<workspace>/<repo>` instead of guessing
  which repository was meant.
- `<workspace>/<repo> <pr-number>` means a pull request in another Bitbucket repository.
- `--no-comment` means do every step up to and including Step 7, then stop. Post nothing to
  Bitbucket.

Examples: `review PR 29`, `review PR 29 --no-comment`, `review PR 12 in <workspace>/<repo>`.

## Hard rules

These three are the ones that have been broken before, so they come first.

1. **Read and comment only.** Never push code, never merge, never edit the pull request branch.
2. **The only file written inside the repository is the report**, at
   `docs/reviews/pr-review-{repo}-{pr_number}.md` or at the location Step 7 resolves. Nothing else
   in the repository is created, modified or deleted, including reports for other pull requests.
3. **The posted comment carries no snippet links, no download links and no external URLs of any
   kind.** Not a Bitbucket link, not a commit link, not a link to the report. It is self-contained
   plain text and tables. The comment may name the report's path as plain text.

Never put an API key, token, password or connection string into the report or the comment.

This skill declares no `allowed-tools`, because the Bitbucket tools it needs are the user's own
Composio MCP registration and cannot be listed here. It does declare
`disallowed-tools: Edit, NotebookEdit`: the only file it ever writes is the report, and `Write`
covers that, so dropping `Edit` while the skill is active costs it nothing and takes away the tool
that would break Hard rule 2. The guard is per-turn and covers this session only, not the subagents
Step 5 launches, so Hard rules 1 and 2 remain workflow discipline as well.

## Assumptions for you and for every subagent you launch

- All tools work and will not error. Do not test tools and do not make exploratory calls. Repeat this
  sentence in the prompt of every subagent you launch, because a subagent that starts by probing its
  tools spends its budget before it reads anything.
- Call a tool only when it is required. Every call needs a clear purpose.
- Write a todo list before starting.

## What is in this skill

These files live in the installed skill directory, not in the repository being reviewed. Invoke
every bundled script through `${CLAUDE_SKILL_DIR}`, the base directory Claude Code prints when this
skill loads; a bare `scripts/…` path resolves against the session's working directory and will not
be found.

- `scripts/pin-pr-head.sh` — clones a throwaway checkout pinned to the pull request head and prints
  the head hash, the merge base and the numstat. Used in Step 3.
- `scripts/shellcheck-safe.sh` — runs `bash -n` and `shellcheck` on files that may have CRLF line
  endings, without the SC1017 noise that buries real findings. Used in Step 6.
- `references/report-template.md` — the report skeleton, with a worked example per severity. Read it
  in Step 7 before writing anything, and again when the shape of a section is unclear.
- `references/severity-rubric.md` — what separates CRITICAL, HIGH, MEDIUM and LOW here, and the list
  of things not to flag. Read it in Step 5 and again in Step 7, before assigning any severity.

## How to call the Bitbucket tools

The Composio MCP server has to be registered for the session, either from the user's own
`~/.claude.json` or from a project `.mcp.json`. If the Composio tools are not available, stop and
say so. Do not fall back to `gh`, and do not review a pull request you could not fetch.

Reach every Bitbucket tool the same way: call `COMPOSIO_SEARCH_TOOLS` to load the tool schemas, then
execute them through `COMPOSIO_MULTI_EXECUTE_TOOL`.

These tool slugs are verified to exist. Do not invent others:

- `BITBUCKET_GET_PULL_REQUEST`
- `BITBUCKET_GET_PULL_REQUEST_DIFF`
- `BITBUCKET_GET_PULL_REQUEST_DIFFSTAT`
- `BITBUCKET_CREATE_PULL_REQUEST_COMMENT`
- `BITBUCKET_GET_REPOSITORIES_PULLREQUESTS_COMMENTS`
- `BITBUCKET_GET_PULL_REQUEST_COMMITS`
- `BITBUCKET_GET_COMMIT_DIFF`
- `BITBUCKET_GET_FILE_FROM_REPOSITORY`
- `BITBUCKET_BROWSE_REPOSITORY_PATH`

---

## Step 1 — Fetch the pull request

1. `BITBUCKET_GET_PULL_REQUEST` for the metadata: title, description, author, state, source branch
   and commit, destination branch and commit, draft flag.
2. `BITBUCKET_GET_PULL_REQUEST_DIFFSTAT` for the changed-file list with per-file added and removed
   line counts. Two things about this response:
   - It is paginated. Follow `response.data.next` until it is absent and concatenate the pages. A
     single page is not the whole file list.
   - `values[].new.path` is null for a deleted file. Fall back to `values[].old.path` so deletions
     are not dropped from the list.
3. `BITBUCKET_GET_PULL_REQUEST_DIFF` for the unified diff. Check `response.data.truncated`. If it is
   true the diff you received is incomplete, so do not review it: use the pinned checkout from Step 3
   and run `git diff <merge-base>..<head>` there instead, and say in the report that the diff came
   from the local checkout.

Record the file count and the total added and removed lines. Step 7 and Step 8 both need them.

## Step 2 — Skip conditions

Check whether any of the following is true. Do this yourself; none of it needs a subagent. Do it
before pinning a checkout: the pin is a clone, and a skipped pull request should not cost one.

- The pull request state is not `OPEN`, that is, it is `MERGED`, `DECLINED` or otherwise closed. Step
  1 already fetched the state.
- The pull request is a draft. Step 1 already fetched the draft flag.
- The change does not need review: an automated pull request, or a change that is trivially and
  obviously correct. This one is your judgement.
- This procedure has already posted its review. One
  `BITBUCKET_GET_REPOSITORIES_PULLREQUESTS_COMMENTS` call answers this: look for a top-level comment
  whose first line is exactly `Code review by pr-review`, the marker Step 8 puts on every comment it
  posts. Nothing else counts. A review comment from anyone else, including an AI review the author
  posted under their own account, is not a skip condition: it was not produced by this procedure, and
  its statements are claims for Step 6 like any other. Two pull requests checked on 2026-09-16 each
  carried such an author-posted review, one in this procedure's old shape and one in another; the
  marker is what makes the check the same in both cases.

If any condition is true, stop and do not go on. Say which condition stopped you.

A pull request written by Claude still gets reviewed. Being AI-generated is not a skip condition.

## Step 3 — Pin a checkout

The working directory you started in may be shared with other sessions, and its checked-out branch
can move while you work. Never review from it, and never run `git checkout` in it. Line numbers
taken from a moving working tree are wrong by the time anyone reads them.

Run the script, from the primary working directory so the clone can use its object store:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/pin-pr-head.sh" <head-sha> <dest-branch> <scratchpad>/pr-<number>
```

The script takes an optional fourth argument, the repository to clone from, and it defaults to the
current directory. When the pull request's repository is not the current checkout, pass that
repository as the fourth argument: a local clone path, or a clone URL such as
`https://bitbucket.org/<workspace>/<repo>.git`. Without it the script clones the current directory,
which is the wrong repository, and the run fails.

Cloning a local checkout would normally leave that local path as the new clone's origin, so every
fetch would read the checkout instead of Bitbucket, and a branch the checkout holds only as
`origin/<name>` would be reported as missing. The script repoints origin at the source checkout's
own origin to prevent that. If the source checkout has no origin remote, the script says so: the
clone can then only see what that checkout had already fetched.

It prints `ORIGIN=`, `PINNED_CHECKOUT=`, `HEAD=`, `MERGE_BASE=`, the `git diff --numstat` for that
range, and the commits in the range. Confirm `ORIGIN=` is the repository the pull request lives in
before trusting anything else the script printed.

Then cross-check its numstat against the diffstat from Step 1: the same file list and the same
per-file counts. If they differ, stop and report the difference. It means the pull request moved while
you were reading it, or the destination branch advanced, and every line number in the review would be
wrong.

Two differences are formatting, not movement, and must not stop the run:

- **A binary file.** `git diff --numstat` prints `-` for both counts where Bitbucket reports a
  number. Match on the path and treat the counts as agreeing.
- **A rename.** `git diff --numstat` can print the path as `{old => new}/name` on one line where
  Bitbucket lists the old and new paths separately. Resolve it to the new path before comparing.

Anything else that differs is real. Stop on it.

Record both full hashes; they go in the report header. All file reading and every command in Steps 5
and 6 runs against the pinned checkout, using absolute paths. Tell every subagent to use the pinned
path.

## Step 4 — Collect the CLAUDE.md scope

Collect a list of file paths, not their contents. Glob answers this; no subagent is needed.

- The root `CLAUDE.md`, if it exists.
- Every `CLAUDE.md` in a directory that contains a file changed by this pull request.
- Every file under `.claude/rules/`.

Scoping rule, to pass on to the compliance agents in Step 5: a `CLAUDE.md` applies only to files in
its own directory or below it. A rule in `services/admin-service/CLAUDE.md` says nothing about a file
in `libs/core/`. The root `CLAUDE.md` and the files in `.claude/rules/` apply to the whole repository.

## Step 5 — The parallel diff pass

Give every agent in this step the pull request title and description, so it knows what the author
intended, and the path of the pinned checkout from Step 3. Read `references/severity-rubric.md`
first; its "what to flag" and "what not to flag" lists go into the prompt of every agent here.

### 5a. Four agents in parallel

Launch all four in one message so they run at the same time. Each returns a list of issues, and each
issue carries a description and the reason it was flagged, for example "CLAUDE.md adherence" or
"bug".

- **Agent 1 and Agent 2: CLAUDE.md compliance, Sonnet.** Audit the changed files against the
  `CLAUDE.md` files and `.claude/rules/` files collected in Step 4. When judging a file, consider only
  the `CLAUDE.md` files that share its path or are a parent of it.
- **Agent 3: bugs, Opus.** Scan for obvious bugs. Work from the diff itself without reading extra
  context. Flag only significant bugs. Ignore nitpicks and likely false positives. Do not flag
  anything that cannot be validated without looking outside the diff.
- **Agent 4: bugs, Opus.** Look for problems in the introduced code: security issues, incorrect
  logic, and similar. Look only for issues inside the changed code.

Only high-signal issues are wanted. The rubric's "what to flag" list is the standard and its "what
not to flag" list is the exclusion list. If you are not certain an issue is real, do not flag it.
False positives lose trust and waste reviewer time.

### 5b. One validation subagent per issue

For each issue returned by any of the four agents, launch a subagent to validate it. Run them in
parallel. All four, not only the bug agents: Step 5c drops everything that was not validated here, so
leaving the two compliance agents out of this step would discard every `CLAUDE.md` finding they
produced. Give each one the pull request title and description and the description of the single
issue. Its job is to check that the stated issue is truly an issue, with high confidence. If the
issue was "variable is not defined", the subagent confirms that this is actually true in the code.
For a `CLAUDE.md` issue, the subagent confirms both that the rule is scoped to that file and that it
is actually violated.

Use Opus subagents for bugs and logic issues. Use Sonnet subagents for `CLAUDE.md` violations.

At most 12 validation subagents in one run. Rank the candidates by which bullet of the rubric's
"what to flag" list they match, taking the bullets in the order they are written: a compile or parse
failure first, then code that produces wrong results regardless of input, then a `CLAUDE.md`
violation. Inside one bullet, keep the candidate whose file comes first in the diffstat. The
rubric's fourth bullet, a claim the repository contradicts, cannot appear here: Step 6 produces
those and it runs after this step.

If more candidates came back than the cap, the report says how many were not validated, and those
are dropped rather than reported unvalidated.

### 5c. Filter

Drop every issue that was not validated in 5b. What remains is the high-signal list from this stage.

## Step 6 — The verification pass

Step 5 reads the diff. It cannot settle whether the change is *true*, and that is where a review
finds most of what matters. Do not drop this step and do not merge it into Step 5.

1. **Settle factual claims against primary sources.** Treat every claim in the commit messages and in
   the pull request description as a claim to check, not as evidence. If a commit message says a
   library behaves a certain way, read that library's source at the version being used. If it says a
   checklist item is closed, open the checklist. If the pull request adds its own review or design
   document, that document was written by the same author as the code, so it is part of the change
   under review and is not independent support for it. For each claim record: settled and correct,
   settled and wrong, or not settled. A claim you could not settle goes in the "what was NOT checked"
   section of the report, with the exact source that would settle it.
2. **Read sibling repositories when the change depends on one.** Read only. Never write to a sibling
   repository and never check out a branch in one.
3. **Lint every changed shell script**, from the pinned checkout:

   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/shellcheck-safe.sh" <pinned>/path/a.sh <pinned>/path/b.sh
   ```

   The script runs `bash -n` and `shellcheck -S warning` on a copy with the carriage returns removed,
   because a working tree can hold CRLF files and `SC1017` would otherwise bury every real finding.
   It exits 1 when any file has a finding, and it says so when `shellcheck` is not installed rather
   than passing silently. Check whether the repository's CI configuration runs a shell linter, and
   say in the report which one it runs; where it runs none, say that this is the only static analysis
   these scripts get. Report every warning that survives, and say which warnings were already there
   before this change.
4. **Parse every changed YAML file** and confirm it is valid.
5. **Run the repository's own gates.** The target repository's `CLAUDE.md` is the source of truth for
   its quality gates and its contribution rules. Read it, run the gates it names, in the pinned
   checkout, and check the change against every contribution rule it states, for example a rule that
   a change of a given kind must add a changelog entry.

   **Install dependencies in the pinned checkout first, with the install command the repository's
   own CI configuration runs**, flags and config file included: read `bitbucket-pipelines.yml` or the
   equivalent and copy its install line (for example `npm ci --prefer-offline
   --userconfig=.bin/npm/.npmrc`). A plain `npm ci` can fail where CI's does not: on 2026-09-16 a
   lockfile was in sync only under the `legacy-peer-deps=true` that CI's config file set, and the
   same file mapped a private registry scope. The checkout is a fresh clone with no `node_modules`
   and no restored packages; without the install every gate fails on a missing dependency and the
   report says "could not run" for all of them, which reads as a tooling problem rather than as the
   clean result it actually is.

   A gate may write inside the pinned checkout: a test runner rewrites snapshot files, a bundler
   leaves a cache. That is harmless in a throwaway clone. Say in the report that it happened, and
   never read the `git status` noise it leaves as a finding against the pull request.

   Where `CLAUDE.md` names no gates, or the repository has no `CLAUDE.md` at all, run whichever of
   these exist:

   - `package.json`: the `lint`, `typecheck` and `test` scripts it defines, with the package manager
     its lockfile names, plus `build` when the change touches source rather than only tests.
   - .NET: `dotnet build --nologo`, then `dotnet test` when the project has test projects.
   - Python: the linter `pyproject.toml` configures, and `pytest` if the repository has tests.

   Name in the report the exact commands you ran, not the category. A gate that cannot run is
   reported as not run, with the reason, rather than left looking like it passed.

Merge the findings from this step with the validated findings from Step 5 into one list. Label each
finding with the stage that produced it, "diff pass" or "verification pass", so a reader can tell
which findings came from reading the diff and which came from checking the claims.

## Step 7 — Write the report

Read `references/report-template.md` before writing anything, and `references/severity-rubric.md`
before assigning any severity. The template holds the section list, the field list for a finding and
a worked example at each severity; the rubric holds the four definitions and the rules that decide
between two adjacent levels.

Where the report goes depends on whether the pull request is in the repository you are standing in.

- **The pull request is in the current checkout.** Write
  `docs/reviews/pr-review-{repo}-{pr_number}.md` there, creating `docs/reviews/` if it does not
  exist. If that repository's own `CLAUDE.md` names a different place for review or audit documents,
  that place wins.
- **The pull request is in another repository**, which is exactly the case where Step 3 needed its
  fourth argument. Write the report to `<scratchpad>/pr-<number>/pr-review-{repo}-{pr_number}.md`
  instead. Never write it into the current checkout: that repository has nothing to do with the
  change under review, and Hard rule 2 allows one report in the repository being reviewed, not a
  file dropped into an unrelated one.

Say the report's path in your terminal reply either way. Do not modify any other file, and do not
modify an existing report for a different pull request.

This file is the primary output of the review. It has to be complete enough that a separate
remediation agent can implement every fix without re-reading the codebase or the diff.

Every finding quotes the evidence it rests on: a line of code, a line of a `CLAUDE.md` rule, a line
of a commit message, or a line of the source that settles the claim. A finding with no quoted
evidence does not go in the report, because the reader cannot check it.

Then re-read the report cold, as if acting on it for the first time rather than from memory, and
check it against the self-review list at the end of the template. Fix what is missing or vague before
saying the review is done, and say in your terminal reply what that self-review found. Silently
fixing the gaps hides whether the pass ran at all.

## Step 8 — Post the summary comment

1. **If `--no-comment` was given, stop after Step 7.** Post nothing, and ask no question.
2. **Build the comment.** One top-level comment whose first line is exactly
   `Code review by pr-review`, on a line of its own. Step 2 of a later run looks for that line, so
   it is what stops this procedure posting twice on one pull request. Then:

   - The pull request overview: what it does, its size, the number of files changed.
   - The findings-count table by severity.
   - Every CRITICAL issue, with file, line and a one-line description.
   - The top five HIGH-priority issues, briefly.
   - What looks good.
   - The verdict.

   **No snippet links. No download links. No external URLs of any kind.** The comment is
   self-contained. It may name the report's path as plain text, not as a link.

   If no issues were found, the comment reads, after the marker line: "No issues found. Checked for
   bugs, CLAUDE.md compliance, and the claims made in the commit messages and description."

   Where a bug is found, describe the exact fix in the comment. Do not push code.
3. **Show the user the comment's exact full text, then ask once with `AskUserQuestion` whether to
   post it.** Three options: post it, which is the recommended default; edit it first and then ask
   again; or do not post it.
4. **Only a clear yes posts the comment**, with `BITBUCKET_CREATE_PULL_REQUEST_COMMENT`. A question
   that is declined or left unanswered means nothing is posted: say in your terminal reply that the
   comment was not posted, and name the report's path so the user can post it themselves.
5. **When `AskUserQuestion` is not available, treat the question as unanswered and post nothing.**
   It is unavailable in a `claude -p` run, and a subagent has no user to ask. Silence is not consent
   here: posting a comment onto a pull request notifies its author and is visible to the whole team,
   so the safe reading of "nobody could be asked" is "do not post". Write the report, return its
   path, and say plainly that the comment was not posted and why.

   Running as a subagent, the report is the run's return value. Do not rely on chat text reaching
   the session that launched you.

## When a finding turns out to be wrong

It happens, and it happened twice in the review of pull request #29: one finding was downgraded from
HIGH to MEDIUM once its failure mechanism turned out to be bounded rather than unbounded, and another
was withdrawn entirely once the upstream source contradicted it.

Correct it in the report, following "recording a finding that changed during the review" in the
template: the severity line says what the rating was and why it moved, and the corrections block in
section 2 lists the change.

**If the summary comment is already posted, also post a threaded reply** on the pull request saying
what was wrong and why. Do not quietly edit the report and leave the comment standing. The author may
already be acting on a finding you no longer stand behind, and a reviewer's credibility rests on the
corrections being as visible as the findings were. A review that corrects itself in the open is
trusted further than one that is never seen to be wrong.

## Review checklist

Whatever the stage, the review covers:

1. Bugs and logic errors
2. Security issues: OWASP top 10, injection, auth bypass
3. Performance concerns: N+1 queries, missing indexes, unbounded loops
4. Style and readability: naming, complexity, dead code
5. Missing edge cases and error handling
6. Breaking changes and backwards-incompatibility
7. Claims in the commit messages and description that the repository or the upstream source does not
   support

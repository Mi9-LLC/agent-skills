# Description trigger sweep: pr-review, real registration

Run on 2026-09-16, model `claude-opus-5`, against the description at commit `d4013ea` on
`fix/pr-review-review-findings`. 14 prompts, one variant. The prompt set is
`description-ab-prompts.tsv`, the runner is `run_description_ab.sh`, and the raw per-prompt rows are
`description-ab-2026-09-16-results.tsv`.

## Why this run exists

The skill went to `main` in `a3b8c9f` with no trigger measurement. The independent review of that
commit rated the description a MEDIUM finding: "Use this whenever a pull request review is asked for
in any wording" would fire on a GitHub pull request, and the skill then refuses instead of leaving
the ask to a code-review skill. `f124c4f` qualified the use-when clause with "Bitbucket" and added a
do-NOT clause for GitHub pull requests, local uncommitted changes, and a diff never opened as a pull
request. This run measures that wording.

## Method

Real `.claude/skills/` registration in two scratch git repositories, not skill-creator's
`.claude/commands/` loop, which measures recall far below reality (see the `session-cleanup` and
`clear-and-short` runs). `bb-proj` has `origin` on `bitbucket.org`, `gh-proj` on `github.com`; both
carry the skill under its real name and a two-line `scripts/hello.sh` for the file-review negative.
The installed twin was moved out of `~/.claude/skills/` for the run and moved back afterwards. Every
other user-level skill stayed registered, so the negatives competed against `retro`,
`plan-eng-review` and the rest.

One fresh `claude -p` per prompt, prompt on stdin, `--permission-mode bypassPermissions`,
`--max-turns 3`. Detection: the session transcript's first `"skill":"pr-review"`. Runs cut by the
turn cap report `error_max_turns`; that is expected for every fired positive and is not a failure.

## Results

| Query | Fixture | Result | Note |
| --- | --- | --- | --- |
| P1 "review PR 29" | bb | FIRED | |
| P2 pasted `bitbucket.org/.../pull-requests/300` URL | bb | FIRED | |
| P3 "review pull request 12 in mi9retail/nexus-transformation-service" | bb | FIRED | |
| P4 "Write me a PR review report for pull request 27 in ..., --no-comment" | bb | FIRED | |
| P5 "post a review comment on PR 300 in ..." | bb | FIRED | |
| P6 "do a code review of the open pull request 37 on Bitbucket, repo ..." | bb | FIRED | |
| N1 "review PR 29" | gh | FIRED | stopped inside the skill, see below |
| N2 "review https://github.com/Mi9-LLC/agent-skills/pull/2" | gh | quiet | |
| N3 "review my uncommitted changes before I commit them" | bb | quiet | answered with `git status` |
| N4 "code review of the diff between develop and my branch feature/x; no pull request yet" | bb | quiet | |
| N5 "review the code in scripts/hello.sh" | bb | quiet | reviewed the file inline |
| N6 "what did we ship this week?" | bb | quiet | fired `retro` |
| N7 "review this plan before we build it: ..." | bb | quiet | fired `plan-eng-review` |
| N8 "summarize what the pr-review skill in the Mi9 catalog does" | bb | quiet | |

Positives 6/6. Hard negatives 7/8 quiet.

## The one miss, and why it is left as is

N1 is a bare "review PR 29" in a repository whose `origin` is on GitHub. The description cannot
separate this from P1: the words are identical, and the model does not know the remote when it
decides whether to load a skill. The skill fired, then its own Arguments rule handled it. Its first
reply, from the transcript:

> I can't start this review yet — the repository is ambiguous. `git remote get-url origin` in the
> current working directory points at **GitHub**, not Bitbucket

It asked which Bitbucket repository was meant instead of guessing, and it did not fall back to `gh`.
That is the behaviour the skill body specifies for exactly this case. A description clause cannot
improve on it, because the discriminating fact is only available after the skill has loaded, so no
second variant was drafted. The explicit GitHub URL (N2) stays quiet, which is the case the
do-NOT clause was written for.

## Caveats

- One model, one run per prompt, no repeats. The `clear-and-short` run showed 1-in-6 variation on
  borderline phrasings across repeats; none of these prompts read as borderline, but a repeat would
  settle it.
- `--max-turns 3` means a fired positive never reached Composio. Whether the skill then behaves is
  the live run's question, not this one's (first live run: PR 300, 2026-09-16, Steps 1 to 7).
- The Bitbucket URL in P2 and the repository names in P3 to P6 are real. A fired positive under the
  turn cap read nothing from them.

# Pre-call sentence A/B: clear-and-short

Date: 2026-09-04
Model: claude-fable-5-1 (the default that `claude -p` picked; recorded from each transcript)
Claude Code: 2.1.260
Skill under test: `skills/clear-and-short/SKILL.md` with the 2026-09-04 edits (rule 2 pre-call
limit, rule 3 no comment on the question or the approach, first-sentence check after rule 9)
Control: the same file at commit c5de674

## Why this run exists

In an interactive session the skill was on and the reply to "is it safe to remove the local
"agent/STF-864-provision-order-refusal" branch?" opened with "Good question, and it's checkable
rather than a judgement call. Let me verify in both repos." The skill's rules 1, 2, and 8 already
forbid that sentence. The run measures whether the naming of this exact failure changes the model's
pre-call text, and where the pre-call text comes from.

## Method

- A scratch git repo with `main` and a local branch `agent/STF-864-provision-order-refusal`
  merged into `main` with `--no-ff`.
- The skill body (frontmatter removed) went in through `--append-system-prompt-file`, not through
  skill registration: the installed plugin cache still held the old text, so a registered skill
  would have tested the control in both arms. The description was not under test.
- One fresh `claude -p --output-format stream-json --verbose --permission-mode bypassPermissions`
  process per run, the question on stdin, in the scratch repo. `parse_preamble_ab.py` prints every
  assistant text block and tool call in order, so the text written before the first tool call is
  visible (the `json` output format hides it).
- Two conditions. Plain: the skill body alone. Harness: the skill body plus the interactive
  harness's sentence "Before you start, say in a line what you're about to do; brief updates while
  you work help the user follow along. Close with a short recap that stands on its own." That
  sentence is in the interactive system prompt and not in the `claude -p` one.
- 3 runs per arm per condition.

## Results

Plain condition, control text: 3 of 3 runs wrote no text before the tool call and opened with
"Yes." The failure did not reproduce.

Harness condition, text before the first tool call:

| Run | Control (c5de674) | New text |
|---|---|---|
| 1 | I'll check whether the branch's commits are already in main. | Checking the branch against main. |
| 2 | I'll check whether that branch's commits are already in main. | Checking whether the branch is merged into main. |
| 3 | I'll check whether that branch is fully merged into main. | Checking whether the branch is merged into main. |

Both arms answered "Yes, it is safe." with the merge commit named, in all 6 runs. No run in either
arm wrote "Good question" or a comment on the question.

## Reading

- The pre-call sentence comes from the harness instruction, not from the skill. With that sentence
  absent, the control text already writes nothing before the call.
- The new text turns the harness line into the short form the user asked for (3 of 3). The control
  writes a full narration sentence (3 of 3).
- The "Good question, and it's checkable rather than a judgement call" opening did not reproduce
  in 12 runs. Whether the session that produced it had the skill loaded is not known; its
  transcript was not checked.

## Not measured

- Interactive sessions. The harness sentence was pasted into the system prompt to stand in for
  them.
- Other models. All 12 runs were claude-fable-5-1.
- Triggering. The description is unchanged and was not re-run.

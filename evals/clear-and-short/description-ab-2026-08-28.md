# Description A/B: clear-and-short, real registration

Date: 2026-08-28 (run at 18:43 to 18:51, America/Toronto)
Model: claude-opus-5 (the default that `claude -p` picked; recorded from each transcript)
Claude Code: 2.1.251
Skill under test: `skills/clear-and-short/SKILL.md` at commit 898cd00, description 1256 characters
Control: the same file at commit cf10773, description 963 characters

## Why this run exists

Commit 5b06460 added five reply-directed voice phrases to the description ("humanize your
responses", "remove the AI tells", ...) and grew it from 961 to 1254 characters. The 6/6 recall
recorded in cf10773 was measured on the old text, so it no longer described the file on disk.

## Method

- The `clear-and-short` plugin was disabled (`claude plugin disable clear-and-short@mi9-agent-skills`)
  so its `UserPromptSubmit` hook could not load the skill by regular expression. Every transcript
  was checked for the hook's directive string; it appeared in 0 of 26 runs as hook context.
- The skill was registered only as `C:\Temp\cas-eval\.claude\skills\clear-and-short\SKILL.md`
  (a project-level copy in an otherwise empty folder). The control used a second folder,
  `C:\Temp\cas-eval-old`, with the cf10773 file. `unslop` and `document-generate` stayed installed
  at user level.
- One fresh `claude -p --output-format json --permission-mode bypassPermissions` process per prompt,
  prompt passed on stdin, 3 processes at a time. Group B ran with
  `--add-dir "C:\Develop\Mi9 Artifacts\Claude Skills"` so the file references resolve.
- Scored from the transcript at `~/.claude/projects/C--Temp-cas-eval/<session-id>.jsonl`:
  any `"name":"Skill"` call, which `"skill":"..."`, and whether the hook directive appeared.
- Runner: `run_description_ab.sh`; prompts: `description-ab-prompts.tsv`.

## Results, current description (898cd00)

Group A, voice asks, must fire. Result 5/6, A1 fired. Pass (threshold 5/6 with A1 mandatory).

| # | Prompt | Fired |
|---|---|---|
| A1 | Humanize your responses and remove the AI tells. | yes |
| A2 | Your replies sound like ChatGPT. Fix that, and tell me what hooks/hooks.json does. | yes |
| A3 | Stop writing like an AI. | yes |
| A4 | de-AI your answers from now on | yes |
| A5 | humanize your responses, and while you're at it, list the files under skills/ | yes |
| A6 | no more em dashes in your replies | no (replied "Understood, no em dashes.") |

Group B, length asks with a task attached, must fire. Result 4/6. Fail against the 6/6 threshold;
see the control below.

| # | Prompt | Fired |
|---|---|---|
| B1 | Be brief. What does scripts/git-retro.mjs compute? | no |
| B2 | Keep it short from now on. Which skills declare disallowed-tools? | no |
| B3 | You are too verbose. What does the retro skill do? | yes |
| B4 | Use fewer tokens. Summarize the repo layout. | yes |
| B5 | Stop narrating every tool call and check whether the README mentions the hook. | yes |
| B6 | Use simple English. Explain what marketplace.json does. | yes |

Group C, the same verbs aimed at files, must not fire. Result 0/8. Pass.

| # | Prompt | Fired | What loaded instead |
|---|---|---|---|
| C1 | Unslop the README intro. | no | nothing; asked which README (the scratch folder has none) |
| C2 | Humanize this README. | no | nothing; same |
| C3 | De-AI the docs under docs/agents/. | no | nothing; same |
| C4 | Make the release notes sound less like AI. | no | nothing; same |
| C5 | Write shorter commit messages for these changes. | no | nothing |
| C6 | Make this function shorter: function add(a, b) { return a + b; } | no | nothing |
| C7 | Summarize hooks/README.md in a few lines. | no | nothing |
| C8 | Write docs for the clear-and-short hook. | no | nothing; read hooks/README.md and reported it current |

The scratch folder is empty apart from the skill, so C1 to C4 do not measure routing to `unslop`;
they only show that `clear-and-short` did not claim them.

## Control, old description (cf10773), Group B only, same model

Result 3/6.

| # | Fired |
|---|---|
| B1 | no |
| B2 | no |
| B3 | yes |
| B4 | no |
| B5 | yes |
| B6 | yes |

## Reading

- The new description did not weaken the length trigger: 4/6 against 3/6 for the old text on the
  same model. The drop from the 6/6 recorded on 2026-08-27 comes from the model generation
  (2026-08-27 ran on the previous generation; this run picked claude-opus-5), not from the text.
- The brief's Group B fix (cut the voice phrase list from five to three) was therefore not applied.
  Decision taken by the user on 2026-08-28: keep the description as it is.
- B1 "Be brief." and B2 "keep it short from now on" with a task attached remain the weak spot.
  In real use the plugin's hook covers both deterministically; this measures the description alone.

## Findings outside the A/B

1. The plugin was found re-enabled at 18:39 after being disabled at 15:46 in the same session, with
   no `claude plugin enable` run by this session. A grid run in between measured the hook and was
   discarded. Verify `claude plugin list` immediately before every grid, not only at setup.
2. In the discarded grid the hook emitted its first-prompt voice directive on
   `Make this function shorter: function add(a, b) { return a + b; }` in a `claude -p` run whose
   transcript records `promptSource: "sdk"`. `hooks/clear-and-short-trigger.py` fires the default
   when the payload has no `source` field, so the `claude -p` payload apparently carries none. The
   hook's "does not fire in `claude -p`" claim (hooks/README.md, CLAUDE.md) does not hold on Claude
   Code 2.1.251. Fixed on 2026-08-29: the hook now also requires the environment variable
   `CLAUDE_CODE_ENTRYPOINT` to be `cli` or absent (it is `sdk-cli` under `claude -p`).
3. Two runner mistakes that void a grid: a `claude -p` process inherits the shell loop's stdin and
   reads it as extra input (pass the prompt on stdin explicitly); `--add-dir` takes several
   directories and swallows a following prompt argument.

## Voided runs

Three earlier grids from the same day were discarded: run 1 (prompt file leaked into every process
via stdin, and a session limit cut the last 5 runs), run 2 (plugin found re-enabled), and run 2's
control (same). Their raw outputs were not kept.

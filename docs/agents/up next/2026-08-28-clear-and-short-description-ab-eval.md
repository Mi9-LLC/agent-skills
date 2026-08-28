# Up next: re-measure the `clear-and-short` trigger description (A/B)

**Written** 2026-08-28 by the session that shipped commit `5b06460`.
**For** a fresh session, after a computer restart.
**Repo** `C:\Develop\Mi9 Artifacts\Claude Skills`, branch `main`, HEAD `5b06460` (pushed).
**Estimated effort** ~20 scripted `claude -p` runs, 15-30 min wall clock. The Group B subset alone is ~5 min.

---

## 1. Why this run exists

Commit `5b06460` widened `clear-and-short` to own reply-voice asks. Read its full commit
message first (`git show -s 5b06460`) - it states the problem, the fix, and what was left
undone.

The description grew from **961 to 1254 characters**. The previously measured score
(**6/6 recall, 6/6 hard negatives clean**, recorded in commit `cf10773`) was measured on the
961-character wording. It no longer describes what is on disk. Two things are unmeasured:

1. **Voice recall** - does the new wording actually fire on "humanize your responses"? This is
   the capability the commit added, and the reason the phrase failed in the first place.
2. **Length recall regression** - 293 added characters can dilute the clause that produced the
   6/6. This is the real risk of the change.

Precision (hard negatives) was already 100% and must stay there.

## 2. State you are inheriting

| Thing | State |
|---|---|
| `clear-and-short` | **Plugin only**: `clear-and-short@mi9-agent-skills`, user scope, enabled, cache pinned to commit `5b06460197ec`. No `npx` copy; absent from `~/.agents/.skill-lock.json` |
| `unslop` | `npx` global install at `~/.agents/skills/unslop`, symlinked to `~/.claude/skills/unslop`, in the lock file, identical to `5b06460` |
| The hook | `hooks/clear-and-short-trigger.py`, shipped by the plugin, active at user scope from the next session onward |
| `python` | 3.12.10 on PATH (the hook's only requirement) |
| Description lengths | `clear-and-short` 1254 chars, `unslop` 1146 chars |

Already verified in the shipping session, do not redo: 38/38 hook pattern cases
(`python "evals/clear-and-short/test_hook_patterns.py"`), hook run end-to-end over stdin JSON,
both frontmatters parse, README table rows / `##` sections / `skills/` dirs all 24.

## 3. THE TRAP - read before running anything

The hook is installed at **user scope**, so it fires in every project, scratch ones included.
It loads the skill by regular expression regardless of what the description says. Left enabled,
every recall prompt scores 100% and **the run measures nothing**.

```bash
claude plugin disable clear-and-short@mi9-agent-skills
claude plugin list          # must show: Status: disabled
```

Disabling the plugin removes the hook *and* the skill, which is exactly the "park the installed
twin" step the 2026-08-27 run used. The candidate then comes from the scratch project only.

**Invariant to check on every single run:** grep the transcript for
`Invoke the clear-and-short skill now`. If that string appears, the hook fired, and that run is
void.

The 2026-08-27 A/B predates the hook install, so it never had to handle this.

## 4. Setup

```bash
# 1. Scratch project, outside this repo
mkdir -p /c/Temp/cas-eval/.claude/skills
cd /c/Temp/cas-eval

# 2. Register the candidate at project level
cp -r "/c/Develop/Mi9 Artifacts/Claude Skills/skills/clear-and-short" .claude/skills/

# 3. Sanity: the candidate must be the 1254-char description
grep -c "humanize your responses" .claude/skills/clear-and-short/SKILL.md   # expect 1
```

Leave `unslop` and `document-generate` installed at user level. Group C measures *routing*, so
those two must be reachable, otherwise a negative looks clean for the wrong reason.

A project-level `.claude/skills/` in a brand-new directory may raise a folder-trust prompt on
first run. Not tested from print mode. If `claude -p` hangs or refuses, run `claude`
interactively in the scratch dir once to accept, then continue. `--permission-mode
bypassPermissions` is the fallback.

## 5. The prompt grid

20 prompts. **One fresh process per prompt** - once the skill loads, the rest of that session is
contaminated and repeats inside it measure nothing.

### Group A - voice recall (expect the skill to load)

| # | Prompt |
|---|---|
| A1 | `Humanize your responses and remove the AI tells.` |
| A2 | `Your replies sound like ChatGPT. Fix that, and tell me what hooks/hooks.json does.` |
| A3 | `Stop writing like an AI.` |
| A4 | `de-AI your answers from now on` |
| A5 | `humanize your responses, and while you're at it, list the files under skills/` |
| A6 | `no more em dashes in your replies` |

**A1 is the reported failure and the point of the whole change. A1 must fire.**

### Group B - length recall, regression check (expect the skill to load)

Task-attached shape, because `cf10773` found that shape was the weak one (it scored 1/6 on the
old wording before the fix).

| # | Prompt |
|---|---|
| B1 | `Be brief. What does scripts/git-retro.mjs compute?` |
| B2 | `Keep it short from now on. Which skills declare disallowed-tools?` |
| B3 | `You are too verbose. What does the retro skill do?` |
| B4 | `Use fewer tokens. Summarize the repo layout.` |
| B5 | `Stop narrating every tool call and check whether the README mentions the hook.` |
| B6 | `Use simple English. Explain what marketplace.json does.` |

These reference this repo's files, so run Group B with
`--add-dir "C:\Develop\Mi9 Artifacts\Claude Skills"` or point the questions at scratch files.
The answer's correctness does not matter - only whether `Skill` was called.

### Group C - hard negatives (expect the skill NOT to load)

| # | Prompt | Correct destination |
|---|---|---|
| C1 | `Unslop the README intro.` | `unslop` |
| C2 | `Humanize this README.` | `unslop` |
| C3 | `De-AI the docs under docs/agents/.` | `unslop` or `document-generate` |
| C4 | `Make the release notes sound less like AI.` | `unslop` |
| C5 | `Write shorter commit messages for these changes.` | no skill |
| C6 | `Make this function shorter: function add(a, b) { return a + b; }` | no skill |
| C7 | `Summarize hooks/README.md in a few lines.` | no skill |
| C8 | `Write docs for the clear-and-short hook.` | `document-generate` |

C1, C4-C7 mirror the six negatives from `cf10773`. C2 and C3 are new: they are the voice-boundary
cases this change introduced, where the same verbs point at a file instead of at the replies.

## 6. How to run and score

```bash
cd /c/Temp/cas-eval
SID=$(python -c "import uuid;print(uuid.uuid4())")
claude -p --session-id "$SID" --output-format json "Humanize your responses and remove the AI tells."

# transcript: ~/.claude/projects/<cwd-slug>/<SID>.jsonl
# slug = the cwd path with separators replaced by '-', e.g. C--Temp-cas-eval
T="$HOME/.claude/projects/C--Temp-cas-eval/$SID.jsonl"

grep -c '"name":"Skill"' "$T"                              # did any skill load
grep -o '"skill":"[^"]*"' "$T"                             # which one
grep -c 'Invoke the clear-and-short skill now' "$T"         # MUST be 0 (hook contamination)
```

A skill load appears in the transcript as
`"name":"Skill","input":{"skill":"clear-and-short"}`. Accept **both** `clear-and-short` and the
plugin-prefixed `clear-and-short:clear-and-short` - the prefix appears when the skill comes from
the plugin rather than from a project directory, and seeing the prefixed form during this run
means the plugin is still enabled (see section 3).

Worth writing a small loop over the 20 prompts that records prompt / kind / skill-loaded /
hook-string-present into one table. Record the model used - `claude -p` without `--model` uses
the session default, and the 2026-08-27 numbers were taken on a different model generation than
today's, so the two are not directly comparable.

## 7. Pass criteria and what to do on failure

| Group | Pass | On failure |
|---|---|---|
| A | 5/6, **A1 mandatory** | A1 fails, others pass: move the voice clause ahead of the length phrase list in the description. Several fail: the voice vocabulary is not carrying - add the exact failing phrasing to the phrase list |
| B | 6/6 | Dilution regression. Do **not** cut the "Invoke it on the first such request..." sentence - `cf10773` proves that sentence is what fixed the original under-triggering. Cut the voice phrase list from five entries to three (keep "humanize your responses", "remove the AI tells", "stop writing like an AI") and re-measure Group B only |
| C | 0/8 | Precision loss, the worse outcome. Strengthen the do-NOT clause with an explicit rule: a request naming a file, document, or piece of prose goes to `unslop`, whatever verb it uses |

Any description edit means re-running the group that failed **plus** Group C, since a wording
change can trade recall for precision in either direction.

## 8. When done

1. Record the grid and the results as a fixture under `evals/clear-and-short/` - mirror
   `evals/session-handoff/` (scenarios file + results file). `evals/` is development material;
   `npx skills add` never installs it, so nothing here reaches consumers.
2. Re-enable the hook: `claude plugin enable clear-and-short@mi9-agent-skills`, then confirm
   `claude plugin list` shows it enabled again. **This is easy to forget and silently leaves the
   user without the mechanism that makes the mode reliable.**
3. Delete `/c/Temp/cas-eval`.
4. Commit any description change plus the fixture. Repo rule (`CLAUDE.md` contributing section):
   a wording change to a skill also updates `README.md` (table row + per-skill section) and
   `CLAUDE.md`'s Current skills bullet in the same commit.

## 9. Two stale facts to ignore

- **`cf10773`'s message says "961 chars, under the 1024 truncation limit".** That limit does not
  hold in the current Claude Code version. The shipping session observed its own skill listing
  carrying the full 1254-character `clear-and-short` description and the full 1146-character
  `unslop` one, both ending on their last word, and `convert-plan-to-feature` ships 1239. Do not
  design the eval around a 1024 cutoff.
- **The `skill-creator` description-optimization loop is the wrong tool here.** It registers
  skills as `.claude/commands` files, which measures far below real registration (0-17% versus
  3/3 on the same wording). That is why this procedure uses real `.claude/skills/` registration.
  The loop also needs three Windows fixes re-applied before it runs at all.

## 10. Uncommitted files left behind

`git status` will show two additions from the shipping session, neither committed:

- `evals/clear-and-short/test_hook_patterns.py` - the 38-case hook pattern test, moved out of a
  session scratchpad so this document does not point at a deleted file. Run it with
  `python "evals/clear-and-short/test_hook_patterns.py"` from the repo root.
- `docs/agents/up next/` - this document.

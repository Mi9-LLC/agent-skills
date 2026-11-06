# Description trigger sweep: windows-disk-cleanup, real registration

Run on 2026-11-06, model `claude-opus-5-5`, against the description in the uncommitted
`skills/windows-disk-cleanup/SKILL.md` (862 characters). 15 prompts, one variant, one run each,
plus two re-runs of P5. The prompt set is `trigger-prompts.tsv`, the runner is
`run_trigger_sweep.sh`, the method and safety setup are in `evals.json`, and the raw per-prompt
rows (including both P5 re-runs) are `description-sweep-2026-11-06-results.tsv`.

## Method

The skill was registered through the user-level copy in `~/.claude/skills/windows-disk-cleanup`,
checked identical to the repository copy with `diff -r` before the run. One variant only, so no
copy was parked. Every other user-level skill stayed registered, so the negatives competed against
`session-cleanup`, `trim-initial-bundle` and the rest.

One fresh `claude -p` per prompt in a scratch git repository, `--max-turns 3`,
`--permission-mode dontAsk` with only `Skill`, `Read`, `Glob` and `Grep` allowed. Two canary prompts
checked the safety setup first: a file write through the Bash tool and one through the PowerShell
tool were both denied, and neither file existed afterwards. During the sweep, 13 of 15 runs tried
Bash or PowerShell and were denied, and the fixture repository was unchanged afterwards
(`git status` clean).

## Results

| Query | Expected | Result | Skills loaded |
| --- | --- | --- | --- |
| P1 "My C drive is almost full. What can I delete?" | fire | FIRED | windows-disk-cleanup |
| P2 "free up some disk space on this machine" | fire | FIRED | windows-disk-cleanup |
| P3 "what is taking all the space on my disk?" | fire | FIRED | windows-disk-cleanup |
| P4 pasted `du -sh` output, "what is safe to remove?" | fire | FIRED | windows-disk-cleanup |
| P5 "Cursor is uninstalled but its folders are still in my user profile. Can those go?" | fire | **quiet, 0/3** | none |
| P6 "I ran the disk cleanup commands from yesterday, check again ..." | fire | FIRED | windows-disk-cleanup |
| P7 "delete the temp files on my C drive, they are taking too much space" | fire | FIRED | windows-disk-cleanup |
| N1 "we're done here, clean up the branches and the scratch files" | quiet | quiet | session-cleanup |
| N2 "delete the temp files this task created under .scratch" | quiet | quiet | session-cleanup |
| N3 "how big is the src folder in this repo?" | quiet | quiet | none |
| N4 "remove the dead code in src/legacy" | quiet | quiet | none |
| N5 "rm -rf node_modules and reinstall the dependencies" | quiet | quiet | none |
| N6 "run npm cache clean --force" | quiet | quiet | none |
| N7 "my Ubuntu server's disk is full, what can I delete under /var?" | quiet | quiet | none |
| N8 "why is the dist bundle of this Vite app so big?" | quiet | quiet | trim-initial-bundle |

**Recall 6/7, precision 8/8.** P7 and N2 are the same request ("delete the temp files") with a
machine scope and a repository scope; each went to its own skill, so the overlap with
`session-cleanup`'s description did not cause a misfire.

## P5 is a real miss

P5 stayed quiet in all three runs. Each time the model went straight to listing the Cursor folders
with PowerShell (`$env:USERPROFILE\.cursor`, `$env:APPDATA\Cursor`, `$env:LOCALAPPDATA\Programs\cursor`
and others) instead of loading the skill. The description's use-when clause names freeing space,
finding what takes space, and which files or folders can be removed, but not the leftover folders of
an uninstalled program, and P5 never mentions disk space. The README lists this case as a trigger
phrase, so the README and the description disagree.

## Caveats

1. One run per prompt except P5. A single run does not establish a rate.
2. The denied tool calls end each run early. Whether a model that could run the shell would still
   load the skill first is not measured here; in this sweep the Skill call came before any denied
   call in every fired run that tried a shell.
3. P6 presupposes an earlier session that a fresh `claude -p` does not have. It fired anyway.

## Not measured

Whether the skill changes behaviour once loaded. The behaviour eval is still owed.

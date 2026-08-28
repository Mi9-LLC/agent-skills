# Hooks

Claude Code hooks shipped with the plugins in `.claude-plugin/marketplace.json`.

`npx skills add` installs skill files and nothing else, so a skill that needs a hook is
published as a plugin as well. That is the only reason this directory exists.

This directory holds the hook scripts themselves and no hooks declaration. Both plugins
declare their hooks inline in their own entry in `.claude-plugin/marketplace.json`. There is
no `hooks/hooks.json` and no per-plugin hooks file, and adding one would break things. Two
reasons, both checked against the installed Claude Code binary rather than the docs:

1. A marketplace entry rejects a hooks file path. The CLI errors with "hooks: the file-path
   and array forms are not yet supported in a marketplace entry. Define hooks in the plugin's
   own hooks/hooks.json (or its plugin.json), or inline them here as an object mapping hook
   event names to matcher arrays."
2. `hooks/hooks.json` auto-loads from the plugin root, and both entries use
   `"source": "./"` -- this repo's root. A hooks.json there would load into both plugins, so
   installing `execute-change` alone would silently register the `clear-and-short`
   `UserPromptSubmit` hook as well, turning on the voice default for someone who never asked
   for it.

## clear-and-short-trigger.py

A `UserPromptSubmit` hook for the `clear-and-short` skill. It reads the prompt from stdin
and, when the prompt asks for shorter, simpler, or less AI-sounding chat replies, prints a
directive telling Claude to load the skill. On any other prompt it prints nothing and the
prompt is unaffected, with one exception: the first prompt of a session gets the voice
directive by default, described below.

The hook exists because the skill's own description does not trigger reliably. A bare
"be brief" scored 0 out of 4 in testing: Claude answered briefly that one time without
loading the skill, so the mode never persisted. A regular expression either matches or it
does not, which is what makes the mode hold for the rest of the session.

Matching is deliberately narrow. Strong patterns name Claude's own replies and fire on their
own. Weak patterns such as "too verbose" or "ai tells" are ambiguous, so they fire only when
the prompt names no file, function, or document. Rewriting a file or a commit message is a
different job and belongs to the `unslop` skill.

The script sorts a match into two kinds, because they are not the same request. **Length**
("be brief", "too many words", "use fewer tokens") gets the directive to apply the whole
skill. **Voice** ("humanize your responses", "remove the AI tells", "stop writing like an
AI") gets a directive to apply the skill's voice and simple-English rules and leave the
length caps off: that user asked for a different voice, not for less content. A prompt
matching both gets the whole skill. Run `classify()` on a phrase to see which kind it is.

The voice directive is also the default, emitted once per session. On the first prompt of a
session that matches no pattern at all, the hook prints the voice directive and records the
session id in `~/.claude/.clear-and-short-sessions.json`. Replies are then plain from the
start, without anyone typing "humanize your responses". The first prompt was chosen over
every prompt for two reasons. Re-injecting the same text on every turn gains nothing, and it
would fight an explicit "normal mode" later in the session. Emitting once leaves the hook
quiet for the rest of the session, so a later matched prompt still works: "be brief"
upgrades to the length rules, "normal mode" turns the skill off.

A prompt that matches the skill's own patterns does two things: it prints its own directive,
exactly as it always did, and it closes out the default by recording the session id. That
second part matters when the match comes first. Without it, a session opening with "be
brief" would get the length rules, and then the next unrelated prompt would get the voice
directive, which says in so many words not to apply the length rules -- reversing what the
user asked for one turn earlier. Recording the session is best-effort: a matched prompt
prints its directive whether or not the write succeeds.

Entries in the seen file older than 7 days are pruned on the next write, and the file is
replaced atomically through a temporary file. A missing, unwritable, or corrupt file never
blocks a prompt: it counts as empty. What it does change is the default. An unmatched
prompt whose session could not be recorded gets no directive at all, rather than the same
one on every turn, and a payload with no session id is treated the same way, because
without an id the hook cannot tell a first prompt from a fiftieth. A matched prompt is
unaffected by any of that and always prints its directive.

## execute-change-watch.py, sweep-worktree-processes.ps1

Hooks for the `execute-change` skill, shipped as the second plugin entry,
`execute-change@mi9-agent-skills`. Its hooks are declared inline in that entry in
`.claude-plugin/marketplace.json`, the same as `clear-and-short`'s.

`execute-change-watch.py` is one Python script handling three events: `SubagentStart`,
`SubagentStop`, and `Notification`. All three fire in the parent session, not inside the
subagent. The script reads `<run root>/.claude/execute-change-run.json`, written once by the
`execute-change` lead session, and appends one JSON line per event to
`<run root>/.claude/execute-change-run.jsonl`. The run root is the directory the run works
in: the checkout the run was started from, or a dedicated worktree, chosen by a question at
preflight. The metadata file names it under the key `run_root`; the hook falls back to the
older key `worktree` so a run already in flight keeps working. If that metadata file is
absent, or its `session_id` does not match the payload's, the hook exits 0 and writes
nothing. That
pass-through rule is what keeps it inert in every session that is not an `execute-change`
run. It always exits 0: exit code 2 on `SubagentStop` would block the subagent from
stopping.

Two payload details are easy to get wrong. The `Notification` field carrying the text is
`message`, with an optional `title` beside it, not `notification_text`. The log key stays
`notification_text`, populated from `message`. And `SubagentStop` has no `stop_reason` field
at all, so nothing can test one; the stop event logs `agent_transcript_path` and
`stop_hook_active` instead. The transcript path is the useful one, because it lets the lead
read a failed subagent's transcript directly.

The lead arms a background watcher that re-reads the JSONL log every 180 seconds and speaks
only when something is wrong: a 9-minute subagent silence, or a `permission_prompt`,
`agent_needs_input`, or `idle_prompt` notification. There is no bad-stop condition in that
list because no field reports one. A failed step is caught by the lead's own acceptance
check after the subagent returns, against the acceptance-check table in `SKILL.md`. That
table is the gate; the watcher only says when to go and look.

`sweep-worktree-processes.ps1` is Windows-only cleanup of processes a finished subagent left
running -- `node`, test runners, shells. A process is selected only when its command line
contains the run root path or it descends from the current `claude` process, AND it started
at or after the run start, AND its executable is in a fixed allowlist. Selected processes
are killed with `taskkill /PID <n> /T /F`. `-WhatIf` lists them without killing. The run
root is passed in the `-Worktree` parameter, whose name predates the run-root choice and
is unchanged. One blind spot: `node script.js` launched with its working directory set to the
run root shows no run root path on its command line, so only the parent-chain rule catches
it. `Win32_Process` has no working-directory field.

## Installing

The hooks are not installed by `npx skills add`. Install the plugin that carries the one
you want:

```bash
claude plugin marketplace add Mi9-LLC/agent-skills
claude plugin install clear-and-short@mi9-agent-skills
claude plugin install execute-change@mi9-agent-skills
```

Restart the session. For `clear-and-short`, type "be brief" to confirm the skill loads.

Do not install `clear-and-short` both ways on one machine. `npx skills add` and the plugin
each register a skill under the same name, and only the plugin carries the hook.

## Requirements

`python` must be on the PATH and resolve to Python 3. On macOS and Linux the interpreter is
often `python3` only, and there a Python hook fails silently: nothing runs, and no error is
shown. `sweep-worktree-processes.ps1` is Windows-only and needs PowerShell.

## Editing the scripts

Change the scripts here, not the copies under `~/.claude/plugins/cache/`.
That cache is overwritten on every plugin update. Run `claude plugin marketplace update
mi9-agent-skills` to push a change from this repo into an installed plugin.

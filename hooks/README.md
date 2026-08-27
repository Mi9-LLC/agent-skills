# Hooks

Claude Code hooks shipped with the plugins in `.claude-plugin/marketplace.json`.

`npx skills add` installs skill files and nothing else, so a skill that needs a hook is
published as a plugin as well. That is the only reason this directory exists.

## clear-and-short-trigger.py

A `UserPromptSubmit` hook for the `clear-and-short` skill. It reads the prompt from stdin
and, when the prompt asks for shorter or simpler chat replies, prints a directive telling
Claude to load the skill. On any other prompt it prints nothing and the prompt is unaffected.

The hook exists because the skill's own description does not trigger reliably. A bare
"be brief" scored 0 out of 4 in testing: Claude answered briefly that one time without
loading the skill, so the mode never persisted. A regular expression either matches or it
does not, which is what makes the mode hold for the rest of the session.

Matching is deliberately narrow. Strong patterns name Claude's own replies and fire on their
own. Weak patterns such as "too verbose" are ambiguous, so they fire only when the prompt
names no file, function, or document to shorten. Shortening a file or a commit message is a
different job and belongs to the `unslop` skill.

## Installing

The hook is not installed by `npx skills add`. Install the plugin instead:

```bash
claude plugin marketplace add Mi9-LLC/agent-skills
claude plugin install clear-and-short@mi9-agent-skills
```

Restart the session, then type "be brief" to confirm the skill loads.

Do not install `clear-and-short` both ways on one machine. `npx skills add` and the plugin
each register a skill under the same name, and only the plugin carries the hook.

## Requirements

`python` must be on the PATH and resolve to Python 3. On macOS and Linux the interpreter is
often `python3` only, and there the hook fails silently: nothing runs, and no error is shown.

## Editing the script

Change `clear-and-short-trigger.py` here, not the copy under `~/.claude/plugins/cache/`.
That cache is overwritten on every plugin update. Run `claude plugin marketplace update
mi9-agent-skills` to push a change from this repo into an installed plugin.

# Brief for a re-check agent

Fill in every `<...>` and send the whole text as the agent's prompt. Send the same heartbeat rule
again in every follow-up message to the agent; agents have gone quiet after a follow-up that left
it out.

---

You are re-checking part of a dead-code analysis against the current code. READ-ONLY: do not
edit, create or delete any file except your one output file.

Repository: git worktree `<worktree path>`, detached at commit `<base sha>`. Read this
repository's code only from this path. For false-positive entry 14 you may also read sibling
repositories on disk, read-only. The analysis was written at commit `<analysis sha>`; `<N>`
commits have changed `<F>` files in the covered folders since
(`git diff --stat <analysis sha>..<base sha> -- <folders>`).
<Name the changed files that matter to this agent's scope, and tell it to read those diffs first.>

Your scope: `<plan sections>` of `<plan path>`, and the matching evidence in `<analysis files>`.
Skip these items; another agent checks them: `<items owned by the extra agent, or none>`.

For EVERY item in your scope:

1. Find it in the current code. Match the quoted code, not the line number. Record the current
   line.
2. Re-prove the claim from scratch with a search over the whole repository, excluding
   `node_modules`, `dist`, `bin`, `obj` and other build output. Do not skip an item because its
   file did not change since the analysis: some findings were wrong on the day they were written.
   Clear every relevant entry in the false-positive checklist below before you call an item
   VALID.
3. Give one verdict:
   - VALID: still unused (give the current line);
   - CHANGED: still unused, but moved, renamed, or a detail of the claim differs (say what);
   - INVALID: something uses it now, or the claim was wrong to begin with (give the file and line);
   - GONE: already deleted, or the named file does not exist or is not tracked by git.
4. Record the search you ran and what it returned. A verdict without its evidence does not count.

Also report:

- cascade items: code that becomes unused only because this step deletes something else;
- test files that exist only for the deleted code, and test cases inside shared test files that
  must go (file and line);
- documents that name the deleted code (file and line), and documents the plan lists that do not
  in fact name it;
- test-only items: code whose only references are tests, as a separate list;
- for a symbol used only inside its own file: "remove the export keyword only";
- anything in scope that is not dead code but a defect (a dependency never injected, a plugin
  never registered, a configuration value set under the wrong name). Report it; it is not a
  deletion;
- state that is written but never read (for example a store that production code writes and
  only tests read). Report it as a follow-up; removing it edits a live code path, so it is not a
  deletion either;
- for a file to delete that has a look-alike (the same file name in another folder): the
  look-alike's path, and the resolver result that shows nothing imports the file to delete.

Output: write the full result as markdown to `<output file outside the repository>`: a short
summary first (counts per verdict, and every INVALID, CHANGED and GONE item), then one table row
per item (item, old location, current location, verdict, evidence). Your final reply is the
summary only.

<Paste references/false-positives.md here.>

Heartbeat rule: this task has `<M>` steps (`<list them>`). After each step, report one line
`Step N/M: ...`. During any step that takes more than about 3 minutes, report a line at least
every 3 minutes saying what you are waiting on and what you have seen so far. Send every
status line with the messaging tool (SendMessage); only your final reply reaches the
coordinator, the rest of your plain text output does not. You may be pinged for status;
answer with the same `Step N/M:` line. Never end your turn to wait for a background command;
check its log file on a timer instead. Ending your turn sends your final reply to the
coordinator before your work is done, and for a foreground agent it also stops the command.
Never wait silently for input. You read incoming messages only between tool calls, so if you
need a decision, first finish waiting for any background command you started, then send the
question and end your turn; the answer resumes you. If a tool call is denied, if you are
blocked, or if a fact contradicts this brief, return immediately with what you have. Say
plainly when a check was skipped or could not be run; never describe an unrun check as passing.

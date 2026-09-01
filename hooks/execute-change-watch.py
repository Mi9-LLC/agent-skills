#!/usr/bin/env python3
"""SubagentStart / SubagentStop / Notification hook: keep a run log for an execute-change
run, and sweep leftover build processes out of the run's run root once the last subagent
has stopped. The run root is whichever directory preflight settled on -- the current
checkout, or a git worktree created for the run.

WHY this exists. The execute-change skill drives an hours-long run through one fresh
subagent per step, and the lead session deliberately keeps its own context small -- so the
lead cannot watch what the subagents do while they do it. Two things then go unnoticed: the
run stalls on a permission prompt with nobody looking at the terminal, and a step-6
implementer leaves a test watcher or a dev server holding files open inside the run root,
which makes the next step's dependency install or the close-out `git worktree remove` fail
for no visible reason. This hook records both in a file the lead can read cheaply, and
kills the leftover processes.

All three events fire in the PARENT session, not inside the subagent, so one script wired to
all three sees the whole run from one place.

INERT BY DEFAULT. The hook is installed per machine, so it runs in every session, including
every session that has nothing to do with execute-change. It therefore does nothing at all
unless <root>/.claude/execute-change-run.json exists AND names this exact session_id -- the
pass-through rule in _load_run below. Absent, unreadable, malformed, or naming a different
session all mean the same thing: return without writing anything.

WHERE <root> IS. The payload's `cwd` is the Bash tool's current working directory, not the
session's project root: a `cd` into a subdirectory persists between the lead's commands, and
a hook that fires while the shell sits there gets that subdirectory as `cwd`. Reading
<cwd>/.claude/... directly therefore missed every event fired while the shell was inside a
package directory (observed 2026-09-01: 4 of 8 SubagentStart events absent, and the matching
SubagentStop events present only because Claude Code had reset the directory by then). So
_find_root walks up from `cwd` until it finds a directory holding .claude/<META_NAME>, and
every read and write below uses that directory. The walk stops at the filesystem root; a
`cwd` outside the project (a worktree under ../<repo>.worktrees/) finds nothing and the hook
stays inert for that event, which is the pre-existing behavior for that case.

ALWAYS EXIT 0. Exit code 2 on SubagentStop tells Claude Code to block the subagent from
stopping and hand it the hook's stderr instead -- the opposite of what a watchdog should do.
A watchdog that can wedge the run it is watching is worse than no watchdog, so every path
here returns normally: malformed payload, unreadable log, crashed sweep, anything.

Appends are single short writes in "a" mode, one JSON object per line, so the parallel step-6
subagent groups cannot corrupt each other's writes -- nothing shares a mutable JSON document.
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

META_NAME = "execute-change-run.json"
LOG_NAME = "execute-change-run.jsonl"
SWEEP_NAME = "sweep-worktree-processes.ps1"
SWEEP_TIMEOUT_SECONDS = 60
LAST_MESSAGE_HEAD_CHARS = 200
MAX_LOG_LINES = 20000  # a runaway log must not turn the replay into the slow part


def _now() -> str:
    """ISO-8601 UTC timestamp."""
    stamp = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
    return stamp.replace("+00:00", "Z")


def _find_root(cwd):
    """Walk up from cwd to the nearest directory holding .claude/<META_NAME>; None if none."""
    if not cwd:
        return None
    try:
        here = os.path.abspath(cwd)
    except Exception:
        return None
    for _ in range(64):  # a bound, so a pathological path cannot loop
        if os.path.isfile(os.path.join(here, ".claude", META_NAME)):
            return here
        parent = os.path.dirname(here)
        if not parent or parent == here:
            return None
        here = parent
    return None


def _load_run(cwd, session_id):
    """Return the run metadata, or None when this session is not an execute-change run.

    This is the pass-through rule that keeps the hook inert everywhere else.
    """
    if not cwd or not session_id:
        return None
    try:
        with open(os.path.join(cwd, ".claude", META_NAME), "r", encoding="utf-8") as handle:
            meta = json.load(handle)
    except Exception:
        return None  # absent, unreadable, or malformed -- stay inert
    if not isinstance(meta, dict):
        return None
    if meta.get("session_id") != session_id:
        return None  # another session's run file -- not ours to append to
    return meta


def _append(cwd, event) -> None:
    """Append one JSON object as one line. Failure is swallowed on purpose."""
    try:
        line = json.dumps(event, ensure_ascii=True) + "\n"
        with open(os.path.join(cwd, ".claude", LOG_NAME), "a", encoding="utf-8") as handle:
            handle.write(line)  # one short append, so no lock is needed
    except Exception:
        return


def _replay(cwd):
    """Replay the whole log once and return (running agent ids, batch start timestamp).

    The batch start is the `at` of the most recent start event that took the running set from
    empty to non-empty -- that is, when the current batch of subagents began.

    A `resume` event is a hard reset. An interrupted run leaves `start` lines whose subagents
    died without ever emitting `stop`, so a replay over the whole log would hold them forever:
    the running set never empties again, the sweep never runs for the rest of the resumed run,
    and the batch start stays pinned at the first batch of the original run. The resume check
    appends the boundary event rather than truncating or renaming the log, because the history
    is worth keeping and a boundary event is what makes the replay correct without losing it.
    """
    running = []
    batch_started_at = None
    try:
        with open(os.path.join(cwd, ".claude", LOG_NAME), "r", encoding="utf-8") as handle:
            lines = handle.readlines()[:MAX_LOG_LINES]
    except Exception:
        return running, batch_started_at
    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        try:
            event = json.loads(raw)
        except Exception:
            continue  # a truncated line must not hide a still-running agent's stop
        if not isinstance(event, dict):
            continue
        kind = event.get("kind")
        agent_id = event.get("agent_id")
        if kind == "resume":
            running = []
            batch_started_at = None  # forget the interrupted run's batch entirely
            continue
        if kind == "start":
            if not running:
                batch_started_at = event.get("at")  # empty -> non-empty: a new batch begins
            running.append(agent_id)
        elif kind == "stop" and agent_id in running:
            running.remove(agent_id)
    return running, batch_started_at


def _sweep(cwd, meta, since) -> None:
    """Run the Windows process sweep and log its summary lines. Never raises."""
    # "worktree" is the pre-run-root name of this key: a run started before the rename
    # still has a metadata file carrying it, and that run must keep sweeping.
    run_root = meta.get("run_root") or meta.get("worktree")
    if not run_root or not since:
        return
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), SWEEP_NAME)
    if not os.path.isfile(script):
        return
    for shell in ("pwsh", "powershell"):
        try:
            done = subprocess.run(
                [
                    shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
                    "-Worktree", str(run_root), "-Since", str(since),
                ],
                capture_output=True,
                text=True,
                timeout=SWEEP_TIMEOUT_SECONDS,
            )
        except FileNotFoundError:
            continue  # pwsh is not installed -- fall back to powershell
        except Exception:
            return  # timeout or anything else: a failed sweep never blocks the hook
        lines = [ln.strip() for ln in (done.stdout or "").splitlines() if ln.strip()]
        if not lines:
            lines = ["no matching processes"]
        for line in lines:
            _append(cwd, {"kind": "sweep", "at": _now(), "line": line})
        return


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return  # never block on a malformed payload
    if not isinstance(payload, dict):
        return
    cwd = _find_root(payload.get("cwd"))  # the project root, not the shell's directory
    meta = _load_run(cwd, payload.get("session_id"))
    if meta is None:
        return
    event = payload.get("hook_event_name")
    if event == "SubagentStart":
        _append(cwd, {
            "kind": "start",
            "at": _now(),
            "agent_id": payload.get("agent_id"),
            "agent_type": payload.get("agent_type"),
        })
    elif event == "SubagentStop":
        head = payload.get("last_assistant_message") or ""
        if not isinstance(head, str):
            head = str(head)
        # No stop_reason here: the SubagentStop payload has no such field, and a key that is
        # always null would make a "stop_reason other than task_complete" test silently dead.
        # agent_transcript_path is what actually helps when a subagent goes wrong -- the lead
        # can read that subagent's transcript directly.
        _append(cwd, {
            "kind": "stop",
            "at": _now(),
            "agent_id": payload.get("agent_id"),
            "agent_transcript_path": payload.get("agent_transcript_path"),
            "stop_hook_active": payload.get("stop_hook_active"),
            "last_message_head": head[:LAST_MESSAGE_HEAD_CHARS],
        })
        # The last subagent stopping is the only moment when killing run-root processes is
        # safe: anything still alive there is a leftover of the batch that just finished.
        #
        # The window is the BATCH start, not the run start. Step 0 launches the run-root
        # preparation -- the dependency install plus one gate run -- as a background task that
        # keeps going while later steps run their subagents. It is a descendant of claude and
        # its executables (bash, npm, node) are all on the allowlist, so a run-start window
        # would let the first idle moment kill the install mid-flight, leaving the lead with a
        # half-installed run root and no baseline. Anything older than the batch is somebody
        # else's business; anything the just-finished batch spawned is still a candidate.
        running, batch_started_at = _replay(cwd)
        if not running and sys.platform == "win32":
            # Only an empty or unreadable log leaves no transition to use.
            _sweep(cwd, meta, batch_started_at or meta.get("started_at"))
    elif event == "Notification":
        # The payload field carrying the text is "message", not "notification_text". The log
        # key stays notification_text because the lead's watcher and the docs already grep it.
        _append(cwd, {
            "kind": "notify",
            "at": _now(),
            "notification_type": payload.get("notification_type"),
            "notification_text": payload.get("message"),
            "title": payload.get("title"),
        })


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # see ALWAYS EXIT 0 in the module docstring
    sys.exit(0)

#!/usr/bin/env bash
# stall-watcher.sh -- the execute-change lead's heartbeat watcher.
#
# Purpose: right after launching a subagent the lead arms this script with
# Bash(run_in_background: true). It stays quiet until something needs the lead's
# attention, then prints one verdict line and exits, which notifies the lead.
#
# Usage 1, the log watcher (default mode):
#   bash stall-watcher.sh "<absolute path of .claude/execute-change-run.jsonl>"
# It re-reads the heartbeat log every interval and exits on the first of:
# a permission_prompt / agent_needs_input / idle_prompt notification, every
# subagent stopped, or 3 consecutive silent checks with an agent still running
# (a 9-minute silence at the default interval). The verdict is the last stdout
# line: NOLOG, TROUBLE <type>: <text>, IDLE, STALL, or WATCHER ERROR. It also
# prints "alive: N agents running, oldest <age>" every 10 checks, which is 30
# minutes at the default interval.
#
# Usage 2, the fallback timer (when the log cannot be trusted):
#   bash stall-watcher.sh --fallback "<run root>"
# Prints one "tick ..." line naming the newest file in the run root, then exits.
#
# WATCH_INTERVAL overrides the sleep, 180 seconds in log mode and 175 in
# fallback mode. It exists for the tests only; a real run leaves it unset.
#
# Exits 0 in every case, a bad or missing argument included, so the lead's
# background task never looks like a crash.
set -u

usage() {
  echo "usage: stall-watcher.sh <absolute log path> | stall-watcher.sh --fallback <run root>"
  exit 0
}

if [ "$#" -eq 2 ] && [ "$1" = "--fallback" ]; then
  sleep "${WATCH_INTERVAL:-175}"
  echo "tick $(date -u +%H:%M:%SZ) newest-file: $(find "$2" -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort | tail -1)"
  exit 0
fi

[ "$#" -eq 1 ] || usage
case "$1" in
  --*) usage ;;
esac

LOG="$1"
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # the arm time: older events are not fresh activity
INTERVAL="${WATCH_INTERVAL:-180}"
silent=0; checks=0; prev_last=""; verdict=""
until [ -n "$verdict" ]; do
  sleep "$INTERVAL"
  checks=$((checks + 1))
  status=$(python - "$LOG" "$SINCE" <<'PY'
import datetime, json, sys
log, since = sys.argv[1], sys.argv[2]
iso = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
now = datetime.datetime.now(datetime.timezone.utc)
cut = iso(since)
try:
    lines = open(log, encoding="utf-8").read().splitlines()
except OSError:
    print("NOLOG"); raise SystemExit
running, last, trouble = {}, cut, ""
for line in lines:
    try:
        e = json.loads(line)
        at, kind = iso(e["at"]), e.get("kind")
    except Exception:
        continue
    # The running set is rebuilt from the WHOLE log: every start adds and every
    # stop removes, whatever their timestamps. cut is a separate question. A
    # resume boundary is a hard reset -- the interrupted run's subagents died
    # without a stop, so their starts would hold the set non-empty forever.
    if kind == "resume":
        running.clear()
        continue
    if kind == "start":
        running[e.get("agent_id")] = at
        continue
    if kind == "stop":
        running.pop(e.get("agent_id"), None)   # a stop carries no pass/fail signal
    elif kind != "notify":
        continue
    if at < cut:
        continue          # predates this watcher: not fresh activity, not trouble
    last = max(last, at)
    if kind == "notify" and e.get("notification_type") in (
            "permission_prompt", "agent_needs_input", "idle_prompt"):
        trouble = "%s: %s" % (
            e.get("notification_type"), e.get("notification_text"))
if trouble:
    print("TROUBLE " + trouble)
elif not running:
    print("IDLE")
else:
    age = int((now - min(running.values())).total_seconds())
    print("RUN %d %d %s" % (len(running), age, last.isoformat()))
PY
)
  case "$status" in
    NOLOG*)   verdict="NOLOG - no heartbeat log; the execute-change hooks are not installed" ;;
    TROUBLE*) verdict="$status" ;;
    IDLE*)    verdict="IDLE - all subagents stopped" ;;
    RUN*)     set -- $status
              if [ "$4" = "$prev_last" ]; then
                silent=$((silent + 1))
              else
                silent=0; prev_last="$4"
              fi
              if [ "$silent" -ge 3 ]; then
                verdict="STALL - $2 agent(s) running, no stop or notify event for 9 minutes"
              elif [ $((checks % 10)) -eq 0 ]; then
                echo "alive: $2 agents running, oldest $(($3 / 60))m"
              fi ;;
    *)        verdict="WATCHER ERROR - unexpected output: $status" ;;
  esac
done
echo "$verdict"

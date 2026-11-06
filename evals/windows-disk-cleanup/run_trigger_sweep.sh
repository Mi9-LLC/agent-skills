#!/bin/bash
# usage: bash run_trigger_sweep.sh <fixture-repo> <results-dir> [prompt-id-regex]
#
# Real-registration trigger sweep for the windows-disk-cleanup description. See evals.json.
#
# The skill under test is the user-level copy in ~/.claude/skills/windows-disk-cleanup (check it
# matches skills/windows-disk-cleanup in this repo before running). <fixture-repo> is a scratch git
# repository with src/math.js, src/legacy/old.js, .scratch/csv-import/vitest.log and a package.json,
# so the repository-scoped negatives have something to point at.
#
# SAFETY: this skill's prompts ask to delete files on the real machine. Every run uses
# --permission-mode dontAsk with only Skill, Read, Glob and Grep allowed, so any Bash, PowerShell,
# Edit or Write call is denied. Do NOT switch to bypassPermissions: the user-level settings default
# to it, and a prompt like "delete the temp files on my C drive" would then delete real files.
#
# One fresh `claude -p` per prompt, prompt on stdin (\n and \t in the TSV are expanded), capped at
# 3 turns. Detection is the transcript under ~/.claude/projects/<slug>/<session-id>.jsonl, first
# match of "skill":"windows-disk-cleanup".
FX="$1"; OUT="$2"; FILTER="${3:-.}"
PROMPTS="$(dirname "$0")/trigger-prompts.tsv"
mkdir -p "$OUT"
run() {
  id="$1"; expect="$2"; prompt="$3"
  SLUG=$(echo "$FX" | sed "s|^/c/|C:/|; s|[^A-Za-z0-9]|-|g")
  SID=$(python -c "import uuid;print(uuid.uuid4())")
  ( cd "$FX" && printf '%b' "$prompt" | claude -p --session-id "$SID" --output-format json --permission-mode dontAsk --allowedTools "Skill,Read,Glob,Grep" --max-turns 3 > "$OUT/$id.json" 2> "$OUT/$id.err" )
  T="$HOME/.claude/projects/$SLUG/$SID.jsonl"
  skills=$(grep -o '"skill":"[^"]*"' "$T" 2>/dev/null | sort -u | sed 's/"skill"://; s/"//g' | tr '\n' ' ')
  fired=quiet; echo " $skills " | grep -q ' windows-disk-cleanup ' && fired=FIRED
  denied=$(python -c "import json;d=json.load(open(r'$(cygpath -w "$OUT/$id.json")'));print(','.join(sorted({x['tool_name'] for x in d.get('permission_denials',[])})) or '-')" 2>/dev/null || echo NOJSON)
  model=$(grep -o '"model":"claude[^"]*"' "$T" 2>/dev/null | sort | uniq -c | sort -rn | head -1 | grep -o 'claude[^"]*')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$expect" "$fired" "${skills:--}" "$denied" "$model" "$SID" >> "$OUT/results.tsv"
}
while IFS=$'\t' read -r id expect prompt; do
  [ -z "$id" ] && continue
  echo "$id" | grep -qE "$FILTER" || continue
  run "$id" "$expect" "$prompt" &
  while [ "$(jobs -rp | wc -l)" -ge 3 ]; do sleep 2; done
done < "$PROMPTS"
wait
echo DONE

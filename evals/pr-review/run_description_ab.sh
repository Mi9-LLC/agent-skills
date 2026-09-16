#!/bin/bash
# usage: bash run_description_ab.sh <fixtures-dir> <results-dir> [prompt-id-regex]
#
# Real-registration trigger sweep for the pr-review description. See description-ab-2026-09-16.md.
#
# <fixtures-dir> holds two scratch git repositories, bb-proj (origin on bitbucket.org) and gh-proj
# (origin on github.com), each with the skill under test copied to .claude/skills/pr-review and a
# two-line scripts/hello.sh. Before running, move the installed twin OUT of ~/.claude/skills (a rename
# inside that directory does not park it), and move it back afterwards.
#
# One fresh `claude -p` per prompt, prompt on stdin, capped at 3 turns: enough for the Skill tool
# call to land in the transcript, not enough for a fired review to get past its first Composio call.
# Detection is the transcript under ~/.claude/projects/<slug>/<session-id>.jsonl, first match of
# "skill":"pr-review". A run cut by the cap reports subtype error_max_turns; that is expected and is
# not a failure of the prompt.
FX="$1"; OUT="$2"; FILTER="${3:-.}"
PROMPTS="$(dirname "$0")/description-ab-prompts.tsv"
mkdir -p "$OUT"
run() {
  id="$1"; fixture="$2"; prompt="$3"
  PROJ="$FX/$fixture-proj"
  SLUG=$(echo "$PROJ" | sed "s|^/c/|C:/|; s|[^A-Za-z0-9]|-|g")
  SID=$(python -c "import uuid;print(uuid.uuid4())")
  ( cd "$PROJ" && printf '%s' "$prompt" | claude -p --session-id "$SID" --output-format json --permission-mode bypassPermissions --max-turns 3 > "$OUT/$id.json" 2> "$OUT/$id.err" )
  T="$HOME/.claude/projects/$SLUG/$SID.jsonl"
  err=$(python -c "import json;d=json.load(open(r'$(cygpath -w "$OUT/$id.json")'));print(d.get('subtype') or ('ERR' if d.get('is_error') else 'ok'))" 2>/dev/null || echo NOJSON)
  n=$(grep -c '"name":"Skill"' "$T" 2>/dev/null); n=${n:-0}
  skills=$(grep -o '"skill":"[^"]*"' "$T" 2>/dev/null | sort -u | tr '\n' ' ')
  fired=quiet; echo "$skills" | grep -q '"skill":"pr-review"' && fired=FIRED
  model=$(grep -o '"model":"[^"]*"' "$T" 2>/dev/null | sort | uniq -c | sort -rn | head -1 | grep -o 'claude[^"]*')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$fixture" "$fired" "$err" "$n" "${skills:--}" "$model" "$SID" >> "$OUT/results.tsv"
}
while IFS=$'\t' read -r id fixture prompt; do
  [ -z "$id" ] && continue
  echo "$id" | grep -qE "$FILTER" || continue
  run "$id" "$fixture" "$prompt" &
  while [ "$(jobs -rp | wc -l)" -ge 3 ]; do sleep 2; done
done < "$PROMPTS"
wait
echo DONE

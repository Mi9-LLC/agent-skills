#!/bin/bash
# usage: bash run_description_ab.sh <scratch-project-dir> <results-dir> [prompt-id-regex]
# Prompts come from description-ab-prompts.tsv next to this script. See description-ab-2026-08-28.md.
# One fresh claude -p process per prompt; the prompt goes in on stdin (an inherited stdin would be read as extra input).
PROJ="$1"; OUT="$2"; FILTER="${3:-.}"
mkdir -p "$OUT"; cd "$PROJ" || exit 1
SLUG=$(echo "$PROJ" | sed "s|^/c/|C:/|; s|[^A-Za-z0-9]|-|g")
REPO="C:\Develop\Mi9 Artifacts\Claude Skills"
run() {
  id="$1"; prompt="$2"
  SID=$(python -c "import uuid;print(uuid.uuid4())")
  if [[ "$id" == B* ]]; then extra=(--add-dir "$REPO"); else extra=(); fi
  printf '%s' "$prompt" | claude -p --session-id "$SID" --output-format json --permission-mode bypassPermissions "${extra[@]}" > "$OUT/$id.json" 2> "$OUT/$id.err"
  T="$HOME/.claude/projects/$SLUG/$SID.jsonl"
  err=$(python -c "import json;d=json.load(open(r'$(cygpath -w "$OUT/$id.json")'));print('ERR' if d.get('is_error') else 'ok')" 2>/dev/null || echo NOJSON)
  n=$(grep -c '"name":"Skill"' "$T" 2>/dev/null); n=${n:-0}
  skills=$(grep -o '"skill":"[^"]*"' "$T" 2>/dev/null | sort -u | tr '\n' ' ')
  # hook directive only counts when it appears in a user-role message (hook additional context), not in file contents
  hook=$(grep -c 'Invoke the clear-and-short skill now' "$T" 2>/dev/null); hook=${hook:-0}
  model=$(grep -o '"model":"[^"]*"' "$T" 2>/dev/null | sort | uniq -c | sort -rn | head -1 | grep -o 'claude[^"]*')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$err" "$n" "${skills:--}" "$hook" "$model" "$SID" >> "$OUT/results.tsv"
}
while IFS=$'\t' read -r id prompt; do
  [ -z "$id" ] && continue
  echo "$id" | grep -qE "$FILTER" || continue
  run "$id" "$prompt" &
  while [ "$(jobs -rp | wc -l)" -ge 3 ]; do sleep 2; done
done < "$(dirname "$0")/description-ab-prompts.tsv"
wait
echo DONE

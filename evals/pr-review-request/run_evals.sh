#!/bin/bash
# usage: bash run_evals.sh <fixture-repo> <results-dir> <trigger|behaviour> [id-regex]
#
# Runs the prompts in evals.json against real .claude/skills registration. <fixture-repo> is a
# scratch git repository whose .claude/skills/pr-review-request is a copy of skills/pr-review-request
# from this repo (check with diff -r before running). The user-level pr-review, delegation-prompt
# and unslop stay installed, so the hard negatives compete against them.
#
# SAFETY: pr-review posts a review comment to Bitbucket without asking. Every run uses
# --permission-mode dontAsk with only Skill, Read, Glob and Grep allowed, so no MCP, Bash or Write
# call can run. Do NOT switch to bypassPermissions.
#
# trigger:   positives P* and hard negatives N*, --max-turns 3.
# behaviour: evals B<id>, --max-turns 10; the reply is saved to <results-dir>/<id>.reply.txt.
# One fresh `claude -p` per prompt, prompt on stdin, stream-json output. Detection is every
# "skill":"<name>" in that output. results.tsv columns: id, expected, pr-review-request fired,
# every skill loaded, denied tools, model.
FX="$1"; OUT="$2"; MODE="$3"; FILTER="${4:-.}"
EVALS="$(cd "$(dirname "$0")" && pwd)/evals.json"
mkdir -p "$OUT/prompts"
python - "$EVALS" "$OUT/prompts" "$MODE" <<'EOF'
import json, sys, pathlib
d = json.load(open(sys.argv[1], encoding='utf-8')); out = pathlib.Path(sys.argv[2])
if sys.argv[3] == 'trigger':
    rows = [(x['id'], 'fire', x['query']) for x in d['positives']] + [(x['id'], 'quiet', x['query']) for x in d['hard_negatives']]
else:
    rows = [('B%d' % x['id'], 'fire', x['prompt']) for x in d['evals']]
for i, expect, text in rows:
    (out / (i + '.' + expect + '.txt')).write_text(text, encoding='utf-8')
EOF
TURNS=3; [ "$MODE" = behaviour ] && TURNS=10
run() {
  f="$1"; id=$(basename "$f" | cut -d. -f1); expect=$(basename "$f" | cut -d. -f2)
  ( cd "$FX" && claude -p --output-format stream-json --verbose --permission-mode dontAsk --allowedTools "Skill,Read,Glob,Grep" --max-turns "$TURNS" < "$f" > "$OUT/$id.jsonl" 2> "$OUT/$id.err" )
  skills=$(grep -o '"skill":"[^"]*"' "$OUT/$id.jsonl" | sort -u | sed 's/"skill"://; s/"//g' | tr '\n' ' ')
  fired=quiet; echo " $skills " | grep -q ' pr-review-request ' && fired=FIRED
  python - "$OUT/$id.jsonl" "$OUT/$id.reply.txt" > "$OUT/$id.meta" <<'EOF'
import json, sys
denied, model, reply = set(), '-', ''
for line in open(sys.argv[1], encoding='utf-8'):
    try: e = json.loads(line)
    except ValueError: continue
    if e.get('type') == 'system' and e.get('model'): model = e['model']
    if e.get('type') == 'result':
        reply = e.get('result') or ''
        denied |= {x.get('tool_name', '?') for x in e.get('permission_denials', [])}
open(sys.argv[2], 'w', encoding='utf-8').write(reply)
print((','.join(sorted(denied)) or '-') + '\t' + model)
EOF
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$expect" "$fired" "${skills:--}" "$(cat "$OUT/$id.meta")" >> "$OUT/results.tsv"
}
for f in "$OUT"/prompts/*.txt; do
  basename "$f" | cut -d. -f1 | grep -qE "$FILTER" || continue
  run "$f" &
  while [ "$(jobs -rp | wc -l)" -ge 3 ]; do sleep 2; done
done
wait
echo DONE

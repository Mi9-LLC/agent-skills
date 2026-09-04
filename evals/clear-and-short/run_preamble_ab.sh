#!/bin/bash
# usage: bash run_preamble_ab.sh <arm> <n>   (arm = old | new | oldH | newH; the *H files carry the harness say-a-line sentence)
# Scratch paths: S is the scratchpad that held the test repo and the <arm>-skill.md system-prompt files. See preamble-ab-2026-09-04.md.
S="<scratchpad>"
arm="$1"; n="$2"; cd "$S/testrepo" || exit 1
printf '%s' 'is it safe to remove the local "agent/STF-864-provision-order-refusal" branch?' \
 | claude -p --append-system-prompt-file "$S/$arm-skill.md" --output-format stream-json --verbose --permission-mode bypassPermissions > "$S/outH/$arm-$n.jsonl" 2> "$S/outH/$arm-$n.err"
echo "done $arm-$n"

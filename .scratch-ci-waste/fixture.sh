#!/usr/bin/env bash
# Local fixtures for the deepen loop in "Pushed commits add no violations" (no network).
# After the step's fetch part runs in a depth-2 clone, the clone's base..HEAD and
# BEFORE..HEAD must equal origin's (no commit missing, none extra).
# Usage: fixture.sh <workflow file> <shape>
#   deep-side:  base 300 commits below the tip; a 500-commit side branch forked before base, merged below the tip
#   low-fork:   600 commits; base is commit 301; a 20-commit branch forked from commit 50, merged below the tip
#   linear:     base 300 commits below the tip, nothing else
set -euo pipefail
wf="$1" shape="$2"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@e -c init.defaultBranch=main "$@"; }
g init -q "$T/o"; o="$T/o"
c() { g -C "$o" commit -q --allow-empty -m "$1"; }
case "$shape" in
  deep-side)
    for i in $(seq 1 50); do c "pre $i"; done; fork=$(git -C "$o" rev-parse HEAD)
    c base; base=$(git -C "$o" rev-parse HEAD)
    for i in $(seq 1 300); do c "main $i"; done
    g -C "$o" checkout -q -b side "$fork"; for i in $(seq 1 500); do c "side $i"; done ;;
  low-fork)
    for i in $(seq 1 600); do c "main $i"; [[ $i == 50 ]] && fork=$(git -C "$o" rev-parse HEAD); [[ $i == 301 ]] && base=$(git -C "$o" rev-parse HEAD); done
    g -C "$o" checkout -q -b side "$fork"; for i in $(seq 1 20); do c "side $i"; done ;;
  linear)
    for i in $(seq 1 50); do c "pre $i"; done; c base; base=$(git -C "$o" rev-parse HEAD)
    for i in $(seq 1 300); do c "main $i"; done ;;
esac
if [[ "$shape" != linear ]]; then g -C "$o" checkout -q main; g -C "$o" merge -q --no-ff -m merge side; fi
c "tip-1"; c "tip"; head=$(git -C "$o" rev-parse HEAD); before=$(git -C "$o" rev-parse HEAD^)

awk '/- name: Pushed commits add no violations/{f=1} f&&/run: \|/{g=1;next} g&&/^      - name:|^      # `outcome`/{exit} g{print}' "$wf" \
  | sed -E 's/^          //' \
  | sed -E "s/^sidebar_from=.*/sidebar_from=$base/" \
  | sed -E 's/^( *)(python3 -I scripts\/cmux-next\/prepush-gate.py.*)$/\1true/; /^ *\| tee -a/d' > "$T/step.sh"

g init -q "$T/c"; g -C "$T/c" remote add origin "file://$o"
g -C "$T/c" -c protocol.file.allow=always fetch -q --no-tags --depth=2 origin "$head"; g -C "$T/c" checkout -q --detach "$head"
(cd "$T/c" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
  EVENT_NAME=push BEFORE="$before" GITHUB_SHA="$head" GITHUB_STEP_SUMMARY=/dev/null bash -e "$T/step.sh")
ok=PASS
for b in "$base" "$before"; do
  want=$(git -C "$o" rev-list "$b..$head" | sort); have=$(git -C "$T/c" rev-list "$b..HEAD" 2>/dev/null | sort)
  [[ "$want" == "$have" ]] || { ok=FAIL; echo "range ${b:0:8}..HEAD: origin $(wc -l <<<"$want"), clone $(wc -l <<<"$have")"; }
done
echo "$shape: clone depth $(git -C "$T/c" rev-list --count HEAD) of $(git -C "$o" rev-list --count "$head"): $ok"
[[ $ok == PASS ]]

#!/usr/bin/env bash
# Runs this checkout's "Pushed commits add no violations" step body on a fresh
# depth-2 clone of <head> (as actions/checkout fetch-depth: 2 leaves it), as a
# push whose before is <before>, and prints its time and the gate's verdicts.
# Usage: verify.sh <head> <before>
set -uo pipefail
head="$1" before="$2"
url=https://github.com/manaflow-ai/cmux.git
awk '/- name: Pushed commits add no violations/{f=1} f&&/run: \|/{g=1;next} g&&/^      - name:|^      # `outcome`/{exit} g{print}' \
  .github/workflows/cmux-next.yml | sed -E 's/^          //' > /tmp/step.sh
grep -n 'git fetch' /tmp/step.sh
dir=/tmp/clone
rm -rf "$dir"; git init -q "$dir"; git -C "$dir" remote add origin "$url"
s=$(date +%s)
git -C "$dir" fetch -q --no-tags --depth=2 origin "$head"; git -C "$dir" checkout -q --detach "$head"
echo "checkout: $(( $(date +%s) - s ))s"
s=$(date +%s)
(cd "$dir" && EVENT_NAME=push BEFORE="$before" GITHUB_SHA="$head" GITHUB_STEP_SUMMARY=/dev/null \
  timeout 900 bash -e /tmp/step.sh) 2>&1 | tail -6
echo "STEP rc=${PIPESTATUS[0]} $(( $(date +%s) - s ))s, depth $(git -C "$dir" rev-list --count HEAD), partial $(git -C "$dir" config extensions.partialclone), promisor $(git -C "$dir" config remote.origin.promisor)"
# PR form of the step: the sweep and the --base/--head gate.
s=$(date +%s)
(cd "$dir" && EVENT_NAME=pull_request BEFORE= GITHUB_SHA="$head" GITHUB_STEP_SUMMARY=/dev/null \
  timeout 900 bash -e /tmp/step.sh) 2>&1 | tail -3
echo "STEP (pull_request form, warm) rc=${PIPESTATUS[0]} $(( $(date +%s) - s ))s"

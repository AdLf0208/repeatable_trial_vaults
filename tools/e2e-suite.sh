#!/usr/bin/env bash
# The three e2e legs for repeatable_trial_vaults, one slot lease:
#   default         must exit 0 (loot, control, reset, loot, reload, loot)
#   counterfactual  must exit 0 (a stick cannot reset the rewarded vault)
#   negative        must exit non-zero (the counterfactual assertion inverted)
# Each leg keeps its transcript in /tmp/opencode/rtv-<leg>.{log,out}; the
# default leg also keeps the first launch's game log beside its transcript.
set -uo pipefail

PORT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/tmp/opencode}
cd "$PORT"

# Keep the suite's own output (exit codes included) beside the leg transcripts.
exec > >(tee "$OUT/rtv-suite.log") 2>&1

leg() { # name expected(0|nonzero) env...
    local name=$1 expected=$2
    shift 2
    rm -f "$OUT/repeatable_trial_vaults-e2e.log"
    echo "=== $name ==="
    env "$@" LOG="$OUT/rtv-$name-transcript.log" tools/e2e.sh \
        >"$OUT/rtv-$name.out" 2>&1
    local rc=$?
    grep -v '^{' "$OUT/rtv-$name-transcript.log" | tail -40
    echo "$name EXIT:$rc"
    if [ "$expected" = 0 ] && [ "$rc" -ne 0 ]; then
        echo "SUITE: $name had to exit 0" >&2
        return 1
    fi
    if [ "$expected" = nonzero ] && [ "$rc" -eq 0 ]; then
        echo "SUITE: $name had to exit non-zero" >&2
        return 1
    fi
}

leg default 0
leg counterfactual 0 COUNTERFACTUAL=1
leg negative nonzero COUNTERFACTUAL=1 NEGATIVE=1

echo "SUITE PASS: default 0, counterfactual 0, negative non-zero"

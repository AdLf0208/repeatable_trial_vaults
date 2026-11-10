#!/usr/bin/env bash
# Verification ladder for repeatable_trial_vaults at the campaign pin.
# Run inside a build slot:
#   ports/tools/build-slot.sh run --job new-vaults \
#       --port ports/repeatable_trial_vaults --step ladder -- \
#       env CARGO_INCREMENTAL=0 HORIZON_MIXINS=<pin>/horizon-mixins-5a64af9 \
#       tools/ladder.sh
# Writes one log per step under target/repin-41f822b/ and prints every exit code.
set -uo pipefail

PORT=$(cd "$(dirname "$0")/.." && pwd)
HORIZON=${HORIZON:-${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/ports/_shared/pins/horizon-41f822b}
LOGS=$PORT/target/repin-41f822b
mkdir -p "$LOGS"
cd "$PORT"

step() { # name command...
    local name=$1
    shift
    echo "=== $name ==="
    "$@" >"$LOGS/$name.log" 2>&1
    local rc=$?
    tail -n 25 "$LOGS/$name.log"
    echo "$(echo "$name" | tr '[:lower:]-' '[:upper:]_')_EXIT:$rc"
    return $rc
}

step fmt cargo fmt --all --check
step cargo-test cargo test --locked --offline
step clippy cargo clippy --all-targets --locked --offline -- -D warnings
step stage python3 tools/horizon.py stage --horizon "$HORIZON"
step check python3 tools/horizon.py check --horizon "$HORIZON"
step test python3 tools/horizon.py test --horizon "$HORIZON"
step build python3 tools/horizon.py build --horizon "$HORIZON"

echo "=== warnings in the staged build logs ==="
grep -c '^warning' "$LOGS/check.log" "$LOGS/test.log" "$LOGS/build.log" 2>/dev/null || true

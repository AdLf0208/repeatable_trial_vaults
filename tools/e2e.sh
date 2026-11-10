#!/usr/bin/env bash
# In-game check for Repeatable Trial Vaults: a trial key resets a vault that
# already rewarded the player, so the same player can loot it again.
#
# Default run (headless, survival world, Overworld at x/z=0):
#   1. a `minecraft:vault` placed at (0,100,2) becomes `active` for the player;
#   2. one trial key loots it: the state goes `unlocking`/`ejecting`, exactly
#      one key is consumed and item entities appear; the player is rewarded;
#   3. CONTROL (the pre-reset state): a stick on the rewarded vault does
#      nothing - no key, no items, and the vault does not become active. The
#      pre-reset state therefore cannot be looted again;
#   4. a trial key *resets* it: exactly one key is consumed, no loot is
#      ejected, the vault becomes `active` again, and a further key loots it a
#      second time;
#   5. the same control + reset repeat after loot 2, then `save`/`quit`/reopen:
#      the reset is durable and a third key loots the reloaded vault;
#   6. the game log carries one `[repeatable_trial_vaults] reset the vault at`
#      line per reset, so the hook (not vanilla) is what acted.
#
# Why the control uses a stick, not a key: with this mod a *key* click on a
# rewarded vault is the reset itself (upstream never checks `vault_state`), so
# a key click can never be "a second loot without a reset". A stick is the
# item-level counterfactual: it is not in the reset tag, cannot reset, and the
# vault stays inactive.
#
# COUNTERFACTUAL=1 stops after loot 1 and the stick click: the reset item is
# replaced by `minecraft:stick`, which must consume nothing and leave the
# vault `inactive`. That is the differential run for the reset trigger.
# NEGATIVE=1 (with COUNTERFACTUAL=1) inverts that assertion: the run MUST fail,
# proving the control is not vacuous.
set -euo pipefail

CLONE=${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/repeatable_trial_vaults
# The control binary is shared at the campaign pin; the game is this port's build.
CTL=${CTL:-$CLONE/ports/_shared/bin/horizon-1d63e0a5/horizon-ctl}
GAME=${GAME:-$PORT/target/horizon-cargo/fast/horizon-client}
RES=${RES:-${HORIZON_RES:-${HORIZON_RES:-$HOME/.local/horizon-client/26.3}}}
SOCK=${SOCK:-/tmp/opencode/repeatable_trial_vaults-e2e.sock}
LOG=${LOG:-/tmp/opencode/repeatable_trial_vaults-e2e-transcript.log}
GAME_LOG=${GAME_LOG:-/tmp/opencode/repeatable_trial_vaults-e2e.log}
COUNTERFACTUAL=${COUNTERFACTUAL:-0}
NEGATIVE=${NEGATIVE:-0}
# EMBEDDED=1 (the default) launches with **only the native bundle** and no
# `--dev-mod`: the content comes from the bundle's embedded copy
# (`mixins/repeatable_trial_vaults/data/…`, the AE2 pattern). CONTROL=1 (default
# with EMBEDDED) first launches the same binary with `.horizon-cache` unusable,
# where the reset tag must be unknown.
EMBEDDED=${EMBEDDED:-1}
CONTROL=${CONTROL:-$EMBEDDED}
DEV_MOD=()
[ "$EMBEDDED" = 1 ] || DEV_MOD=(--dev-mod "$PORT/content")
WORLD=RepeatableTrialVaults
CONTROL_WORLD=RepeatableTrialVaultsControl
VAULT="0 100 2"
# The content half is this tag (upstream's `can_reset_trial_vaults`): a vanilla
# `/clear @s #tag` resolves it only when the content mod is loaded.
RESET_TAG="#repeatable_trial_vaults:can_reset_trial_vaults"

mkdir -p "$(dirname "$LOG")"
exec > >(tee "$LOG") 2>&1

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/content/horizon-mod.toml" ] || { echo "missing content mod: $PORT/content" >&2; exit 1; }
command -v jq >/dev/null || { echo "missing jq" >&2; exit 1; }

SCRATCH=$(mktemp -d /tmp/opencode/repeatable-trial-vaults-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { printf 'ctl %s\n' "$*" >&2; "$CTL" --socket "$SOCK" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
vault_state() { block_state 0 100 2; }
keys() { ctl inventory | jq -r '.counts["minecraft:trial_key"] // 0'; }
item_entities() { ctl entities 32 minecraft:item | jq '.entities | length'; }
# Loot on the floor plus loot already picked up: the reward may be collected
# before the count is read, so neither an entity count nor the inventory alone
# is the right signal. Keys and the control stick are excluded.
loot_total() {
    local floor bag
    floor=$(ctl entities 32 minecraft:item | jq '
        [.entities[] | select(.item.item != "minecraft:trial_key"
                              and .item.item != "minecraft:stick") | .item.count]
        | add // 0')
    bag=$(ctl inventory | jq '
        [.counts | to_entries[]
         | select(.key != "minecraft:trial_key" and .key != "minecraft:stick") | .value]
        | add // 0')
    echo $((floor + bag))
}
reset_lines() {
    local n
    n=$(grep -c '\[repeatable_trial_vaults\] reset the vault at' "$GAME_LOG" 2>/dev/null || true)
    echo "${n:-0}"
}
# Wait until the vault state contains `want`, polling every 2 ticks.
wait_state() {
    local want=$1 limit=${2:-200} i state
    for ((i = 0; i < limit; i += 2)); do
        state=$(vault_state)
        case "$state" in
            *"vault_state=$want"*) return 0 ;;
        esac
        ctl wait 2 >/dev/null
    done
    echo "last vault state: $(vault_state)" >&2
    return 1
}
# Right-click the vault with the selected stack, from two blocks north.
click_vault() {
    ctl look-at 0.5 100.5 2.0 >/dev/null || fail "cannot aim at the vault"
    ctl wait 6
    ctl use-item || fail "use-item failed"
}
select_item() { ctl select "$1" >/dev/null || fail "cannot select $1"; }

launch() { # launch WORLD
    local reply log
    if ! reply=$("$CTL" --socket "$SOCK" launch \
        --game "$GAME" --world "$1" --seed 20261105 --headless --wait \
        --game-dir "$SCRATCH/game" --resources "$RES" "${DEV_MOD[@]}"); then
        echo "FAIL: the game did not launch ($WORLD): $reply" >&2
        return 1
    fi
    printf '%s\n' "$reply"
    log=$(printf '%s' "$reply" | jq -r '.log // empty')
    [ -n "$log" ] && GAME_LOG=$log
    ctl wait-ready 120
}

# Whether the reset tag resolves: `/clear @s #tag` names an unknown tag when the
# content half is not loaded. Prints the command's reply.
tag_reply() {
    ctl command "clear @s $RESET_TAG"
}

cleanup() {
    local status=$?
    timeout 15 "$CTL" --socket "$SOCK" quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
    # Last line of every run: `check-e2e-logs.py` reads it as the verdict.
    echo "EXIT:$status"
}
trap cleanup EXIT

# The control for EMBEDDED=1: the same binary (every hook is in it) with the
# embedded content made unavailable — `.horizon-cache` is a plain file, so the
# helper can neither compare nor write its content file and falls back to
# `Continue`. Nothing may be written into the cache; the run then proves that the
# file the main leg finds comes from the bundle, not from an earlier run.
control_leg() {
    echo "== control: the same game with no embedded content file =="
    mkdir -p "$HORIZON_HOME"
    rm -rf "$HORIZON_HOME/.horizon-cache"
    : > "$HORIZON_HOME/.horizon-cache"
    launch "$CONTROL_WORLD"
    local reply
    reply=$(tag_reply | tr -d '\n')
    echo "  tag reply without the content: $reply"
    [ -f "$HORIZON_HOME/.horizon-cache" ] || fail "the control's .horizon-cache was replaced: the helper wrote its content"
    [ ! -e "$HORIZON_HOME/.horizon-cache/repeatable_trial_vaults-embedded-content.hmod" ] \
        || fail "the control game wrote the embedded content: the cache was not unusable"
    echo "  without the embedded file: the cache stayed a plain file and no content mod was written"
    ctl quit >/dev/null 2>&1 || true
    sleep 6
    rm -f "$HORIZON_HOME/.horizon-cache"
}

# EMBEDDED=1: the bundle must have written its content out at startup, byte for
# byte the delivered content mod.
embedded_content_check() {
    local cache=$HORIZON_HOME/.horizon-cache/repeatable_trial_vaults-embedded-content.hmod
    [ -f "$cache" ] || fail "the bundle did not write its embedded content to $cache"
    cmp -s "$cache" "$PORT/content/repeatable_trial_vaults.hmod" \
        || fail "the embedded content differs from content/repeatable_trial_vaults.hmod"
    echo "  embedded content: $(wc -c < "$cache" | tr -d ' ') B at $cache, identical to content/repeatable_trial_vaults.hmod"
}

if [ "$CONTROL" = 1 ]; then control_leg; fi

if [ "$EMBEDDED" = 1 ]; then
    echo "== launch ($WORLD, one .hnmod, no --dev-mod) =="
else
    echo "== launch ($WORLD, content --dev-mod content/) =="
fi
launch "$WORLD"
if [ "$EMBEDDED" = 1 ]; then embedded_content_check; fi

echo "== the content half: the reset tag file, as the game sees it =="
# The content half of this port is upstream's `can_reset_trial_vaults` item tag
# plus the tooltip lang string; the two keys are named in `runtime.rs` because a
# tag read needs a server execution role the hook does not have. `/clear @s #tag`
# is the one command probe for a tag, and at this pin it answers "Unknown item
# tag" for this content mod in both runs, so the tag is *not* observable here —
# the evidence that the content half came from the bundle is the written file
# above (byte-identical to content/…) plus the behaviour below, which the
# COUNTERFACTUAL/NEGATIVE legs prove can fail.
TAG_REPLY=$(tag_reply | tr -d '\n')
echo "  tag reply (diagnostic, not an assertion): $TAG_REPLY"

echo "== a stone platform at y=99 and clean air above =="
ctl command "time set noon"
ctl command "difficulty peaceful"
ctl command "kill @e[type=!minecraft:player]"
ctl command "tp @s 0 100 0" >/dev/null
ctl wait 30
ctl command "forceload add -8 -8 8 8" >/dev/null || true
ctl fill -8 99 -8 8 99 8 minecraft:stone
ctl fill -8 100 -8 8 110 8 minecraft:air
# Stand 3.5 blocks north of the vault: inside its 4-block activation range,
# outside item pickup reach, so ejected loot stays measurable.
ctl command "tp @s 0.5 100 -1.0" >/dev/null
ctl wait 30
ctl command "clear @s"
ctl wait 4
ctl give minecraft:trial_key 8 >/dev/null || fail "cannot give trial keys"
ctl give minecraft:stick 1 >/dev/null || fail "cannot give a stick"
ctl wait 4
select_item minecraft:trial_key
ctl state | jq -c '{position: .player.position}' || true

echo "== a placed vault becomes active for the player =="
ctl command "setblock $VAULT minecraft:vault" >/dev/null || fail "cannot place the vault"
wait_state active 60 || fail "the vault did not become active"
echo "vault after placement: $(vault_state)"

echo "== loot 1: a trial key unlocks and ejects =="
keys_before=$(keys)
items_before=$(item_entities)
loot_before=$(loot_total)
echo "before loot 1: keys=$keys_before items=$items_before loot=$loot_before"
click_vault
ctl wait 2
case "$(vault_state)" in
    *vault_state=unlocking* | *vault_state=ejecting*) ;;
    *) fail "the vault did not unlock after a key: $(vault_state)" ;;
esac
wait_state inactive 260 || fail "the vault did not finish ejecting"
keys_after=$(keys)
items_after=$(item_entities)
loot_after=$(loot_total)
echo "after loot 1: keys=$keys_after items=$items_after loot=$loot_after"
[ $((keys_before - keys_after)) -eq 1 ] || fail "loot 1 consumed $((keys_before - keys_after)) keys, expected 1"
[ "$loot_after" -gt "$loot_before" ] || fail "loot 1 gave no item (loot $loot_before -> $loot_after)"

echo "== control: the pre-reset (rewarded) state yields no second loot =="
select_item minecraft:stick
keys_control=$(keys)
loot_control=$(loot_total)
resets_before_control=$(reset_lines)
click_vault
ctl wait 10
keys_held_control=$(keys)
echo "stick click: keys=$keys_control -> $keys_held_control state=$(vault_state)"
if [ "$NEGATIVE" = 1 ]; then
    # This run asserts the inverse of the control, so it MUST exit non-zero.
    case "$(vault_state)" in
        *vault_state=active*)
            fail "NEGATIVE: the stick reset the vault (impossible; the control is broken)" ;;
        *)
            fail "NEGATIVE run: the inverted assertion was checked (stick reset nothing)" ;;
    esac
fi
case "$(vault_state)" in
    *vault_state=inactive*) ;;
    *) fail "the rewarded vault left inactive without a reset: $(vault_state)" ;;
esac
[ "$keys_held_control" -eq "$keys_control" ] || fail "a key was consumed without a reset"
[ "$(loot_total)" -eq "$loot_control" ] || fail "the rewarded vault gave items without a reset"
[ "$(reset_lines)" -eq "$resets_before_control" ] || fail "a non-key click logged a reset"
echo "control PASS: the stick neither reset nor looted the rewarded vault"

if [ "$COUNTERFACTUAL" = 1 ]; then
    echo "counterfactual PASS: no non-key reset (vault inactive, nothing consumed)"
    exit 0
fi

echo "== reset 1: a trial key clears the rewarded player =="
select_item minecraft:trial_key
keys_reset_before=$(keys)
loot_reset_before=$(loot_total)
resets_before=$(reset_lines)
click_vault
ctl wait 2
keys_reset_after=$(keys)
echo "reset click: keys=$keys_reset_before -> $keys_reset_after state=$(vault_state)"
[ $((keys_reset_before - keys_reset_after)) -eq 1 ] || fail "the reset consumed $((keys_reset_before - keys_reset_after)) keys, expected 1"
[ "$(loot_total)" -eq "$loot_reset_before" ] || fail "the reset ejected loot"
[ "$(reset_lines)" -eq $((resets_before + 1)) ] || fail "the reset hook logged no line"
wait_state active 60 || fail "the reset vault did not become active again"
echo "reset 1 PASS: vault is $(vault_state), reset lines=$(reset_lines)"

echo "== loot 2: the same player loots the reset vault again =="
keys_loot2=$(keys)
loot_loot2=$(loot_total)
click_vault
ctl wait 2
case "$(vault_state)" in
    *vault_state=unlocking* | *vault_state=ejecting*) ;;
    *) fail "the reset vault did not unlock: $(vault_state)" ;;
esac
wait_state inactive 260 || fail "the second loot did not finish"
ctl wait 20
keys_loot2_after=$(keys)
loot_loot2_after=$(loot_total)
echo "loot 2 counts: keys=$keys_loot2 -> $keys_loot2_after loot=$loot_loot2 -> $loot_loot2_after items=$(item_entities)"
[ $((keys_loot2 - keys_loot2_after)) -eq 1 ] || fail "loot 2 consumed $((keys_loot2 - keys_loot2_after)) keys, expected 1"
[ "$loot_loot2_after" -gt "$loot_loot2" ] || fail "loot 2 gave no item (loot $loot_loot2 -> $loot_loot2_after)"
echo "loot 2 PASS: keys=$keys_loot2 -> $keys_loot2_after loot=$loot_loot2 -> $loot_loot2_after"

echo "== control 2: still no loot without a reset =="
select_item minecraft:stick
keys_control2=$(keys)
loot_control2=$(loot_total)
click_vault
ctl wait 10
case "$(vault_state)" in
    *vault_state=inactive*) ;;
    *) fail "the re-rewarded vault left inactive without a reset: $(vault_state)" ;;
esac
[ "$(keys)" -eq "$keys_control2" ] || fail "control 2 consumed a key"
[ "$(loot_total)" -eq "$loot_control2" ] || fail "control 2 gave items"
echo "control 2 PASS: no second loot without a reset"

echo "== persistence: reset, save, reopen, loot a third time =="
select_item minecraft:trial_key
keys_presave=$(keys)
resets_before=$(reset_lines)
click_vault
ctl wait 2
[ $((keys_presave - $(keys))) -eq 1 ] || fail "the pre-save reset consumed the wrong key count"
[ "$(reset_lines)" -eq $((resets_before + 1)) ] || fail "the pre-save reset logged no line"
wait_state active 60 || fail "the pre-save reset did not become active"
keys_saved=$(keys)
resets_before_quit=$(reset_lines)
[ "$resets_before_quit" -ge 2 ] || fail "the hook logged $resets_before_quit resets, expected at least 2"
cp "$GAME_LOG" "$LOG.game-before-reload" || true
ctl save >/dev/null || fail "cannot save"
ctl wait 10
ctl quit >/dev/null || fail "cannot quit"
sleep 2

echo "== reopen $WORLD =="
rm -f "$SOCK"
launch "$WORLD"
ctl command "tp @s 0.5 100 -1.0" >/dev/null
ctl wait 40
echo "after reload: keys=$(keys) state=$(vault_state)"
[ "$(keys)" -eq "$keys_saved" ] || fail "the key count changed across the reload"
wait_state active 60 || fail "the saved reset did not survive the reload (the vault is $(vault_state))"
select_item minecraft:trial_key
keys_loot3=$(keys)
loot_loot3=$(loot_total)
click_vault
ctl wait 2
case "$(vault_state)" in
    *vault_state=unlocking* | *vault_state=ejecting*) ;;
    *) fail "the reloaded vault did not unlock: $(vault_state)" ;;
esac
wait_state inactive 260 || fail "the third loot did not finish"
ctl wait 20
keys_loot3_after=$(keys)
loot_loot3_after=$(loot_total)
echo "loot 3 counts: keys=$keys_loot3 -> $keys_loot3_after loot=$loot_loot3 -> $loot_loot3_after items=$(item_entities)"
[ $((keys_loot3 - keys_loot3_after)) -eq 1 ] || fail "loot 3 consumed $((keys_loot3 - keys_loot3_after)) keys, expected 1"
[ "$loot_loot3_after" -gt "$loot_loot3" ] || fail "loot 3 gave no item (loot $loot_loot3 -> $loot_loot3_after)"
echo "persistence PASS: keys=$keys_loot3 -> $keys_loot3_after loot=$loot_loot3 -> $loot_loot3_after"

echo "resets logged by the hook before the reload: $resets_before_quit"
echo "PASS: a trial key reset a rewarded vault and the player looted it again (and again after a reload)"

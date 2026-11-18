# Repeatable Trial Vaults — port notes

> **Format (2026-11-18): the port is now a flat SDK `.hmod`.** Horizon retired `.hnmod` in the
> mod-API merge (#16941, launcher ≥ 0.2.70); the bundle this file described below (PR #658, closed)
> was migrated to `horizon-mod.toml` + `Cargo.toml` + `src/lib.rs` (`impl mod_api::Hooks`) +
> `assets/`/`data/` at Horizon **`0b14f8acfd97fa2c750e42795249dcc981178ca4`** / horizon-mixins
> **`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, mod API `0.2`. Read
> **`## Migration to the SDK format`** and **`## Migration verification (SDK 0b14f8a)`** at the end
> of this file first: they are the current state. Everything above them is the history of the
> retired bundle (pin `41f822b6`/`1d63e0a5`, `.hnmod`, `mixins/`, the staging ladder) and is kept
> as the record, not as instructions — none of `tools/horizon.py`, `compatibility.json`,
> `mixins/<id>/` or the `.hnmod` exists any more.

Ported from **Repeatable Trial Vaults 1.0.3**
(`Buuz135/Repeatable-Trial-Vaults`, commit
`23a2529bc488eaee0843991ffb3b872f38c968b3`) for Minecraft Java 26.3 on Horizon
**41f822b6** (main, 2026-11-06; 432 hooks / 174 helpers) / horizon-mixins
**5a64af9** (0.6.0, schema 6). Originally written at `c9d474d` / `d9c83d7` and
re-pinned on 2026-11-07 (migration table below); the old pin's evidence did not
survive, so every result in this file was re-run at the new pin.

**Licence:** `gradle.properties` says `license=MIT`; the repository's `LICENSE`
file is the CC0 1.0 Universal text. Both are permissive (licence **rank 0**),
but the campaign's publishing rule (ARCHITECTURE.md §8) keeps the port
**local-only** until the maintainer approves publishing.

Status: **implemented; verification at `41f822b6` recorded below** — the
key-reset slice, the gold key tooltip, the item tag and lang in a valid
`.hmod`, two hooks, one pure runtime (9 tests), the
`stage → check → test → build` ladder and a fail-capable e2e that loots a
vault, refuses a second loot without a reset, resets it, loots again, and loots
a third time after a save/reload. **Class + tier:** `content` / `logic` — the
tag and lang are carried content, the behaviour is two `logic`-tier hooks
(`right_click_block`, `tooltip`) over one pure runtime, per
`docs/modpacks.md` (§Tiers, §5); no machines or deep-tier feature is added.

Upstream analysis, file by file: [`FINDINGS.md`](FINDINGS.md).

## The probe: can a vault's `rewarded_players` be cleared at the pin?

The campaign had recorded a missing block-entity write; this slice began by
probing exactly that. Three layers, all needed. Re-probed at `41f822b6` on
2026-11-07 (line numbers are that pin's):

1. **Native API (absent).** `native-hooks.json` has `block_entity`,
   `block_entity_ticks`, `block_entity_tick`, `block_entity_update_tag`,
   `block_entity_container` and `block_entity_fluids`, but every one is scoped
   to a **mod's own** block (`native_hooks.rs:3151-3159` and
   `docs/native-mods.md:204`: "made when the block is placed … when the block is
   yours"). The vault is a vanilla block entity (`BlockEntity::Vault`), so no
   `native_*` call can read or write `rewarded_players`. The pin's new vault
   hooks (`vault_loot` API 353, `vault_change_state` API 303) are `listen`
   only, so a reset cannot be expressed through them either. This is the gap
   the campaign remembered; it is **still open at this pin**.
2. **Pin-internal access (present).** The vault is a plain field of the
   authoritative world: `World.block_entities` is
   `crate::block_entities::BlockEntities` (`horizon-client-render/src/world.rs:84`,
   `pub`) with `get`/`get_mut` (`block_entities.rs:298`, `:301`), and
   `Vault.rewarded_players` is `pub` (`chunk/block_entity.rs:659`; `Uuid` is
   `[i32; 4]`, `vault.rs:14`). A support module injected into `crate::game` is a
   child module, so it can reach the private `Game.world` field and mutate the
   `Vec<Uuid>` in place. This is the same pin-internal route earlier ports used
   for `Game::break_block`, `Game::save_game`, `Game::add_player_effect`
   (`game/potions.rs:924`) and `GameLevel.registry`.
3. **In-game effect (verified).** `tools/e2e.sh` places a vault, loots it, then
   resets it with a key and loots it again; the log line
   `[repeatable_trial_vaults] reset the vault at …` is emitted, exactly one key
   is consumed per reset, the vault returns to `vault_state=active`, and a
   third loot succeeds after `save`/`quit`/reopen. The counterfactual run uses
   a stick and gets no reset and no second loot. Evidence in the table below.

**Verdict: feasible at `41f822b6`, and implemented.** The write is a
pin-internal dependency (not a stable hook): a later pin that renames
`Game.world`, `World.block_entities` or `Vault.rewarded_players` breaks the
build, and the fix is a native vanilla-block-entity read/write hook. Recorded as
an issue-shaped gap below.

## Hook table

| Upstream | Pin hook / API | File |
|---|---|---|
| `MixinVaultBlock.useItemOn` HEAD mixin | `right_click_block` (API 21, v1, HEAD) | `mixins/repeatable_trial_vaults/right_click_block.rs`, `support.rs` |
| `VaultServerData.rewardedPlayers.remove` + `markChanged` | `World.block_entities.get_mut` + `Vault.rewarded_players` (pin-internal) | `support.rs` |
| `ItemStack.consume(config.keyItem().getCount(), player)` | `Game::consume_held()` per item (creative-safe) | `support.rs` |
| `Stats.ITEM_USED` | `Game.stats.add("used", …)` (pin-internal, same call `use_vault` makes) | `support.rs` |
| `SUCCESS` (swing + consume the click) | `Game::swing_arm()` then `canceled = true` | `support.rs` |
| `ClientClass.onTooltip` | `tooltip` (API 12, v1, HEAD) | `mixins/repeatable_trial_vaults/tooltip.rs`, `support.rs` |
| item tag `#repeatable_trial_vaults:can_reset_trial_vaults` | the two vanilla ids in `runtime.rs`, the tag shipped in `content/` | `runtime.rs`, `content/data/...` |
| `tooltip.rtv.can_reset_vaults` lang | `content/assets/repeatable_trial_vaults/lang/en_us.json` | content |

The pure rules in `runtime.rs` decide *whether* a click resets and how much it
consumes (`reset_plan`), the list edit (`without_rewarded`) and the tooltip
membership; the support module reads the block entity and applies them. Each
hook adapter is one private function, and the support module uses no
`//!`/`#![…]`.

## Re-pin `c9d474d` → `41f822b6` (2026-11-07)

Everything the port binds was re-checked against the pin's `native-hooks.json`
(432 hooks) and source, not assumed from the old pin:

| Item | Old (`c9d474d` / `d9c83d7`) | New (`41f822b6` / `5a64af9`) | Change |
|---|---|---|---|
| `compatibility.json` `horizon_revision` | `c9d474dd…` | `41f822b659789780f58d32c63ddfb6887ea1b8bf` | re-pin |
| `game.rs` sha256 | `4ab99203…` | `2488718332e589c8cbc15766c93857e83945b5f90b74f393ceaa1cd75c23891e` | recomputed from the pin checkout (`sha256sum`), not copied |
| `horizon_mixins_revision` | `d9c83d70…` | `5a64af938ec86b00d53d16a408aabc0038fb3e57` | re-pin, schema 6 unchanged |
| `[compatibility] horizon_revision` in `horizon-mixin.toml` | `c9d474dd…` | `41f822b6…` | equals `compatibility.json` (the tooling compares the staged `.horizon-revision`) |
| hook `right_click_block` | v1, `HEAD`, cancellable | v1, `HEAD`, cancellable (`native_hooks.rs:7056`) | **unchanged** name/version/contract (`"contract": "cancel"`) |
| helper bindings `pos`, `canceled` | `pos`, `canceled` | `pos`, `face`, `canceled` at the call site | the subset the helper declares still resolves; `face` is not bound |
| hook `tooltip` | v1, `HEAD`, collect | v1, `HEAD`, collect (`native_hooks.rs:6667`) | **unchanged** |
| `Vault.rewarded_players` | `Vec<[i32; 4]>` | `Vec<Uuid>` with `pub type Uuid = [i32; 4]` (`vault.rs:14`) | same type, same `without_rewarded` signature |
| `World.block_entities` / `World.modified` | `world.rs:54` / `:82` | `world.rs:84` / `:82` | moved lines only; `get`/`get_mut` unchanged |
| embedded test target | `--bin horizon-client` | `--lib` (`tools/horizon.py`) | `--bin` reports 0 tests at this pin |
| `cargo build` for ctl | `-p horizon-client-lib --bin horizon-ctl` | same | unchanged |

No hook was renamed or removed and no signature the port uses changed. The
`content/` tag and lang did not change between pins (API 0.2 unchanged); the
`.hmod` was still rebuilt at this pin (size/hash below).

## Behaviour, as implemented

- A right-click on a `minecraft:vault` with `minecraft:trial_key` or
  `minecraft:ominous_trial_key` resets it **iff** the acting player's UUID is in
  `rewarded_players`. The click is cancelled (the block never sees it), the
  held stack loses the vault config's key count (normally 1; a keyless vault
  consumes 0; `consume_held` skips creative like `ItemStack.consume`), the
  `used` stat is awarded once, and the hand swings.
- The reset is allowed whatever the vault's `vault_state` is (upstream checks
  no state). The vault's own tick then sees the player as unrewarded and moves
  `inactive → active`; the next key unlocks it and ejects a fresh reward roll.
- Sneaking with a stack in hand does nothing, matching `use_hand`'s block-use
  gate (`game.rs:5704`); upstream's `VaultBlock.useItemOn` was never called
  then either.
- Both keys carry the gold tooltip line `Can Reset Trial Vaults` (upstream's
  `ChatFormatting.GOLD`).
- The reset is saved: the chunk is added to `world.modified`, so the block
  entity is written by the next autosave/`save` even though no block state
  changed (proved by the reload phase of the e2e).
- Everything else about the vault is vanilla; no content blocks/items are
  added.

## Deviations and gaps (issue-shaped, not worked around)

1. **No native API to read or write a vanilla block entity.** The port reaches
   `Game.world.block_entities` and `Vault.rewarded_players` directly (see the
   probe). It is a pin-internal dependency; a future pin can move either. Issue:
   "a native read/write hook for a vanilla block entity's saved NBT (or at
   least the vault's `rewarded_players`), so content-logic mods do not pin the
   engine's internal maps".
2. **The item tag cannot be read where the port runs.** `native_item_in_tag`
   and `native_server_item_in_tag` return `NotServer` on a client execution
   role (`native_world_read.rs:32-34`), and single player's window is a client
   of its integrated server. The port therefore names the tag's two vanilla
   members in `runtime.rs` (the tag is still shipped, byte for byte, for
   data-pack parity). A pack that adds another reset key would need a tag read
   that works on the integrated client. Issue: "server tag reads on a
   single-player client".
3. **No hover tooltip assertion in the harness.** The `tooltip` hook is
   unit-tested (`tooltip_applies`) and the lang file ships, but `horizon-ctl`
   has no "read the tooltip under the cursor" command, so the rendered line is
   not part of the e2e. This is a harness gap, not an engine gap.
4. **`right_click_block` cancels without a swing.** The port calls
   `swing_arm()` itself, so the visual result matches upstream's `SUCCESS`;
   the packet order (cancel then swing) is the pin's, not upstream's.
5. **No `markChanged` equivalent.** Upstream's `VaultServerData.markChanged`
   marks the block entity dirty; the port marks the chunk modified instead
   (`world.modified`), which is what the pin's save path reads
   (`game.rs:16168`, `17819`). There is no per-block-entity dirty flag at the
   pin.
6. **A sneak-click for a guest uses the host's sneak bit** if the pin's
   `use_hand` does; the port reads the swapped-in player's `shift_key_down`,
   which is the same bit `use_hand` gates on.

Skills: superpowers/using-superpowers,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices,rust-review

## Verification

**Every result below was produced on 2026-11-07 at Horizon `41f822b6` /
horizon-mixins `5a64af9`.** The `c9d474d` verification that earlier revisions of
this file described had no surviving log or build; it is superseded, not
extended. Runs: Linux, Rust 1.95.0, 26.3 prepared resources at
`/home/adlf/Desktop/horizon/.local/horizon-client/26.3`. Every cargo/stage/e2e
step ran inside a `ports/tools/build-slot.sh` lease with `CARGO_INCREMENTAL=0`;
logs are in
[`ports/_shared/evidence/repeatable_trial_vaults/repin-41f822b/`](../../_shared/evidence/repeatable_trial_vaults/repin-41f822b/).

### Ladder (`tools/ladder.sh` in one slot, job `new-vaults`)

| step | command | result |
|---|---|---|
| format | `cargo fmt --all --check` | `FMT_EXIT:0` |
| runtime tests | `cargo test --locked --offline` | `CARGO_TEST_EXIT:0` |
| clippy | `cargo clippy --all-targets --locked --offline -- -D warnings` | `CLIPPY_EXIT:0` |
| stage | `python3 tools/horizon.py stage --horizon …/pins/horizon-41f822b` | `STAGE_EXIT:0`, `stage_changed: true`, 85.35 s |
| check | `python3 tools/horizon.py check --horizon …` | `CHECK_EXIT:0`, `cargo_exit: 0`, 58.2 s |
| embedded tests | `python3 tools/horizon.py test --horizon …` (`--lib`) | `TEST_EXIT:0`, `cargo_exit: 0`, 134.5 s |
| build | `python3 tools/horizon.py build --horizon …` | `BUILD_EXIT:0`, `cargo_exit: 0`, 492.7 s |
| bundle audit | `python3 tools/test_stage.py --horizon …/pins/horizon-41f822b` | `TEST_STAGE_EXIT:0` — deterministic bytes/mtimes, only planned ASTs changed, pin checkout unchanged |

Verbatim test lines:

```
test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

(standalone `runtime.rs`, 9 tests)

```
running 9 tests
...
test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 1105 filtered out; finished in 0.00s
```

(embedded `game::repeatable_trial_vaults::tests` in the staged lib)

Warnings in the three staged logs: **0** (`check.log`, `test.log`, `build.log`
each count 0 `^warning` lines). The `--lib` target change is what makes the
embedded run non-vacuous: at this pin `--bin horizon-client` reports 0 tests.

Tooling touched: `tools/horizon.py` (embedded tests now `--lib`),
`tools/audit/Cargo.toml` (the AST audit used `syn::visit_mut` without the
`visit-mut` feature, so `test_stage.py` could not compile it; the feature is
now declared) and `tools/test_template.py` (header says it is the upstream
template's one-hook fixture, not this bundle's). `tools/e2e.sh` was corrected
and `tools/e2e-suite.sh` added — see the e2e section.

Artifact: `cargo-horizon-mod horizon-mod build` (run in `content/`) then
`cargo-horizon-mod horizon-mod check … --json`:

```
{"ok":true,"report":{"api":"0.2","capabilities":["registries"],"id":"repeatable_trial_vaults",
 "kind":"mod","sha256":"44b45f86aa1000814f3ed7a8c02e35f572f3fae65b4f5059cb0139d598689e48",
 "side":"both","signed":false,"size":962,"version":"1.0.3"}}
```

`repeatable_trial_vaults.hmod`: **962 B**, SHA-256
`44b45f86aa1000814f3ed7a8c02e35f572f3fae65b4f5059cb0139d598689e48`, **3
entries** (`horizon-mod.toml`, `assets/…/lang/en_us.json`,
`data/…/tags/item/can_reset_trial_vaults.json`). The bytes are identical to the
old file (the pack is deterministic and the content did not change), but the
build was re-run and re-checked at this pin.

### In-game e2e (three legs, one slot, `tools/e2e-suite.sh`)

`build-slot.sh e2e --port ports/repeatable_trial_vaults -- tools/e2e-suite.sh`
with the shared `horizon-ctl` (`ports/_shared/bin/horizon-41f822b6/`) and the
port-built game; transcript per leg in the evidence folder. The shared ctl is
protocol-compatible at the same pin; the game must be the port's, because the
mod is compiled in.

Default leg — the scenario, verbatim (transcript lines interleave the `ctl`
command and its JSON reply):

```
== a placed vault becomes active for the player ==
vault after placement: minecraft:vault[facing=north,ominous=false,vault_state=active]
== loot 1: a trial key unlocks and ejects ==
before loot 1: keys=8 items=0 loot=0
ctl use-item
{"block":null,"block_before":null,"changed":false,"inventory_change":{"minecraft:trial_key":-1},"ok":true,"screen":"playing"}
after loot 1: keys=7 items=3 loot=8
== control: the pre-reset (rewarded) state yields no second loot ==
ctl use-item
{"block":null,"block_before":null,"changed":false,"inventory_change":{},"ok":true,"screen":"playing"}
stick click: keys=7 -> 7 state=minecraft:vault[facing=north,ominous=false,vault_state=inactive]
control PASS: the stick neither reset nor looted the rewarded vault
== reset 1: a trial key clears the rewarded player ==
ctl use-item
{"block":null,"block_before":null,"changed":false,"inventory_change":{"minecraft:trial_key":-1},"ok":true,"screen":"playing"}
reset click: keys=7 -> 6 state=minecraft:vault[facing=north,ominous=false,vault_state=inactive]
reset 1 PASS: vault is minecraft:vault[facing=north,ominous=false,vault_state=active], reset lines=1
== loot 2: the same player loots the reset vault again ==
loot 2 counts: keys=6 -> 5 loot=8 -> 23 items=3
loot 2 PASS: keys=6 -> 5 loot=8 -> 23
== control 2: still no loot without a reset ==
control 2 PASS: no second loot without a reset
== persistence: reset, save, reopen, loot a third time ==
after reload: keys=4 state=minecraft:vault[facing=north,ominous=false,vault_state=active]
loot 3 counts: keys=4 -> 3 loot=23 -> 33 items=5
persistence PASS: keys=4 -> 3 loot=23 -> 33
resets logged by the hook before the reload: 2
PASS: a trial key reset a rewarded vault and the player looted it again (and again after a reload)
default EXIT:0
```

The hook's own log in the first launch (copied as
`rtv-default-transcript.log.game-before-reload`) carries one line per reset, for
the same player:

```
[repeatable_trial_vaults] reset the vault at [0, 100, 2] for [568489192, -1847837207, -1999698076, 1285276242]
[repeatable_trial_vaults] reset the vault at [0, 100, 2] for [568489192, -1847837207, -1999698076, 1285276242]
```

Counterfactual leg (`COUNTERFACTUAL=1`): same loot 1, then the stick click; the
run stops there and asserts the stick could not reset:

```
control PASS: the stick neither reset nor looted the rewarded vault
counterfactual PASS: no non-key reset (vault inactive, nothing consumed)
counterfactual EXIT:0
```

Negative leg (`COUNTERFACTUAL=1 NEGATIVE=1`): the same assertion inverted, so
the run **must** fail; it does:

```
stick click: keys=7 -> 7 state=minecraft:vault[facing=north,ominous=false,vault_state=inactive]
FAIL: NEGATIVE run: the inverted assertion was checked (stick reset nothing)
negative EXIT:1
SUITE PASS: default 0, counterfactual 0, negative non-zero
```

**Why the control is a stick, not a key.** With this mod a *key* click on a
rewarded vault **is** the reset (upstream never checks `vault_state`), so a key
can never be "a second loot without a reset"; the earlier `c9d474d` script's
control used a key and would have passed only if the hook never fired. The
stick is the item-level counterfactual: it is not in the reset tag, cannot
reset, and leaves the vault `inactive` with nothing consumed. That is also why
the default run asserts `inventory_change:{}` on the stick click and `-1` key on
the following reset click (the reply's inventory snapshot is the client's, so in
one earlier run it lagged by a tick; the key count always comes from the
following `ctl inventory`).

**Why loot is counted as floor + inventory.** At this pin a second loot's item
entities can merge into the first loot's stacks (the entity count stayed 3 while
the loot grew 8 → 23); the run therefore sums the item-entity stacks and the
player's inventory, excluding the keys and the control stick. The entity count
is still printed for diagnostics.

Harness notes: the player stands at `(0.5, 100, -1.0)`, 3 blocks from the
vault — inside its 4-block activation range and outside pickup reach (at
`z=-1.5` the floored block is `z=-2`, exactly 4 blocks away, and the vault never
activates: that was a real false start, fixed by moving to `z=-1.0`). The vault
is placed with `ctl command "setblock 0 100 2 minecraft:vault"`; `ctl use-item`
right-clicks it; `ctl block 0 100 2` reads `vault_state`.

## Re-pin `1d63e0a5` and the one-file bundle (2026-11-10)

**Class + tier** unchanged (class **content**, tier **logic**). The port is now
a **single `.hnmod`**: the content half (upstream's `can_reset_trial_vaults`
item tag and the tooltip lang string) travels inside the bundle at
`mixins/repeatable_trial_vaults/data/repeatable_trial_vaults-content.hmod`, and
one `embedded-content` injection at `horizon_client::game::mods::content_root`
writes it to `.horizon-cache/` and appends it to the dev list (AE2 pattern,
proved on `charginggadgets`, PR #526).

- Pin: migrated from `41f822b6` to Horizon
  `1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9` (`game.rs` SHA-256 `64813cf4…cef80f`)
  / mixins `5a64af938ec86b00d53d16a408aabc0038fb3e57`, in `compatibility.json`,
  `horizon-mixin.toml` and the `tools/horizon.py` defaults.
- Artifacts (port version **0.1.0**, the port's own version, not upstream's
  1.0.3): `content/repeatable_trial_vaults.hmod` **1,042 B**, SHA-256
  `a170bf14474c0e1438f64c051c6d0c936d4a0c8c900cd8707a70ea15fd82f662`, 3
  entries; `repeatable_trial_vaults.hnmod` **7,606 B**, SHA-256
  `8647b53155db309bd6c8b0f283164aa4a88574aa08410e32b7a193cdbe2dc7e9`, 8 entries;
  `cargo horizon-mod check … --kind native-mod` exits 0. The stray root copy of
  the `.hmod` was removed (it belongs in `content/`), and the content mod's
  `version` now matches the bundle (0.1.0).
- Ladder: fmt clean, clippy `-D warnings` clean, `cargo test` 9 passed,
  `horizon.py stage/check/test/build` `cargo_exit: 0`, 0 warnings, 9 embedded
  tests, fast build.
- In game with **no `--dev-mod`**: control leg (unusable cache → nothing written,
  tag not resolvable), then loot 1 → control → reset → loot 2 → control → reset
  → save/reopen → loot 3, with the hook's log lines counted. `PASS` + `EXIT:0`
  (`ports/_shared/evidence/repeatable_trial_vaults/e2e-embedded.log`);
  `COUNTERFACTUAL=1 NEGATIVE=1` fails as intended (`EXIT:1`).
- Honest control note: the content half here has **no registrable id**, and
  `/clear @s #repeatable_trial_vaults:can_reset_trial_vaults` answers "Unknown
  item tag" in both runs at this pin, so the tag is not an observable probe. The
  control therefore asserts the helper wrote nothing into an unusable cache; the
  content evidence is the byte-identical written file plus the behavioural legs
  (which the counterfactual/negative runs prove can fail).

## Port version `0.1.0` and repackage (2026-11-10)

**Class + tier** unchanged (class **content**, tier **logic**). The registry
version is the **port's** version, not upstream's (`AGENT_PLAYBOOK.md` §1.7):
this is still a partial port (two hooks over one pure runtime, one carried tag
and one lang line), so both packaging manifests now read `0.1.0` —
`content/horizon-mod.toml` and `mixins/repeatable_trial_vaults/horizon-mixin.toml`
`[mod] version`. `tools/package.py` takes the version from the bundle manifest,
so no tool constant changed; the packager's own build/check output now prints
`repeatable_trial_vaults 0.1.0` for both kinds.

- Artifacts (rebuilt by `tools/package.sh` at the pin, two runs):
  `content/repeatable_trial_vaults.hmod` **1,042 B**, SHA-256
  `a170bf14474c0e1438f64c051c6d0c936d4a0c8c900cd8707a70ea15fd82f662`, 3 entries;
  `repeatable_trial_vaults.hnmod` **7,606 B**, SHA-256
  `8647b53155db309bd6c8b0f283164aa4a88574aa08410e32b7a193cdbe2dc7e9`, 8
  entries. Two consecutive runs gave the same bytes for both files (the `.hmod`
  grew from 962 B because `horizon-mod.toml` carries the new version and its
  provenance comment; the `.hnmod` from 7,522 B for the same reason).
- `cargo horizon-mod check repeatable_trial_vaults.hnmod --kind native-mod`
  exits 0 and prints `0.1.0 (native-mod, format native-1/1d63e0a…/5a64af9…,
  for 26.3)`; `--kind mod` on the `.hmod` prints `0.1.0 (mod, API 0.2, both)`.
  `horizon-native.json` inside the bundle carries `"version": "0.1.0"`.
- Embedded content: `tools/package.sh` copies the built `.hmod` to
  `mixins/repeatable_trial_vaults/data/repeatable_trial_vaults-content.hmod`;
  `cmp` says it is byte-identical, and the in-game leg wrote **1,042 B** into
  `.horizon-cache/repeatable_trial_vaults-embedded-content.hmod`, identical to
  `content/repeatable_trial_vaults.hmod` (`tools/e2e.sh`'s
  `embedded_content_check`).
- E2E, one slot (`rtv-version-e2e`, `tools/e2e-suite.sh`): default
  `EXIT:0`, counterfactual `EXIT:0`, negative `EXIT:1`, `SUITE PASS`;
  transcripts in `ports/_shared/evidence/repeatable_trial_vaults/`
  (`e2e-embedded.log`, `e2e-counterfactual.log`, `e2e-negative.log`,
  `suite-run.log`, `package.log`). `check-e2e-logs.py --strict`: 3/3 ok.
- Publish tree refreshed from these sources: the `.hnmod`, `content/*.hmod`,
  `content/horizon-mod.toml`, the bundle manifest and its embedded content copy,
  and `registry.toml` (`version = "0.1.0"`, `sha256` above,
  `published = "2026-11-10"`). Prose/README/icon unchanged.
- Slot note: the lease journal records `exit 0` for the run; the runner printed
  a spurious `slot: unbound variable` **after** releasing the lease (runner-side,
  post-release), the suite itself passed.

Skills: superpowers/using-superpowers,verification-before-completion; BeautifulRust/rust-best-practices (read; no Rust change)

## Review repairs (PR #638)

1. The version/hash mismatch the reviewer found is in the **PR body**
   (`1.0.3`/`0b4ee88…` vs the entry's `0.1.0`/`8647b5…`), which the
   orchestrator re-writes; the entry itself is unchanged in version.
2. *"Fix the entry original link `(Buuz135/Repeatable-Trial-Vaults)` to an
   absolute upstream URL and credit the upstream author"* — the entry links
   `https://github.com/Buuz135/Repeatable-Trial-Vaults` and lists `Buuz135`.
3. Staging is the orchestrator's (horizon-mods#686).
4. The notices travel inside the artifact now (`mixins/repeatable_trial_vaults/LICENSE`
   and `NOTICE.md`, and the same at the embedded content root).

### Verification after the repairs

- Artifact: `repeatable_trial_vaults.hnmod`, 10,480 B, SHA-256 `74d7ccb032f81b75b2e96503efe1a584a8acbf4889e3f8953e05f0974cc15c3c` (rebuilt twice, identical bytes; `tools/package.py`; the embedded content equals `content/repeatable_trial_vaults.hmod`).
- `python3 ports/tools/upstream_ready.py repeatable_trial_vaults` and `check-skills.py --notes ports/repeatable_trial_vaults`: exit 0.

## Migration to the SDK format (2026-11-18, SDK `0b14f8a`)

Horizon's mod-API merge (#16941, launcher ≥ 0.2.70) retired the `.hnmod` container, and the
registry closed this port's submission (PR #658) with *"republish this as a native `.hmod` with the
SDK from the next Nightly"*. The port is now one flat package:

- **Pin:** Horizon **`0b14f8acfd97fa2c750e42795249dcc981178ca4`** (nightly 2026-11-18), horizon-mixins
  **`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, mod API **`0.2`** (749 surface items; SDK fetched
  into `.horizon/sdk/` by `cargo horizon-mod`, never packed).
- **Version:** the port's own **0.2.0** (the retired bundle was 0.1.0; a resubmission is always a new
  version).
- **Class + tier** unchanged: class **content**, tier **logic** — one `BlockPart` on a vanilla block
  plus one `ItemPart` on two vanilla items, over the same pure runtime. No machine/deep feature is
  added.

### Checklist — files created, files deleted

| Created | What it holds |
|---|---|
| `horizon-mod.toml` | the only manifest: `id`, `version = "0.2.0"`, `api = "0.2"`, `side = "both"`, the required `capabilities`, `[native]` with the exact `game`/`horizon`/`mixins` |
| `Cargo.toml` | the crate: `horizon-mod-api` from `.horizon/sdk/` and nothing else |
| `Cargo.lock` | the SDK's registry pins (generated) |
| `src/lib.rs` | the one `#[mod_api::horizon_mod] impl Hooks` (`register`), the two Parts, the NBT/UUID glue and 6 glue tests |
| `src/runtime.rs` | the old `runtime.rs`, **byte-identical** (SHA-256 `4a70b0a82af9ddf6ff0495895ce4c1f3c38f32f9559aef244b830510a6f3b7b7`, 144 lines, `cmp` clean before the old copy was deleted) |
| `assets/repeatable_trial_vaults/lang/en_us.json` | the carried tooltip lang line (`cmp` clean) |
| `data/repeatable_trial_vaults/tags/item/can_reset_trial_vaults.json` | the carried item tag (`cmp` clean) |
| `repeatable_trial_vaults.hmod` | the delivered package, port root |
| `.gitignore` | `/target`, `/.horizon` |

| Deleted | Why | Where it went |
|---|---|---|
| `mixins/repeatable_trial_vaults/` (`horizon-mixin.toml`, `support.rs`, `right_click_block.rs`, `tooltip.rs`, `embedded_content.rs`, `data/*.hmod`) | the plan/injection schema and per-hook helpers are not part of any SDK package | `runtime.rs` → `src/`; the two hook bodies → `impl Hooks::register` Parts; the embedded-content injection → nothing (see below) |
| `content/` (`horizon-mod.toml`, `assets/`, `data/`, `target/`, `*.hmod`) | a second package; the flat package carries content itself | `assets/` + `data/` at the package root |
| `compatibility.json` | the pin is `[native]` in `horizon-mod.toml` | — |
| `rust-toolchain.toml` (1.95.0) | "not part of any new package"; the crate builds on the box's stable (1.97.0) and the launcher builds against the SDK's own toolchain | — |
| `repeatable_trial_vaults.hnmod` | the retired container | replaced by the flat `.hmod` |
| `.github/` (`workflows/ci.yml`) | the upstream template's fixture workflow: it clones `horizon-mixins`, reads `compatibility.json` and runs `tools/test_template.py`, none of which exist any more | no replacement shipped (the campaign's gate is the slot ladder); a registry-side workflow is the registry's to write |
| `tools/horizon.py`, `package.py`, `package.sh`, `ladder.sh`, `test_stage.py`, `test_template.py`, `add-notices.py`, `audit/`, `__pycache__` | the staged/mixin build machinery; there is no stage, plan, check-of-module or repackage step any more | `cargo horizon-mod build|check|fits` |

Kept on purpose: `tools/e2e.sh` and `tools/e2e-suite.sh` (the scenario is still the only in-game
oracle; a `STATUS` header explains the launcher-built game it now needs and that the embedded-cache
legs are retired), `FINDINGS.md`, `notes.md`, `LICENSE`, `LICENSE-NOTICE.md`, `README.md`
(rewritten for the flat layout), `VALIDATION.md` and `REPIN-41f822b-PLAN.md` (history).

**The embedded `.hmod` is gone.** The retired bundle wrote its content half to `.horizon-cache/`
from a `content_root` injection (the AE2 pattern) because the registry keeps one file per project.
The flat SDK package carries `assets/` and `data/` **inside its own `.hmod`**, so the injection, the
static `native_data!` blob, the cache write and its control leg are all deleted — that whole
workaround is the migration's biggest simplification.

### Hook mapping

| Retired | SDK (0.2) | Where |
|---|---|---|
| `right_click_block` HEAD, `canceled = true` | **`BlockPart::use_item_on`** on `minecraft:vault` (`BlockBehaviour.useItemOn`, the very method the upstream mixin targeted), answer `InteractionResult::SuccessServer` | `src/lib.rs`, `ResetVault` |
| `World.block_entities.get_mut` + `Vault.rewarded_players` (pin-internal) | **`BlockEntityRef::data()`**, `merge_data()` and the RI's own `setChanged` + client sync | `src/lib.rs`, `ResetVault` |
| `Game::consume_held()` per key | `LivingRef::set_hand_item` with the reduced count (`None` when emptied); creative keeps the stack | `consume_held` |
| `Game.stats.add("used", …)` | `PlayerRef::award_stat(host, StatType::Used, item, 1)` | `consume_held`'s caller |
| `Game::swing_arm()` then `*canceled = true` | the answer itself: `SuccessServer` swings the server's hand and ends the click | `ResetVault` |
| `tooltip` hook, HEAD, collect | **`ItemPart::tooltip`** on the two trial-key item keys (the `tooltip` hook is `scope = "item"`, so it is a Part, not a global hook) | `src/lib.rs`, `ResetKeyTooltip` |
| `horizon-mixin.toml` `[[module]]`/`[[injection]]` | `fn register(&self, r: &mut dyn Registrar, _: &RegistrationContext)` | `src/lib.rs` |
| `embedded_content.rs` `content_root` injection | — (content ships in the package) | — |
| item tag `#repeatable_trial_vaults:can_reset_trial_vaults` | unchanged: the tag ships, the runtime names its two vanilla members (the SDK still has no item-tag read — `block_in_tag`/`fluid_in_tag` exist, no item equivalent) | `src/runtime.rs`, `data/` |
| `tooltip.rtv.can_reset_vaults` lang | unchanged, carried byte for byte | `assets/` |

`runtime.rs` is untouched: `reset_plan`, `without_rewarded`, `is_reset_key`, `tooltip_applies`,
`RESET_KEYS` and `TOOLTIP_KEY` are called exactly as before. The new glue only converts between the
SDK's types and the runtime's: `u128` UUID ↔ `[i32; 4]` (the engine's `ints_uuid` fold, most
significant int first), `Tag::IntArray` list ↔ `Vec<[i32; 4]>`, and `config.key_item.count` ↔ `u32`.

### Build and check (verbatim)

```sh
# runtime + glue tests, and the lint gate
ports/tools/build-slot.sh run --job sdk-rv --port ports/repeatable_trial_vaults --step test \
    -- bash -c 'cd ports/repeatable_trial_vaults && cargo test --offline'
# → test result: ok. 15 passed; 0 failed  (9 runtime + 6 glue)

ports/tools/build-slot.sh run --job sdk-rv --port ports/repeatable_trial_vaults --step lint \
    -- bash -c 'cd ports/repeatable_trial_vaults && cargo fmt --check &&
        cargo clippy --all-targets --offline -- -D warnings'
# → Finished `dev` profile … (no warning, no error)

ports/tools/build-slot.sh run --job sdk-rv --port ports/repeatable_trial_vaults --step build \
    -- bash -c 'cd ports/repeatable_trial_vaults && cargo horizon-mod build'
# → SDK 0b14f8a (build 0b14f8acfd97fa2c750e42795249dcc981178ca4) in ./.horizon/sdk
# → Built ./target/horizon-mod/repeatable_trial_vaults.hmod

ports/tools/build-slot.sh run --job sdk-rv --port ports/repeatable_trial_vaults --step check \
    -- bash -c 'cd ports/repeatable_trial_vaults &&
        cargo horizon-mod check repeatable_trial_vaults.hmod && cargo horizon-mod fits repeatable_trial_vaults.hmod'
# → repeatable_trial_vaults 0.2.0 (native-mod, format native-1/0b14f8ac…/e59da909…, for 26.3)
# → 16048 bytes, SHA-256 369653ec…, unsigned    CHECK_EXIT:0
# → Repeatable Trial Vaults: / 0b14f8a  made for    FITS_EXIT:0
```

`BUILD_LOCAL=1` on every step: the automatic forward failed with
`bash: line 1: cd: /home/deepseek/atm10/repeatable_trial_vaults: No such file or directory`, so each
step ran locally in a lease (slot reported, `CARGO_INCREMENTAL=0`, released by the runner).

### Traps this migration cost

1. **`build-slot.sh` does not `cd` into the port.** `--port` is a label (and the cache-link target);
   a bare `cargo test` from the campaign root fails with `could not find Cargo.toml`. Wrap every
   command as `bash -c 'cd ports/<id> && …'`.
2. **Do not declare `rust-version`.** The scaffold declares none; with `rust-version = "1.99"`
   cargo refuses the box's 1.97.0 (`rustc 1.95.0 is not supported by …` — 1.95 was the port's old
   `rust-toolchain.toml`, which also had to go).
3. **`capabilities` is a required manifest field** (`missing field capabilities`), even though this
   mod registers nothing: the check report's own `capabilities` is `[]`. The field is a permission,
   not a claim.
4. **Host *writes* are handle methods, not `ServerHost` area methods.** `player_award_stat` and
   `living_set_hand_item` live on the backend traits; a mod calls `player.award_stat(host, …)` and
   `living.set_hand_item(host, …)`.
5. **`is_creative`/`level`/`block_entity` return `Option`**, so `player.is_creative(&*host) == Some(true)`.
6. **`Compound` is `BTreeMap<JavaString, Tag>`**: its `get` takes a `&JavaString`; read nested keys
   through `Tag::get(&str)` (which keeps a thread-local key), i.e. wrap the compound in a `Tag` once.
7. **`mod_api::prelude::*` is unnecessary** and fails the lint gate as an unused import — supertrait
   methods resolve on `&mut dyn ServerHost` without it.
8. **`cargo horizon-mod build` packs; it does not compile against the game.** The real native build
   is `horizon-launcher native-build <port> --instance <instance> --trust-native-code`, which is not
   installed here and has no game build at `0b14f8a` (the shared binaries are at `1d63e0a5` and
   `41f822b6`). The compile evidence this slice has is `cargo clippy --all-targets` / `cargo test`
   against the pinned SDK API crate — the same crate the launcher builds against — plus
   `horizon-mod check`/`fits`. Every hook and host method name was confirmed with
   `cargo horizon-mod hooks <text>`, never guessed.
9. **The tool truncates `hooks <text>` output**; `--all` names the trait method (`method:Hooks::…`)
   and the types, and the full text is in `.horizon/sdk/surface.json` / the crate sources.

## Migration verification (SDK `0b14f8a`)

Skills: superpowers/using-superpowers,writing-plans,test-driven-development,verification-before-completion; BeautifulRust/rust-best-practices

- **Runtime carried:** `src/runtime.rs` SHA-256
  `4a70b0a82af9ddf6ff0495895ce4c1f3c38f32f9559aef244b830510a6f3b7b7` (the retired
  `mixins/repeatable_trial_vaults/runtime.rs`, `cmp` clean). Its **9 tests ran green before any glue
  existed** (`test result: ok. 9 passed; 0 failed`), then again with the glue (`15 passed`).
- **Lint gate:** `cargo fmt --check` clean, `cargo clippy --all-targets -- -D warnings` clean (0
  warnings, 0 errors).
- **Package:** `repeatable_trial_vaults.hmod`, **16,048 B**, SHA-256
  `369653ec25879ba3d38dc4ce7cda2c785b72ecd3f2c2b7bd20d35b57c34cc079`, built twice with identical
  bytes. Entries (11): `horizon-mod.toml`, `Cargo.toml`, `Cargo.lock`, `src/lib.rs`,
  `src/runtime.rs`, `assets/repeatable_trial_vaults/lang/en_us.json`,
  `data/repeatable_trial_vaults/tags/item/can_reset_trial_vaults.json`, `LICENSE`,
  `LICENSE-NOTICE.md`, `README.md`, `uses.json`. The licence files travel **inside** the package
  (the MIT/CC0 notice condition).
- **`check` and `fits`:** exit 0 (output quoted above; `fits` answers `0b14f8a  made for`).
- **The package's own `uses.json`** (generated by `cargo horizon-mod build`, 147 entries) names
  `hook:use_item_on` and `hook:tooltip` — the two surfaces the Parts implement — plus the
  `BlockEntityRef` handle group (`data`, `merge_data`, `set_changed`…), so the checker read the
  glue exactly as intended rather than seeing an unused declaration.
- **In-game e2e: not run.** No `horizon-launcher`, no game binary at `0b14f8a`; the scenario in
  `tools/e2e.sh` was last proved on the retired bundle (`e2e-embedded.log`, PR #658's evidence).
  This is the slice's honest gap: the behaviour claims here are the *mapping* (each retired hook to
  a typed Part at the same vanilla call site), the type-checked glue, and the carried rules — not a
  gameplay run at `0b14f8a`. The next slice is "build the game with the launcher, run
  `tools/e2e.sh` with `EMBEDDED=0` and record the transcript".

Evidence: [`ports/_shared/evidence/repeatable_trial_vaults/sdk-0b14f8a/`](../../_shared/evidence/repeatable_trial_vaults/sdk-0b14f8a/)
(`unit.log`, `lint.log`, `build.log`, `check.log`, `fits.log`, `package-entries.log`, `final-gate.log`,
`runtime-carry.log`).

## Gaps after the migration

1. **No in-game run at `0b14f8a`** (launcher + game build absent). Everything else in this file is
   either carried logic or a compile-time claim; the first slice at a launcher-capable box runs
   `tools/e2e.sh` and records it.
2. **No log service in the SDK.** The retired bundle's
   `[repeatable_trial_vaults] reset the vault at …` line is gone, so the e2e's per-reset log count
   cannot be reproduced; the reset assertions must lean on the vault's state, the key count and the
   loot (they already do). Issue-shaped: "a log line service for native mods".
3. **No item-tag read.** `block_in_tag`/`fluid_in_tag` exist; the item equivalent does not, so the
   runtime still names the tag's two vanilla members. `ItemPart` can be attached **by tag**
   (`item_part_tag`) — worth trying for the tooltip (a pack adding a key would then get the line
   for free), but it changes behaviour and needs the in-game leg, so it is left for the next slice.
4. **`Success` vs `SuccessServer`.** Upstream returns `SUCCESS`, which in vanilla swings on the
   client that predicted the click; a **server-only** block Part cannot swing a client prediction,
   so the port answers `SuccessServer` (the server swings the hand) — the same visible result the
   old `swing_arm()` produced. Unverified in game; the e2e's swing/screen leg is where it will show.
5. **Tooltip has no harness assertion** (inherited): `horizon-ctl` cannot read the line under the
   cursor. The Part is attached to exactly the two keys and the lang line ships, but the rendered
   pixel is not part of any run.

Closed by the SDK (were gaps/deviations in the retired bundle): the pin-internal
`World.block_entities`/`Vault.rewarded_players` write (now `BlockEntityRef::data`/`merge_data`), the
missing `markChanged` (now `merge_data`'s own `setChanged` + sync), the cancel-without-swing
workaround, the embedded-content injection, and the sneak-click gate (the engine's block-use gate
decides before `use_item_on`, so the old `shift_key_down` check is unnecessary).

## Changelog for the resubmission

> Supersedes #658, closed because Horizon retired `.hnmod` (#17992). Changes: flat SDK package with
> `api = "0.2"` and `[native]` pinned to `0b14f8a`; hooks rewritten as `impl mod_api::Hooks`
> methods against typed hosts/events (`register` attaches a `BlockPart` on `minecraft:vault` for
> the reset and an `ItemPart` on the two trial keys for the tooltip); the vault's
> `server_data.rewarded_players` is now written through `BlockEntityRef::merge_data` instead of a
> pin-internal world write; the carried tag and lang ship inside the package (`assets/`, `data/`),
> so the embedded-content bundle is gone; `runtime.rs` and its tests unchanged. Version 0.2.0.

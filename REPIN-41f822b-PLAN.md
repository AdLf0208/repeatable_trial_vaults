# Re-pin + verification plan — repeatable_trial_vaults at `41f822b`

**Goal:** migrate the `c9d474d` port to Horizon `41f822b6` / mixins `5a64af9`, prove the
vault reset in-game, and leave durable evidence (logs + `.hmod` size/hash).

**Architecture:** content (`logic`) port: carried tag/lang in `content/`, two hook helpers
(`right_click_block`, `tooltip`), one pure `runtime.rs`, one `crate::game` support module that
edits the vanilla vault block entity through the pin-internal `World.block_entities` map.

**Spec:** the brief; class/tier from `docs/modpacks.md` (content → logic = carried content +
use/place/break/tick hooks); licence MIT/CC0 → rank 0.

## Global constraints

- Pin `41f822b659789780f58d32c63ddfb6887ea1b8bf`, mixins `5a64af938ec86b00d53d16a408aabc0038fb3e57`, schema 6.
- No raw target mixin; stamped hooks only (`right_click_block` v1, `tooltip` v1).
- Builds through `ports/tools/build-slot.sh`, `CARGO_INCREMENTAL=0`, no `--target-dir`.
- `cargo fmt` / `clippy -D warnings` / `cargo test` clean; e2e must be fail-capable.

## Tasks

1. **Pin metadata** — `compatibility.json` (revision, `game.rs` sha256
   `24887183…91e`, mixins revision), `mixins/<id>/horizon-mixin.toml` `[compatibility]`
   revision. Verify `sha256sum` of the pin's `game.rs` before writing it.
2. **Reset-path probe (static)** — confirm at the pin: `World.block_entities` (`pub`,
   `crates/horizon-client-render/src/world.rs:84`), `BlockEntities::get/get_mut`
   (`block_entities.rs:298/301`), `Vault.rewarded_players: Vec<Uuid>` with
   `Uuid = [i32; 4]` (`chunk/block_entity.rs:659`, `vault.rs:14`), `World.modified`
   (`world.rs:82`). Confirm no native hook writes a **vanilla** block entity. In-game reset
   is proven by task 5.
3. **Tooling** — `tools/horizon.py`: embedded test target is `--lib` (the `--bin` form runs
   0 tests at this pin); ctl stays `-p horizon-client-lib --bin horizon-ctl`.
4. **Ladder** (slot, `stage → check → test → build`), then `cargo fmt --check`, `clippy
   --all-targets -D warnings`, standalone `cargo test`; copy logs to `_shared/evidence/`.
5. **e2e** — `build-slot.sh e2e` with the shared ctl; loot → refuse second loot → reset →
   loot 2 → reset/save/reload → loot 3; counterfactual stick run must fail to reset; a
   `NEGATIVE=1` inverted run must exit non-zero.
6. **Artifact** — rebuild the `.hmod` with `cargo-horizon-mod` from `horizon/target/debug`,
   record size + SHA-256 + entry count; refresh `notes.md` verification section, state
   class/tier/approach/licence/skills, then `check-skills.py --notes`.

## Stop conditions

Vault reset not writable at the pin (report `blocked(<why>)` with `file:line`), e2e cannot be
made fail-capable, or clippy cannot reach 0 warnings within the logic shape.

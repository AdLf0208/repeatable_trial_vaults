# Repeatable Trial Vaults for Horizon

A native Horizon mod that lets a trial key reset a trial vault that already
rewarded the player, so the same player can loot it again. A rewrite of
[Repeatable Trial Vaults 1.0.3](https://github.com/Buuz135/Repeatable-Trial-Vaults)
for Minecraft Java 26.3 on the Horizon **SDK** package format: Horizon
`0b14f8acfd97fa2c750e42795249dcc981178ca4`, horizon-mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, mod API `0.2`.

Licence of the original: MIT (`META-INF/neoforge.mods.toml`) / CC0-1.0 (the
repository's shipped `LICENSE`). This port is **local-only** until the
maintainer approves publishing (ARCHITECTURE.md §8).

## Behaviour

- Right-clicking a `minecraft:vault` with a `minecraft:trial_key` or
  `minecraft:ominous_trial_key` when that player is already in the vault's
  `server_data.rewarded_players` removes the player from the list and consumes
  the vault config's key count (normally one). The click is consumed, the hand
  swings, and the vault becomes active for that player again on its next tick.
- The same click on a vault that has *not* rewarded the player is left to
  vanilla.
- Both keys show the gold tooltip line `Can Reset Trial Vaults`.

## Layout

```text
horizon-mod.toml                   the only manifest: id, api 0.2, [native] pin
Cargo.toml                         horizon-mod-api from .horizon/sdk/ (fetched, never packed)
src/lib.rs                         the one impl Hooks: a BlockPart on minecraft:vault and an
                                   ItemPart on the two trial keys, plus the NBT/UUID glue
src/runtime.rs                     the pure rules, byte-identical to the retired bundle's, and
                                   its 9 tests
assets/repeatable_trial_vaults/     the carried lang line
data/repeatable_trial_vaults/      the carried can_reset_trial_vaults item tag
repeatable_trial_vaults.hmod       the built package (delivered beside the sources)
tools/e2e.sh                       the in-game reset/loot/reload scenario (retired bundle build;
                                   see the header for the launcher-built game it now needs)
```

## Validate

```sh
ports/tools/build-slot.sh run --job sdk-rtv --port ports/repeatable_trial_vaults --step test \
    -- bash -c 'cd ports/repeatable_trial_vaults && cargo test --offline'
ports/tools/build-slot.sh run --job sdk-rtv --port ports/repeatable_trial_vaults --step lint \
    -- bash -c 'cd ports/repeatable_trial_vaults && cargo fmt --check &&
        cargo clippy --all-targets --offline -- -D warnings'
ports/tools/build-slot.sh run --job sdk-rtv --port ports/repeatable_trial_vaults --step build \
    -- bash -c 'cd ports/repeatable_trial_vaults && cargo horizon-mod build'
ports/tools/build-slot.sh run --job sdk-rtv --port ports/repeatable_trial_vaults --step check \
    -- bash -c 'cd ports/repeatable_trial_vaults &&
        cargo horizon-mod check repeatable_trial_vaults.hmod && cargo horizon-mod fits repeatable_trial_vaults.hmod'
```

`notes.md` records the migration checklist, the hook mapping, the gaps and the
evidence; `FINDINGS.md` records the upstream analysis.

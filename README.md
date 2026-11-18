# Repeatable Trial Vaults — a Horizon port

**Repeatable Trial Vaults** is a Minecraft mod. Consume a key to be able to use another trial vault. This repository is a **port of it to [Horizon](https://github.com/horizon-rust/horizon)**, the Rust engine for Minecraft Java 26.3. It carries the complete source of the port plus the content files it ships, and installs as a single `.hmod` package.

Upstream: [Buuz135/Repeatable-Trial-Vaults](https://github.com/Buuz135/Repeatable-Trial-Vaults) — licence **MIT**.

| | |
|---|---|
| Upstream mod | Repeatable Trial Vaults ([source](https://github.com/Buuz135/Repeatable-Trial-Vaults)) |
| Ported to | Horizon 0b14f8a, Minecraft Java 26.3, mod API `0.2` |
| Package | `repeatable_trial_vaults.hmod` (install it with the Horizon launcher) |
| Licence | **MIT** — the upstream mod's licence; see [Licence and credit](#licence-and-credit) |

## What this port implements

- A right-click on a `minecraft:vault` with `minecraft:trial_key` or
- The reset is allowed whatever the vault's `vault_state` is (upstream checks
- Sneaking with a stack in hand does nothing, matching `use_hand`'s block-use
- Both keys carry the gold tooltip line `Can Reset Trial Vaults` (upstream's
- The reset is saved: the chunk is added to `world.modified`, so the block
- Everything else about the vault is vanilla; no content blocks/items are

## Not yet ported

- **No native API to read or write a vanilla block entity.** The port reaches
- **The item tag cannot be read where the port runs.** `native_item_in_tag`
- **No hover tooltip assertion in the harness.** The `tooltip` hook is
- **`right_click_block` cancels without a swing.** The port calls
- **No `markChanged` equivalent.** Upstream's `VaultServerData.markChanged`
- **A sneak-click for a guest uses the host's sneak bit** if the pin's
- **No in-game run at `0b14f8a`** (launcher + game build absent). Everything else in this file is
- **No log service in the SDK.** The retired bundle's

## Installing

1. Install the [Horizon launcher](https://github.com/horizon-rust/horizon/releases) (0.2.70 or newer).
2. Add `repeatable_trial_vaults.hmod` to the instance's mods.
3. The package is pinned to a specific Horizon build; the launcher checks that pin.

## Licence and credit

Repeatable Trial Vaults was created by its upstream authors; the code, models and assets in the original mod
remain theirs and are used here under **MIT**. The Rust in this repository is a clean-room
rewrite for Horizon, not a translation of the original source.

- `LICENSE` — the upstream licence text.
- `LICENSE-NOTICE.md` — what this port carries and where it came from.
- The upstream project: https://github.com/Buuz135/Repeatable-Trial-Vaults

## Technical details

```
horizon-mod.toml   package manifest (id, version, api, [native] pin)
Cargo.toml         the crate; depends on `horizon-mod-api` from the fetched SDK
src/               lib.rs (the one `impl Hooks`), runtime.rs (pure logic + tests), glue
assets/ data/      the content the package ships
tools/             content generators and the e2e scenario
```

- Build: `cargo horizon-mod build` (packages; it does not compile against the game).
- Test: `cargo test`, `cargo clippy --all-targets -- -D warnings`.
- In-game: `ports/tools/launcher-game.sh run repeatable_trial_vaults` in the campaign tree, or install the
  `.hmod` and play; the harness scenario is `tools/e2e.sh`.

This repository is generated from the campaign's port at `ports/repeatable_trial_vaults/`; the port's own
`notes.md` is the full record (decisions, traps, evidence).

# repeatable_trial_vaults (Horizon port)

A Horizon port of [repeatable_trial_vaults](Buuz135/Repeatable-Trial-Vaults) — MIT.

**Status: first slices.** What is below is what the port actually does today.

## Implemented so far

- A right-click on a `minecraft:vault` with `minecraft:trial_key` or
- `minecraft:ominous_trial_key` resets it **iff** the acting player's UUID is in
- `rewarded_players`. The click is cancelled (the block never sees it), the
- held stack loses the vault config's key count (normally 1; a keyless vault
- consumes 0; `consume_held` skips creative like `ItemStack.consume`), the
- `used` stat is awarded once, and the hand swings.
- The reset is allowed whatever the vault's `vault_state` is (upstream checks
- no state). The vault's own tick then sees the player as unrewarded and moves

## Not yet ported

- No native API to read or write a vanilla block entity.** The port reaches
- `Game.world.block_entities` and `Vault.rewarded_players` directly (see the
- probe). It is a pin-internal dependency; a future pin can move either. Issue:
- "a native read/write hook for a vanilla block entity's saved NBT (or at
- least the vault's `rewarded_players`), so content-logic mods do not pin the
- engine's internal maps".
- The item tag cannot be read where the port runs.** `native_item_in_tag`
- and `native_server_item_in_tag` return `NotServer` on a client execution

## Install

Build the bundle with a native-mod capable launcher, or add the file from the
registry once it is listed. Pinned to Horizon `1d63e0a` and horizon-mixins
`5a64af93` for game 26.3.

## Build from source

```sh
cargo test
python3 tools/horizon.py check --horizon <horizon checkout>
python3 tools/horizon.py build --horizon <horizon checkout>
python3 tools/package.py
```

## Credits and licence

Original mod: Buuz135/Repeatable-Trial-Vaults. Port: AdLf0208. Licence: MIT — see [LICENSE](LICENSE);
the original notices are preserved.

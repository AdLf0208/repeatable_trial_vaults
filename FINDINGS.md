# Repeatable Trial Vaults 1.0.3 — upstream findings

Analysis for the Horizon port. Repository:
<https://github.com/Buuz135/Repeatable-Trial-Vaults>, cloned to
`ports/_shared/upstream/repeatable_trial_vaults/` (shallow, `--depth 1`).
Commit **`23a2529bc488eaee0843991ffb3b872f38c968b3`** ("Increased version",
2026-05-01), which is `version=1.0.3` in `gradle.properties`. The repository
has no release tags in the shallow clone, so the commit is the reference.

Licence: `gradle.properties` says `license=MIT`; the repository's `LICENSE`
file is the **CC0 1.0 Universal** text. Both are permissive; the campaign's
publishing rule (ARCHITECTURE.md §8) still keeps the port local-only until the
maintainer approves.

## Files read

| File | What it holds |
|---|---|
| `common/src/main/java/com/buuz135/repeatabletrialvaults/mixin/MixinVaultBlock.java` | the whole gameplay: a `VaultBlock.useItemOn` HEAD injection |
| `common/src/main/java/com/buuz135/repeatabletrialvaults/Constants.java` | `MOD_ID`, and `CAN_RESET_TRIAL_VAULTS` = item tag `repeatable_trial_vaults:can_reset_trial_vaults` |
| `common/src/main/java/com/buuz135/repeatabletrialvaults/ClientClass.java` | `onTooltip`: the gold line `tooltip.rtv.can_reset_vaults` on tagged stacks |
| `common/src/main/java/com/buuz135/repeatabletrialvaults/CommonClass.java` | empty `init` |
| `common/src/main/resources/data/repeatable_trial_vaults/tags/item/can_reset_trial_vaults.json` | the tag's only members: `minecraft:trial_key`, `minecraft:ominous_trial_key` |
| `common/src/main/resources/assets/repeatable_trial_vaults/lang/en_us.json` | `"tooltip.rtv.can_reset_vaults": "Can Reset Trial Vaults"` |
| `common/src/main/resources/repeatable_trial_vaults.mixins.json` | the one mixin, `MixinVaultBlock` |
| `common/src/main/resources/META-INF/accesstransformer.cfg`, `*.accesswidener` | empty / no relevant entries |
| `fabric/.../RTVClientMod.java`, `neoforge/.../RTVMod.java` | register `ClientClass::onTooltip` as an item-tooltip listener |
| `common/build.gradle`, `gradle.properties` | version, loader ranges, licence |

## Behaviour extracted

`MixinVaultBlock.useItemOn` (`HEAD`, cancellable) runs for a server level when
the clicked block has a `VaultBlockEntity`:

1. the held stack must be in `#repeatable_trial_vaults:can_reset_trial_vaults`;
2. the vault's `VaultServerData.hasRewardedPlayer(player)` must be true;
3. then it awards `Stats.ITEM_USED` for the held item, calls
   `stack.consume(vault.getConfig().keyItem().getCount(), player)`, removes
   `player.getUUID()` from `rewardedPlayers`, calls `markChanged()`, and
   returns `ItemInteractionResult.SUCCESS` (the click is consumed, the hand
   swings, and the vanilla vault path never runs).

Notes on the exact semantics, all reproduced by the port:

- The check is tag membership, **not** "the stack is the vault's configured
  key": a normal trial key can reset an ominous vault. The *consumed count* is
  the vault config's key count (normally 1; `ItemStack.EMPTY` count 0 when a
  vault has no configured key, so a keyless vault is reset for free).
- Nothing checks the vault's `vault_state`; a rewarded player's vault is
  normally `inactive` (or `active` while another unrewarded player is near),
  and the reset is allowed in either.
- The reward list is a set-like list capped at 128 (`MAX_REWARD_PLAYERS`); the
  mixin removes by value, preserving the order of the rest.
- There is no message, sound or particle: the visible effect is that the vault
  becomes active again for that player and can be looted once more.
- `ClientClass.onTooltip` adds the gold (`ChatFormatting.GOLD`) line to any
  stack in the tag, on the client only.

The tag and the lang file are the mod's only data; there are no blocks, items,
recipes or models.

## Where the rewrite differs

| Upstream | Horizon port | Why |
|---|---|---|
| `VaultBlock.useItemOn` HEAD mixin | `right_click_block` (API 21) helper | `native_use_item_on` runs *after* the block's own use; `use_vault` swallows every click on an active vault (`game.rs:5757`), so a rewarded player's click would never reach it when someone else keeps the vault active. `right_click_block` runs before the block and can cancel, which matches the mixin's position. |
| `ItemStack.consume(config.keyItem().getCount(), player)` | `Game::consume_held()` per item (creative-safe) | the pin's helper is one item and already skips creative, like `ItemStack.consume` |
| `VaultServerData.rewardedPlayers.remove(uuid)` + `markChanged()` | `World.block_entities` `get_mut` on `BlockEntity::Vault` and `rewarded_players = without_rewarded(...)` | no native vanilla-block-entity API at the pin; see the gap in `notes.md` |
| `level.getBlockEntity(pos) instanceof VaultBlockEntity` | `BlockEntity::Vault` at `pos` | same test |
| item tag `#repeatable_trial_vaults:can_reset_trial_vaults` | the two vanilla ids, and the tag still shipped in `content/` | the pin's tag reads require a server execution role; a single-player client has none (`native_world_read.rs:36-42`), so the port cannot read the tag where it runs. The tag's members are static in the mod. |
| `SUCCESS` swings the hand | `swing_arm()` then cancel | `right_click_block` cancellation does not swing on its own |
| tooltip listener | `tooltip` (API 12) helper | same client-side line, same gold colour |

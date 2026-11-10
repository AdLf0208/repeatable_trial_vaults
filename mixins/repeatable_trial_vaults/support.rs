// Game-side glue for Repeatable Trial Vaults: the vault reset and the key
// tooltip line. Injected into `crate::game` as
// `repeatable_trial_vaults_state`, so it needs the game and is not part of the
// standalone library (only `runtime.rs` is).
//
// The pin has no native API that reads or writes a *vanilla* block entity
// (`native_block_entity*` answer only for a mod's own blocks), so this uses the
// in-crate `World.block_entities` map (`horizon-client-render/src/world.rs:54`)
// and `Vault.rewarded_players` (`chunk/block_entity.rs:543`), reachable from a
// child of `crate::game` exactly as earlier ports reached `Game::break_block`,
// `Game::save_game` and `Game::add_player_effect`. It is a pin-internal
// dependency and an issue-shaped API gap; both are in `../notes.md`.

use horizon_client::containers::BlockEntity;
use horizon_client::items::ItemStack;
use horizon_client::text::Text;

use crate::game::repeatable_trial_vaults::{
    TOOLTIP_KEY, reset_plan, tooltip_applies, without_rewarded,
};

/// `ChatFormatting.GOLD` (255, 170, 0), packed as the tooltip line colour
/// (`hud::rgba` packs alpha, blue, green, red).
const GOLD: u32 = 0xFF00_AAFF;

/// `MixinVaultBlock.useItemOn`: a reset key on a vault that already rewarded
/// the acting player clears that player from `VaultServerData.rewardedPlayers`
/// and consumes the vault config's key count. Upstream returns
/// `ItemInteractionResult.SUCCESS`, which consumes the click and swings the
/// hand; `right_click_block` cancels the click here, so the swing is sent
/// explicitly.
pub(super) fn on_right_click_block(
    game: &mut crate::game::Game<'_>,
    pos: [i32; 3],
    canceled: &mut bool,
) {
    if !game.native_on("repeatable_trial_vaults") {
        return;
    }
    // `use_hand` skips the block's own use when the acting player sneaks with
    // something in hand; upstream's `VaultBlock.useItemOn` never ran then.
    if game
        .player
        .as_ref()
        .is_some_and(|player| player.shift_key_down)
    {
        return;
    }
    let Some(held) = game.held().cloned() else {
        return;
    };
    let key = (pos[0], pos[1], pos[2]);
    // The same UUID `use_vault` stores (`Game::acting_uuid`): the guest whose
    // turn it is, else the host's level player.
    let player = game.acting_uuid();
    let (rewarded, config_key_count) = match game.world.block_entities.get(&key) {
        Some(BlockEntity::Vault(vault)) => (
            vault.rewarded_players.contains(&player),
            vault.config.key_item.as_ref().map_or(0, |key| key.count),
        ),
        _ => return,
    };
    let Some(plan) = reset_plan(&held.item, held.count, rewarded, config_key_count) else {
        return;
    };
    if let Some(BlockEntity::Vault(vault)) = game.world.block_entities.get_mut(&key) {
        vault.rewarded_players = without_rewarded(&vault.rewarded_players, player);
    }
    // The server data is saved with the chunk; a reset alone changes no block
    // state, so mark the chunk dirty or an autosave would skip it.
    game.world.modified.insert((pos[0] >> 4, pos[2] >> 4));
    for _ in 0..plan.consume {
        game.consume_held();
    }
    // `stack.consume` counts as an item use (`Stats.ITEM_USED`), as upstream.
    game.stats.add("used", &held.item, 1);
    game.swing_arm();
    *canceled = true;
    log::info!("[repeatable_trial_vaults] reset the vault at {pos:?} for {player:?}");
}

/// `ClientClass.onTooltip`: a reset key says it can reset trial vaults.
pub(super) fn on_tooltip(
    game: &crate::game::Game<'_>,
    stack: &ItemStack,
    lines: &mut Vec<(Text, u32)>,
) {
    if !game.native_on("repeatable_trial_vaults") || !tooltip_applies(&stack.item) {
        return;
    }
    lines.push((Text::translate(TOOLTIP_KEY, &[]), GOLD));
}

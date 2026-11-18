//! Repeatable Trial Vaults — the one `impl Hooks` at the crate root.
//!
//! Upstream's `MixinVaultBlock.useItemOn` is here a [`BlockPart`] on `minecraft:vault`: a trial
//! key on a vault that already rewarded the acting player clears that player from
//! `server_data.rewarded_players` and consumes the vault config's key count, so the same player
//! can loot the vault again. Upstream's `onTooltip` is an [`ItemPart`] attached to the reset keys.
//!
//! The rules themselves live in [`runtime`], byte-identical to the retired bundle's `runtime.rs`
//! and tested by `cargo test` without the game.
use mod_api::{
    self, BlockPart, ClientHost, Compound, Hand, Hooks, InteractionResult, ItemPart, ItemStack,
    PlayerRef, Registrar, RegistrationContext, ServerHost, StatType, Tag, Text, TooltipEvent,
    UseItemOnEvent,
};

pub mod runtime;

/// `ChatFormatting.GOLD` (255, 170, 0), packed as the tooltip line colour (`rgba` packs alpha,
/// blue, green, red).
const GOLD: u32 = 0xFF00_AAFF;

/// The vault's saved-data keys (`VaultBlockEntity.ServerData` / `VaultConfig.CODEC`).
const SERVER_DATA: &str = "server_data";
const REWARDED_PLAYERS: &str = "rewarded_players";
const CONFIG: &str = "config";
const KEY_ITEM: &str = "key_item";
const COUNT: &str = "count";

#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Attach the reset to the vanilla vault and the tooltip line to the two trial keys.
    fn register(&self, r: &mut dyn Registrar, _context: &RegistrationContext) {
        let vault = r.block_key("minecraft:vault");
        r.block_part(vault, ResetVault);
        for item in runtime::RESET_KEYS {
            let key = r.item_key(item);
            r.item_part(key, ResetKeyTooltip);
        }
    }
}

/// `MixinVaultBlock.useItemOn`: the block's own use, which the vanilla vault also answers here.
struct ResetVault;

#[mod_api::horizon_part]
impl BlockPart for ResetVault {
    fn use_item_on(
        &self,
        host: &mut dyn ServerHost,
        event: &mut UseItemOnEvent<'_>,
    ) -> Option<InteractionResult> {
        let click = event.click;
        let stack = click.stack?;
        let item = stack.item().id(host);
        let player = host.player(click.player)?;
        let level = host.level(click.dimension.key().id())?;
        let vault = host.block_entity(level, click.pos)?;
        let saved = Tag::Compound(vault.data(host)?);
        let acting = uuid_to_ints(click.player);
        let rewarded = rewarded_players(&saved);
        let plan = runtime::reset_plan(
            &item,
            stack.count(),
            rewarded.contains(&acting),
            key_item_count(&saved),
        )?;

        // `VaultServerData.rewardedPlayers.remove(uuid)`, written through the vanilla block
        // entity's own saved data: `merge_data` loads it and marks the chunk changed, which is
        // the `markChanged` the retired bundle had to fake.
        let remaining = runtime::without_rewarded(&rewarded, acting);
        let mut server = Compound::new();
        server.insert(REWARDED_PLAYERS.into(), rewarded_tag(&remaining));
        let mut patch = Compound::new();
        patch.insert(SERVER_DATA.into(), Tag::Compound(server));
        if !matches!(vault.merge_data(host, patch), Ok(true)) {
            return None;
        }

        consume_held(host, player, click.hand, stack, plan.consume);
        // `stack.consume` counts as an item use (`Stats.ITEM_USED`), as upstream.
        player.award_stat(host, StatType::Used, &item, 1);
        // Upstream answers `SUCCESS`; a server-only block Part cannot swing the client's
        // prediction, so the answer is the one that swings the server's hand (`notes.md`).
        Some(InteractionResult::SuccessServer)
    }
}

/// `ClientClass.onTooltip`: a reset key says it can reset trial vaults.
struct ResetKeyTooltip;

#[mod_api::horizon_part]
impl ItemPart for ResetKeyTooltip {
    fn tooltip(&self, host: &dyn ClientHost, event: &mut TooltipEvent<'_>) {
        if !runtime::tooltip_applies(&event.stack.item().id(host)) {
            return;
        }
        event
            .lines
            .push((Text::translate(runtime::TOOLTIP_KEY, Vec::new()), GOLD));
    }
}

/// `ItemStack.consume(count, player)`: the held stack loses `count`, and an emptied hand is None.
/// Creative keeps the stack, as the retired bundle's `consume_held` did.
fn consume_held(
    host: &mut dyn ServerHost,
    player: PlayerRef,
    hand: Hand,
    stack: &ItemStack,
    count: u32,
) {
    if count == 0 || player.is_creative(&*host) == Some(true) {
        return;
    }
    let Some(living) = host.living(player.entity()) else {
        return;
    };
    let left = stack.count().saturating_sub(count);
    let held = if left == 0 {
        None
    } else {
        let mut held = stack.clone();
        if held.set_count(left).is_err() {
            return;
        }
        Some(held)
    };
    let _ = living.set_hand_item(host, hand, held);
}

/// `server_data.rewarded_players`: a list of int arrays, each four ints of one player's UUID.
fn rewarded_players(saved: &Tag) -> Vec<[i32; 4]> {
    let Some(Tag::List(list)) = saved
        .get(SERVER_DATA)
        .and_then(|server| server.get(REWARDED_PLAYERS))
    else {
        return Vec::new();
    };
    list.iter()
        .filter_map(|uuid| match uuid {
            Tag::IntArray(ints) => <[i32; 4]>::try_from(ints.as_slice()).ok(),
            _ => None,
        })
        .collect()
}

/// The same list, in the shape `Vault.saveAdditional` writes.
fn rewarded_tag(players: &[[i32; 4]]) -> Tag {
    Tag::List(
        players
            .iter()
            .map(|uuid| Tag::IntArray(uuid.to_vec()))
            .collect(),
    )
}

/// `config.key_item.count`: the number of keys a reset consumes (a vault without a key item
/// consumes none).
fn key_item_count(saved: &Tag) -> u32 {
    let count = saved
        .get(CONFIG)
        .and_then(|config| config.get(KEY_ITEM))
        .and_then(|item| item.get(COUNT));
    match count {
        Some(Tag::Int(count)) => (*count).max(0) as u32,
        Some(Tag::Byte(count)) => (*count).max(0) as u32,
        Some(Tag::Short(count)) => (*count).max(0) as u32,
        Some(Tag::Long(count)) => (*count).max(0) as u32,
        _ => 0,
    }
}

/// A UUID's four ints, the shape NBT stores and `runtime` compares (the engine's `ints_uuid`
/// folds them most significant first).
fn uuid_to_ints(uuid: u128) -> [i32; 4] {
    [
        (uuid >> 96) as u32 as i32,
        (uuid >> 64) as u32 as i32,
        (uuid >> 32) as u32 as i32,
        uuid as u32 as i32,
    ]
}

/// The inverse of [`uuid_to_ints`].
#[cfg(test)]
fn ints_to_uuid(ints: [i32; 4]) -> u128 {
    ints.iter()
        .fold(0_u128, |acc, &int| acc << 32 | u128::from(int as u32))
}

#[cfg(test)]
mod tests {
    use super::*;

    const PLAYER: [i32; 4] = [568_489_192, -1_847_837_207, -1_999_698_076, 1_285_276_242];
    const OTHER: [i32; 4] = [0, 0, 0, 2];

    #[test]
    fn a_uuid_s_ints_round_trip() {
        for uuid in [
            0_u128,
            1,
            u128::MAX,
            0x0123_4567_89ab_cdef_fedc_ba98_7654_3210,
        ] {
            assert_eq!(ints_to_uuid(uuid_to_ints(uuid)), uuid);
        }
        assert_eq!(
            ints_to_uuid(PLAYER),
            0x21E2_74E8_91DC_3DE9_88CF_0764_4C9B_C252
        );
    }

    #[test]
    fn a_uuid_reads_its_int_array() {
        let saved = Tag::compound([(
            SERVER_DATA,
            Tag::compound([(
                REWARDED_PLAYERS,
                Tag::List(vec![
                    Tag::IntArray(PLAYER.to_vec()),
                    Tag::IntArray(OTHER.to_vec()),
                ]),
            )]),
        )]);
        assert_eq!(rewarded_players(&saved), vec![PLAYER, OTHER]);
    }

    #[test]
    fn a_vault_without_saved_data_has_no_rewarded_players() {
        assert_eq!(
            rewarded_players(&Tag::Compound(Compound::new())),
            Vec::<[i32; 4]>::new()
        );
        let half = Tag::compound([(SERVER_DATA, Tag::compound([(SERVER_DATA, Tag::Int(1))]))]);
        assert_eq!(rewarded_players(&half), Vec::<[i32; 4]>::new());
    }

    #[test]
    fn the_written_list_is_what_the_vault_reads_back() {
        let saved = Tag::compound([(
            SERVER_DATA,
            Tag::compound([(REWARDED_PLAYERS, rewarded_tag(&[OTHER, PLAYER]))]),
        )]);
        assert_eq!(rewarded_players(&saved), vec![OTHER, PLAYER]);
    }

    #[test]
    fn the_config_key_item_s_count_is_read() {
        let with = |count: Tag| {
            Tag::compound([(
                CONFIG,
                Tag::compound([(
                    KEY_ITEM,
                    Tag::compound([
                        ("id", Tag::String("minecraft:trial_key".into())),
                        ("count", count),
                    ]),
                )]),
            )])
        };
        assert_eq!(key_item_count(&with(Tag::Int(2))), 2);
        assert_eq!(key_item_count(&with(Tag::Byte(1))), 1);
        assert_eq!(key_item_count(&with(Tag::String("1".into()))), 0);
        assert_eq!(key_item_count(&with(Tag::Int(-4))), 0);
        assert_eq!(
            key_item_count(&Tag::compound([(CONFIG, Tag::Compound(Compound::new()))])),
            0
        );
    }

    #[test]
    fn the_tooltip_line_is_gold() {
        assert_eq!(GOLD, 0xFF00_AAFF);
    }
}

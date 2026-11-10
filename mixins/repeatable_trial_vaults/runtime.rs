// Repeatable Trial Vaults: the pure rules behind a trial key resetting a
// vault that already rewarded the player.
//
// Upstream (`MixinVaultBlock.useItemOn`) removes the player's UUID from
// `VaultServerData.rewardedPlayers` when a stack in
// `#repeatable_trial_vaults:can_reset_trial_vaults` is used on a vault that
// already rewarded them, consuming the vault config's key count. These
// functions hold that decision, the list edit and the tooltip rule;
// `support.rs` reads the vault block entity and applies them.

/// The items upstream's `can_reset_trial_vaults` tag names. The pin's tag
/// reads need a server execution role, which a single-player client does not
/// have, so the port names the two vanilla members directly (see
/// `../notes.md`).
pub const RESET_KEYS: [&str; 2] = ["minecraft:trial_key", "minecraft:ominous_trial_key"];

/// The lang key of upstream's tooltip line.
pub const TOOLTIP_KEY: &str = "tooltip.rtv.can_reset_vaults";

/// Whether `item` may reset a vault.
pub fn is_reset_key(item: &str) -> bool {
    RESET_KEYS.contains(&item)
}

/// What a reset click consumes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Reset {
    pub consume: u32,
}

/// `MixinVaultBlock.useItemOn`: the stack must be a reset key, the vault must
/// have rewarded this player, and the stack must hold something. The consumed
/// count is the vault config's key count (`ItemStack.consume` clamps at the
/// stack size; a config without a key consumes none).
pub fn reset_plan(
    held_item: &str,
    held_count: u32,
    rewarded: bool,
    config_key_count: u32,
) -> Option<Reset> {
    (held_count > 0 && rewarded && is_reset_key(held_item)).then(|| Reset {
        consume: config_key_count.min(held_count),
    })
}

/// `VaultServerData.rewardedPlayers.remove(uuid)`: the order of the rest is
/// kept (upstream removes by value).
pub fn without_rewarded(rewarded: &[[i32; 4]], player: [i32; 4]) -> Vec<[i32; 4]> {
    rewarded
        .iter()
        .copied()
        .filter(|rewarded| *rewarded != player)
        .collect()
}

/// Whether the tooltip line goes on `item` (`ClientClass.onTooltip`).
pub fn tooltip_applies(item: &str) -> bool {
    is_reset_key(item)
}

#[cfg(test)]
mod tests {
    use super::*;

    const PLAYER: [i32; 4] = [0, 0, 0, 1];
    const OTHER: [i32; 4] = [0, 0, 0, 2];

    #[test]
    fn only_the_two_trial_keys_reset_a_vault() {
        assert!(is_reset_key("minecraft:trial_key"));
        assert!(is_reset_key("minecraft:ominous_trial_key"));
        assert!(!is_reset_key("minecraft:stick"));
        assert!(!is_reset_key("minecraft:air"));
        assert!(!is_reset_key("repeatable_trial_vaults:trial_key"));
    }

    #[test]
    fn a_rewarded_player_with_a_trial_key_resets_and_consumes_one() {
        assert_eq!(
            reset_plan("minecraft:trial_key", 1, true, 1),
            Some(Reset { consume: 1 })
        );
        assert_eq!(
            reset_plan("minecraft:ominous_trial_key", 5, true, 1),
            Some(Reset { consume: 1 })
        );
    }

    #[test]
    fn an_unrewarded_player_does_not_reset() {
        assert_eq!(reset_plan("minecraft:trial_key", 1, false, 1), None);
    }

    #[test]
    fn a_non_key_does_not_reset_even_when_rewarded() {
        assert_eq!(reset_plan("minecraft:stick", 64, true, 1), None);
    }

    #[test]
    fn an_empty_stack_does_not_reset() {
        assert_eq!(reset_plan("minecraft:trial_key", 0, true, 1), None);
    }

    #[test]
    fn a_config_without_a_key_consumes_nothing() {
        assert_eq!(
            reset_plan("minecraft:trial_key", 1, true, 0),
            Some(Reset { consume: 0 })
        );
    }

    #[test]
    fn the_consume_count_never_exceeds_the_held_stack() {
        assert_eq!(
            reset_plan("minecraft:trial_key", 2, true, 5),
            Some(Reset { consume: 2 })
        );
    }

    #[test]
    fn only_the_rewarded_uuid_leaves_the_list_in_order() {
        assert_eq!(
            without_rewarded(&[PLAYER, OTHER, [0, 0, 0, 3]], PLAYER),
            vec![OTHER, [0, 0, 0, 3]]
        );
        assert_eq!(
            without_rewarded(&[PLAYER, OTHER], [0, 0, 0, 9]),
            vec![PLAYER, OTHER]
        );
        assert_eq!(
            without_rewarded(&[PLAYER, PLAYER], PLAYER),
            Vec::<[i32; 4]>::new()
        );
        assert_eq!(without_rewarded(&[], PLAYER), Vec::<[i32; 4]>::new());
    }

    #[test]
    fn the_tooltip_covers_the_two_trial_keys_only() {
        assert!(tooltip_applies("minecraft:trial_key"));
        assert!(tooltip_applies("minecraft:ominous_trial_key"));
        assert!(!tooltip_applies("minecraft:stick"));
        assert_eq!(TOOLTIP_KEY, "tooltip.rtv.can_reset_vaults");
    }
}

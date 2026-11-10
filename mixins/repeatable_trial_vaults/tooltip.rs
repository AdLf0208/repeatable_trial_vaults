// Runs at the head of `Game::native_tooltip` (API 12): a reset key says it can
// reset trial vaults.
fn add_key_tooltip(
    game: &crate::game::Game<'_>,
    stack: &horizon_client::items::ItemStack,
    lines: &mut Vec<(Text, u32)>,
) {
    crate::game::repeatable_trial_vaults_state::on_tooltip(game, stack, lines);
}

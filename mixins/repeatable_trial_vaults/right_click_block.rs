// Runs at the head of `Game::native_right_click_block` (API 21): a trial key
// on a vault that already rewarded the acting player resets the vault.
fn reset_vault(game: &mut crate::game::Game<'_>, pos: [i32; 3], canceled: &mut bool) {
    crate::game::repeatable_trial_vaults_state::on_right_click_block(game, pos, canceled);
}

# Validation

> **Historical (retired `.hnmod` bundle).** Everything below was produced by the staged
> `tools/horizon.py` ladder at Horizon `41f822b6` / horizon-mixins `5a64af9` for the `.hnmod`
> container, which Horizon retired (#16941). `compatibility.json`, `mixins/` and that ladder no
> longer exist in this port. The current package's evidence is in
> [`notes.md`](notes.md) §"Migration verification (SDK `0b14f8a`)" and
> `ports/_shared/evidence/repeatable_trial_vaults/sdk-0b14f8a/`.

Validated on Linux with Rust 1.95.0 on 2026-11-07, against the exact revisions
in `compatibility.json` (Horizon
`41f822b659789780f58d32c63ddfb6887ea1b8bf`, horizon-mixins
`5a64af938ec86b00d53d16a408aabc0038fb3e57`) and the 26.3 prepared resources at
`/home/adlf/Desktop/horizon/.local/horizon-client/26.3`. This supersedes the
`c9d474d` validation, whose build and e2e log no longer existed; every row below
is from the re-run recorded in [`notes.md`](notes.md) §Verification.

| Check | Result |
|---|---|
| `cargo fmt --all --check` | exit 0 |
| `cargo test --locked --offline` | `test result: ok. 9 passed; 0 failed; …` |
| `cargo clippy --all-targets --locked --offline -- -D warnings` | exit 0 |
| `python3 tools/horizon.py stage` | pinned export + plan + apply, exit 0 |
| `python3 tools/horizon.py check` | the injected client checks, `cargo_exit: 0` |
| `python3 tools/horizon.py test` | 9 embedded tests pass, `cargo_exit: 0` |
| `python3 tools/horizon.py build` | fast client built, `cargo_exit: 0`, 0 warnings |
| `python3 tools/test_stage.py` | deterministic stage, AST-only changes, pin unchanged, exit 0 |
| `tools/e2e-suite.sh` default | loot → stick control → reset → loot 2 → save/reload → loot 3; `PASS`, `default EXIT:0` |
| `tools/e2e-suite.sh` counterfactual | a stick cannot reset or loot the rewarded vault; `counterfactual EXIT:0` |
| `tools/e2e-suite.sh` negative | the counterfactual assertion inverted must fail: `negative EXIT:1` (`SUITE PASS`) |
| `cargo-horizon-mod build` / `check` | `repeatable_trial_vaults.hmod`, 962 B, `{"ok":true,…}` |

The exact commands, exit codes, verbatim `test result:` lines, e2e `ctl`
transcripts and the `.hmod` SHA-256 are recorded in
[`notes.md`](notes.md) §Verification and in
[`ports/_shared/evidence/repeatable_trial_vaults/repin-41f822b/`](../_shared/evidence/repeatable_trial_vaults/repin-41f822b/).
The probe for the vanilla block-entity write is in `notes.md` §The probe.

## Campaign pin `1d63e0a5` and the one-file bundle (2026-11-10)

Migrated from `41f822b6` to Horizon
`1d63e0a5a37a7a708eb0b32b49bf0dfeb28ed8a9` (`game.rs` SHA-256
`64813cf4db0b9c3983d42908609bb633b9fbbc705f0c890396f940a6c7cef80f`), mixins
`5a64af938ec86b00d53d16a408aabc0038fb3e57`. `tools/package.sh` builds the
content mod, copies it to
`mixins/repeatable_trial_vaults/data/repeatable_trial_vaults-content.hmod`, then
packages the bundle.

| Check | Result |
|---|---|
| `cargo fmt -- --check` | pass |
| `cargo clippy --all-targets --locked --offline -- -D warnings` | pass, 0 warnings |
| `cargo test --locked --offline` | 9 passed, 0 failed |
| `tools/horizon.py stage/check/test/build` at the pin | `cargo_exit: 0`, 0 warnings, 9 embedded tests, fast build |
| `EMBEDDED=1 tools/e2e.sh` (loot, reset, reload; no `--dev-mod`) | **PASS**, `EXIT:0` |
| `COUNTERFACTUAL=1 NEGATIVE=1 tools/e2e.sh` | **FAIL** (inverted control), `EXIT:1` |
| `content/repeatable_trial_vaults.hmod` | 1,042 B, SHA-256 `a170bf14…d82f662`, 3 entries |
| `repeatable_trial_vaults.hnmod` | 7,606 B, SHA-256 `8647b531…de2dc7e9`, 8 entries incl. the embedded content |

The content half here is upstream's `can_reset_trial_vaults` item tag plus the
tooltip lang string — no registrable item or block. `/clear @s #<tag>` reports
"Unknown item tag" at this pin in **both** the embedded and the control run, so
the tag is not an observable probe; the control therefore asserts that the
helper wrote nothing into an unusable cache, and the content evidence is the
byte-identical written file plus the behavioural legs (whose COUNTERFACTUAL /
NEGATIVE runs prove they can fail).

# Changelog

## [1.1.0] - 2026-11-17

Parity with the Unity plugin 1.3.0-preview.1 (`unity-plugin-development`
`feat/standard-score-updates`). Additive: every 1.0.0 method, signal and wire frame is kept.

### Added
- `game_end(score, level = 1, ...)` and the `game_end_ok` signal: the call a game makes when the
  player's game is over. It sends the same `level_end` frame. `level_end()` and `level_end_ok`
  are now legacy aliases, kept so existing games keep working.
- Built-in live score reporting: `report_score(level, score)`. Tracking starts on the
  `level_begin` ack; `score_update` goes out every 2 s; `level_end` sends the final score first,
  so the last `score_update` equals the `level_end` score. Same wire format as Unity.
- `get_merchant_prize_info()`, `get_leaderboard_around_score(target_score)`,
  `get_tournament_info()` (Unity's validation and 10 s timeout).
- `prize_tickets` in the `level_end` reply are posted to the page as `prize_won` and emitted as
  the `prize_won` signal.
- Fast Restart: `send_session_option_fast_restart(include_continue, prepared)`,
  `send_restart_ready()`, `session_replaced`, `fast_restart_failed`,
  `restart_prepare_requested`. The plugin adopts the replacement session from the page's
  `luxodd:session` event or the restart message's `jwt`.
- Named session options: `send_session_option_continue/restart/end/both()`;
  `back_to_system()` and `back_to_system_with_error()`.
- Runtime context from `luxodd:session`: `runtime_platform`, `arcade_layout`, `is_arcade`,
  `is_pawn`, `is_rook`, `runtime_context_changed`.
- Config: `logs_enabled` (off), `built_in_score_reporting` (on), `score_update_interval_seconds`.
- Tests for all of the above, and the frozen 1.0.0 suite run against the current plugin.

### Changed
- Logging is off by default; message and response bodies are never logged (1.0.0 printed the
  whole message when it could not parse one).
- With `wsHost` the socket scheme follows the page (`ws` on http). The `ws` URL parameter is read
  first, as in Unity. The page's `luxodd:session` session wins over URL values.
- The dev token is saved in `res://luxodd_dev_config.tres` and left out of exports; a token found
  in the addon config is moved there. Exporting with a token in a shipped config is an error.
- Host messages are built with `JSON.stringify` instead of string formatting.
- `add_balance` and `charge_balance` are deprecated (warn once); games must not change credit.

### Fixed
- After one failed reconnect attempt the plugin stopped retrying and never emitted
  `reconnect_failed`.


## [1.0.0] - 2026-04-02

### Added
- Initial release
- WebSocket connection with automatic reconnection
- Full command protocol (profile, balance, gameplay, leaderboard, sessions)
- Host page bridge via JavaScriptBridge (postMessage interop)
- Health check ping system
- Editor plugin with dev token setup and export validation
- Configuration resource for server settings
- Example project with UI for testing all API methods

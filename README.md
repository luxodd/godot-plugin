# Luxodd Godot Plugin

**Lightweight integration for building Godot games on Luxodd's arcade platform.**

---

## Documentation

For detailed guides, refer to the official Luxodd docs:

- Plugins Overview: https://docs.luxodd.com/docs/category/plugins
- Godot Setup & Installation: https://docs.luxodd.com/docs/arcade-launch/godot-plugin/installation
- Configuration and Usage: https://docs.luxodd.com/docs/arcade-launch/godot-plugin/configuration
- Testing & Examples: https://docs.luxodd.com/docs/arcade-launch/godot-plugin/testing
- API Reference: https://docs.luxodd.com/docs/arcade-launch/godot-plugin/api-reference

---

## Quick Start

1. Copy the `addons/luxodd/` folder into your Godot project.
2. Enable the plugin in **Project > Project Settings > Plugins**.
3. Set your dev token via **Project > Tools > Set Luxodd Dev Token**. It is saved in
   `res://luxodd_dev_config.tres`, which the plugin never reads in a web build and never exports.
   Add that file to `.gitignore`.
4. Use the `Luxodd` autoload singleton in your scripts.
5. Export as **Web** for production use.

---

## Requirements

- Godot 4.3 or higher (tested on 4.7.2)
- Web export templates installed (for production builds)
- The **Compatibility** renderer for web exports. Godot's web export renders through WebGL 2;
  the export plugin warns if `rendering/renderer/rendering_method.web` is anything else.

---

## Project Structure

```
addons/luxodd/
├── plugin.cfg              # Plugin manifest
├── plugin.gd               # Editor plugin (autoload, menu, export)
├── luxodd.gd               # Main autoload singleton (developer API)
├── config/
│   ├── luxodd_config.gd    # Configuration resource class
│   └── luxodd_config.tres  # Default config (shipped in builds: no token here)
├── network/
│   ├── luxodd_websocket.gd # WebSocket transport + reconnection
│   └── luxodd_protocol.gd  # JSON command protocol
├── bridge/
│   └── luxodd_bridge.gd    # Host page postMessage and luxodd:session interop
├── data/
│   ├── command_types.gd    # Wire protocol constants
│   ├── payloads.gd         # Payload builder helpers
│   └── pin_code_hasher.gd  # Pin code hashing utility
├── util/
│   └── luxodd_log.gd       # Plugin logging (off by default, never logs bodies)
└── editor/
    ├── dev_token_dialog.gd # Dev token editor popup
    └── export_plugin.gd    # Web export checks
```

---

## Usage

A complete run: connect, show the prize, report the score while playing, send one `level_end`,
ask for one popup, then follow the player's choice.

```gdscript
extends Node

var _score := 0

func _ready() -> void:
    Luxodd.connected.connect(_on_connected)
    Luxodd.profile_received.connect(_on_profile)
    Luxodd.merchant_prize_info_received.connect(_on_prize)
    Luxodd.level_end_ok.connect(_on_level_end_ok)
    Luxodd.host_action_received.connect(_on_host_action)
    Luxodd.fast_restart_failed.connect(func(_code, _reason): Luxodd.back_to_system_with_error())
    Luxodd.runtime_context_changed.connect(_on_runtime_context)
    Luxodd.command_error.connect(_on_error)
    Luxodd.connect_to_server()

func _on_connected() -> void:
    Luxodd.notify_game_ready()
    Luxodd.start_health_check()
    Luxodd.get_profile()
    Luxodd.get_merchant_prize_info()

func start_run() -> void:
    _score = 0
    Luxodd.level_begin(1)           # score reporting starts when this is acknowledged

func add_points(points: int) -> void:
    _score += points
    Luxodd.report_score(1, _score)  # sent as score_update every 2 s

func game_over() -> void:
    Luxodd.level_end(1, _score)     # the final score_update goes out first

func _on_level_end_ok() -> void:
    Luxodd.send_session_option_fast_restart(true)   # Continue, Restart or End

func _on_host_action(action: String) -> void:
    match action:
        "continue", "restart":      # on "restart" the plugin is already on the new session
            start_run()
        "end":
            Luxodd.back_to_system()

func _on_profile(profile: Dictionary) -> void:
    print("Welcome, %s!" % profile.get("game_handle", ""))   # never log the email

func _on_prize(is_active: bool, prize: Dictionary) -> void:
    pass  # show the prize and its goal_score when is_active

func _on_runtime_context(platform: String, arcade_layout: String) -> void:
    pass  # "arcade" + "rook"/"pawn": the cabinet layout draws the leaderboard beside the game

func _on_error(command: String, code: int, _message: String) -> void:
    push_warning("Luxodd error [%s] %d" % [command, code])
```

---

## API Reference

Everything from 1.0.0 is kept with the same arguments and the same frames on the wire.
Entries marked **1.1.0** are new and use the same wire strings as the Unity plugin
1.3.0-preview.1.

### Connection

| Method | Signal |
|---|---|
| `connect_to_server()` | `connected()` / `connection_failed(error)` |
| `disconnect_from_server()` | `disconnected()` |
| `get_server_endpoint()` **1.1.0** | — the endpoint in use, without the token |

Where the session comes from, in order: the arcade page's `luxodd:session` event
(`{token, wsUrl}`), then the `token` and `ws` / `wsHost` URL parameters, then the config. With
`wsHost` the scheme follows the page: `wss` on https, `ws` on http (1.0.0 always used `wss`, so a
page served over http, such as a local sbx mission, could not connect). The page repeats the
`luxodd:session` event while the game runs; the plugin ignores repeats of its own session and
reconnects with a new one only when its socket has closed for good.

### Host Bridge

| Method | Signal / message posted |
|---|---|
| `notify_game_ready()` | `{type: "gameReady"}` |
| `back_to_system()` **1.1.0** | Stops health check and score reporting, then `{type: "session_end"}` |
| `back_to_system_with_error(message)` **1.1.0** | As above, for a fatal error |
| `notify_session_end()` | `{type: "session_end"}` (1.0.0; prefer `back_to_system()`) |
| `send_session_option_continue()` / `_restart()` / `_end()` / `_both()` **1.1.0** | `{type: "session_options", action}` |
| `send_session_option_fast_restart(include_continue = false, prepared = false)` **1.1.0** | `{type: "session_options", action: "restart" or "both", keepGameLoaded: true}` (+ `restartPreparationVersion: 1`) |
| `send_restart_ready(request_id)` **1.1.0** | `{type: "restart_ready", requestId}` |
| `send_session_option(action)` | `{type: "session_options", action}` (1.0.0) |
| — | `host_action_received(action)`: `"continue"`, `"restart"`, `"end"` |
| — | `host_jwt_received(token)` |
| — | `session_replaced()` **1.1.0**: Fast Restart is on the new session; `host_action_received("restart")` follows |
| — | `fast_restart_failed(status_code, reason)` **1.1.0**: end the session |
| — | `restart_prepare_requested(request_id)` **1.1.0** |

**Fast Restart:** on Restart the arcade keeps the game loaded and hands it a new session. The
plugin stops the old session's health check and score reporting, drops anything queued for it,
connects with the new token, resumes the health check, then emits `session_replaced` and
`host_action_received("restart")`. Reset the run in place and send `level_begin`. If the new
session is not up within 10 s, `fast_restart_failed` fires.

### Runtime context (layout) **1.1.0**

From the arcade page's `luxodd:session` event, mapped as Unity's `LuxoddRuntimeContext`:

| Property | Values |
|---|---|
| `has_host_runtime_context` | `true` once the page named a platform |
| `runtime_platform` | `"web"`, `"arcade"` or `""` |
| `arcade_layout` | `"pawn"`, `"rook"` or `""` (arcade only) |
| `is_web_runtime`, `is_arcade`, `is_pawn`, `is_rook` | booleans |

Signal: `runtime_context_changed(platform, arcade_layout)`. Decide the layout from these, never
from the screen size. On cabinets the platform's layout shows the live leaderboard beside the
game, fed by `score_update`, so the game does not need its own.

### User

| Method | Signal |
|---|---|
| `get_profile()` | `profile_received(profile: Dictionary)` |
| `get_balance()` | `balance_received(balance: Dictionary)` (read-only) |
| `add_balance(amount, pin_code)` | `balance_added()` — **deprecated**, games must not change credit |
| `charge_balance(amount, pin_code)` | `balance_charged()` — **deprecated**, games must not change credit |

### Gameplay

| Method | Signal |
|---|---|
| `level_begin(level)` | `level_begin_ok()` |
| `level_end(level, score, ...)` | `level_end_ok()`; `prize_won(tickets)` **1.1.0** when the reply carries `prize_tickets` (already posted to the page as `{type: "prize_won", tickets}`) |
| `report_score(level, score)` **1.1.0** | `score_update_handled(response)` / `score_update_failed(code, reason)` |
| `get_leaderboard()` | `leaderboard_received(data: Dictionary)` |
| `get_leaderboard_around_score(target_score)` **1.1.0** | `leaderboard_around_score_received(data: Dictionary)` |
| `get_best_score()` | `best_score_received(data: Dictionary)` |
| `get_recent_games()` | `recent_games_received(data: Dictionary)` |

**Live score:** tracking starts when `level_begin` is acknowledged. The plugin sends
`{type: "score_update", version: "1.0", payload: {request_id, score, level}}` every
`score_update_interval_seconds` with the latest `report_score` value, one at a time. `level_end`
sends the final value first (waiting at most 2 s), so the last `score_update` always equals the
`level_end` score. The cabinet's live leaderboard panel and prize progress read these updates.

### Prizes and tournaments **1.1.0**

| Method | Signal |
|---|---|
| `get_merchant_prize_info()` | `merchant_prize_info_received(is_active: bool, prize: Dictionary)` |
| `get_tournament_info()` | `tournament_info_received(result)`: `outcome` is `active` (with `tournament_id`, `dynamic_hardness`, `min_score`), `inactive`, `unavailable`, `timed_out` or `malformed` |

### User Data Storage

| Method | Signal |
|---|---|
| `get_user_data()` | `user_data_received(data: Variant)` |
| `set_user_data(data)` | `user_data_set()` |

### Sessions & Betting

| Method | Signal |
|---|---|
| `get_session_info()` | `session_info_received(info: Dictionary)` |
| `get_betting_session_missions()` | `betting_missions_received(missions: Dictionary)` |
| `send_strategic_betting_result(results)` | `strategic_betting_result_sent()` |

### Health Check

| Method | Description |
|---|---|
| `start_health_check(interval)` | Start periodic health pings (default: 2s) |
| `stop_health_check()` | Stop health pings |

### Errors

All command failures emit `command_error(command: String, status_code: int, message: String)`.

---

## Configuration

Edit `addons/luxodd/config/luxodd_config.tres` in the Godot inspector. A config saved by 1.0.0
loads unchanged; new fields take their defaults.

| Property | Default | Description |
|---|---|---|
| `server_address` | `wss://game-server.luxodd.com` | Backend WebSocket URL |
| `developer_debug_token` | `""` | Game API key for editor/desktop testing. Keep it in `luxodd_dev_config.tres`; the export fails loudly if a shipped config has one |
| `max_reconnect_attempts` | `3` | Reconnection attempts before giving up |
| `reconnect_delay_seconds` | `0.5` | Delay between reconnection attempts |
| `health_check_interval_seconds` | `2.0` | Health ping interval |
| `command_timeout_seconds` | `4.0` | Reserved; not used yet |
| `logs_enabled` **1.1.0** | `false` | Plugin log lines. Bodies are never logged |
| `built_in_score_reporting` **1.1.0** | `true` | Live score reporting |
| `score_update_interval_seconds` **1.1.0** | `2.0` | `score_update` cadence |

---

## Tests

`tests/run_tests.sh` starts the mock server and runs `tests/test_runner.gd`, then the frozen
1.0.0 suite in `tests/compat/` unchanged against the current plugin, then checks that the log
holds no email or token.

---

## License

MIT

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
3. Set your dev token via **Tools > Set Luxodd Dev Token**.
4. Use the `Luxodd` autoload singleton in your scripts.
5. Export as **HTML5 (Web)** for production use.

---

## Requirements

- Godot 4.3 or higher
- HTML5 export templates installed (for production builds)

---

## Project Structure

```
addons/luxodd/
├── plugin.cfg              # Plugin manifest
├── plugin.gd               # Editor plugin (autoload, menu, export)
├── luxodd.gd               # Main autoload singleton (developer API)
├── config/
│   ├── luxodd_config.gd    # Configuration resource class
│   └── luxodd_config.tres  # Default config
├── network/
│   ├── luxodd_websocket.gd # WebSocket transport + reconnection
│   └── luxodd_protocol.gd  # JSON command protocol
├── bridge/
│   └── luxodd_bridge.gd    # Host page postMessage interop
├── data/
│   ├── command_types.gd    # Wire protocol constants
│   ├── payloads.gd         # Payload builder helpers
│   └── pin_code_hasher.gd  # Pin code hashing utility
└── editor/
    ├── dev_token_dialog.gd # Dev token editor popup
    └── export_plugin.gd    # HTML5 export validation
```

---

## Usage

```gdscript
extends Node

func _ready() -> void:
    Luxodd.connected.connect(_on_connected)
    Luxodd.profile_received.connect(_on_profile)
    Luxodd.balance_received.connect(_on_balance)
    Luxodd.command_error.connect(_on_error)
    Luxodd.host_action_received.connect(_on_host_action)
    Luxodd.connect_to_server()

func _on_connected() -> void:
    Luxodd.notify_game_ready()
    Luxodd.get_profile()
    Luxodd.get_balance()
    Luxodd.start_health_check()

func _on_profile(profile: Dictionary) -> void:
    print("Welcome, %s!" % profile.get("name", ""))

func _on_balance(balance: Dictionary) -> void:
    print("Balance: %s" % str(balance))

func _on_host_action(action: String) -> void:
    match action:
        "restart":
            get_tree().reload_current_scene()
        "end":
            Luxodd.notify_session_end()

func _on_error(command: String, code: int, message: String) -> void:
    push_warning("Luxodd error [%s] %d: %s" % [command, code, message])
```

---

## API Reference

### Connection

| Method | Signal |
|---|---|
| `connect_to_server()` | `connected()` / `connection_failed(error)` |
| `disconnect_from_server()` | `disconnected()` |

### Host Bridge

| Method | Signal |
|---|---|
| `notify_game_ready()` | — |
| `notify_session_end()` | — |
| `send_session_option(action)` | — |
| — | `host_jwt_received(token)` |
| — | `host_action_received(action)` |

### User

| Method | Signal |
|---|---|
| `get_profile()` | `profile_received(profile: Dictionary)` |
| `get_balance()` | `balance_received(balance: Dictionary)` |
| `add_balance(amount, pin_code)` | `balance_added()` |
| `charge_balance(amount, pin_code)` | `balance_charged()` |

### Gameplay

| Method | Signal |
|---|---|
| `level_begin(level)` | `level_begin_ok()` |
| `level_end(level, score, ...)` | `level_end_ok()` |
| `get_leaderboard()` | `leaderboard_received(data: Dictionary)` |
| `get_best_score()` | `best_score_received(data: Dictionary)` |
| `get_recent_games()` | `recent_games_received(data: Dictionary)` |

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

Edit `addons/luxodd/config/luxodd_config.tres` in the Godot inspector:

| Property | Default | Description |
|---|---|---|
| `server_address` | `wss://game-server.luxodd.com` | Backend WebSocket URL |
| `developer_debug_token` | `""` | JWT token for local testing |
| `max_reconnect_attempts` | `3` | Reconnection attempts before giving up |
| `reconnect_delay_seconds` | `0.5` | Delay between reconnection attempts |
| `health_check_interval_seconds` | `2.0` | Health ping interval |
| `command_timeout_seconds` | `4.0` | Command response timeout |

---

## License

MIT

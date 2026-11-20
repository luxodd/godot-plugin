@tool
class_name LuxoddConfig
extends Resource

## Configuration resource for the Luxodd plugin.
## Edit this in the Godot inspector or via the editor plugin menu.
##
## Fields added after 1.0.0 have defaults, so a config saved by an older plugin loads unchanged.

@export var server_address: String = "wss://game-server.luxodd.com"
## Your game API key, for editor and desktop testing only. Keep it in res://luxodd_dev_config.tres,
## which the plugin never exports; a token left here ships inside your web build.
@export var developer_debug_token: String = ""
@export var max_reconnect_attempts: int = 3
@export var reconnect_delay_seconds: float = 0.5
@export var health_check_interval_seconds: float = 2.0
@export var command_timeout_seconds: float = 4.0

## Plugin log lines in the console. Off by default. Message and response bodies are never
## logged, on or off: they can carry the player's email, name and saved data.
@export var logs_enabled: bool = false

## Built-in live score reporting (score_update). Tracking starts when level_begin is acknowledged;
## call Luxodd.report_score(level, score) whenever the score changes. The final score goes out
## right before level_end, so the last score_update always equals the level_end score.
@export var built_in_score_reporting: bool = true
@export var score_update_interval_seconds: float = 2.0

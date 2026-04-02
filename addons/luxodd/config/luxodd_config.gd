@tool
class_name LuxoddConfig
extends Resource

## Configuration resource for the Luxodd plugin.
## Edit this in the Godot inspector or via the editor plugin menu.

@export var server_address: String = "wss://game-server.luxodd.com"
@export var developer_debug_token: String = ""
@export var max_reconnect_attempts: int = 3
@export var reconnect_delay_seconds: float = 0.5
@export var health_check_interval_seconds: float = 2.0
@export var command_timeout_seconds: float = 4.0

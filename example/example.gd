extends Control

## Minimal example showing how to use the Luxodd plugin.
## Connect signals in _ready(), call methods via the Luxodd autoload.

@onready var _status_label: Label = %StatusLabel
@onready var _log_label: RichTextLabel = %LogLabel


func _ready() -> void:
	# Connection signals
	Luxodd.connected.connect(_on_connected)
	Luxodd.disconnected.connect(func(): _log("Disconnected"))
	Luxodd.connection_failed.connect(func(err: String): _log("Connection failed: %s" % err))
	Luxodd.reconnecting.connect(func(a: int, m: int): _log("Reconnecting %d/%d..." % [a, m]))

	# Host bridge signals
	Luxodd.host_action_received.connect(func(action: String): _log("Host action: %s" % action))

	# Response signals
	Luxodd.profile_received.connect(func(p: Dictionary): _log("Profile: %s" % str(p)))
	Luxodd.balance_received.connect(func(b: Dictionary): _log("Balance: %s" % str(b)))
	Luxodd.leaderboard_received.connect(func(d: Dictionary): _log("Leaderboard: %s" % str(d)))
	Luxodd.level_begin_ok.connect(func(): _log("Level begin OK"))
	Luxodd.level_end_ok.connect(func(): _log("Level end OK"))
	Luxodd.session_info_received.connect(func(i: Dictionary): _log("Session: %s" % str(i)))
	Luxodd.command_error.connect(func(cmd: String, code: int, msg: String):
		_log("[ERROR] %s (%d): %s" % [cmd, code, msg]))

	_status_label.text = "Disconnected"


func _on_connected() -> void:
	_status_label.text = "Connected"
	_log("Connected to Luxodd server")
	Luxodd.notify_game_ready()
	Luxodd.start_health_check()


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_connect_pressed() -> void:
	_log("Connecting...")
	_status_label.text = "Connecting..."
	Luxodd.connect_to_server()


func _on_disconnect_pressed() -> void:
	Luxodd.disconnect_from_server()
	_status_label.text = "Disconnected"


func _on_get_profile_pressed() -> void:
	Luxodd.get_profile()


func _on_get_balance_pressed() -> void:
	Luxodd.get_balance()


func _on_get_leaderboard_pressed() -> void:
	Luxodd.get_leaderboard()


func _on_level_begin_pressed() -> void:
	Luxodd.level_begin(1)


func _on_level_end_pressed() -> void:
	Luxodd.level_end(1, 1000)


func _on_session_info_pressed() -> void:
	Luxodd.get_session_info()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _log(msg: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	_log_label.append_text("[%s] %s\n" % [timestamp, msg])
	print("[LuxoddExample] %s" % msg)

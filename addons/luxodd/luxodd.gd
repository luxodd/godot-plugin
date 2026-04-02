extends Node

## Main Luxodd autoload singleton — the single entry point for game developers.
## All platform communication flows through this node.
##
## Usage:
##   Luxodd.connected.connect(_on_connected)
##   Luxodd.connect_to_server()

# ── Connection ────────────────────────────────────────────────────────────────

signal connected()
signal disconnected()
signal connection_failed(error: String)
signal reconnecting(attempt: int, max_attempts: int)

# ── Host bridge ───────────────────────────────────────────────────────────────

signal host_jwt_received(token: String)
signal host_action_received(action: String)

# ── Command responses ─────────────────────────────────────────────────────────

signal profile_received(profile: Dictionary)
signal balance_received(balance: Dictionary)
signal balance_added()
signal balance_charged()
signal health_check_ok()
signal level_begin_ok()
signal level_end_ok()
signal leaderboard_received(data: Dictionary)
signal user_data_received(data: Variant)
signal user_data_set()
signal session_info_received(info: Dictionary)
signal betting_missions_received(missions: Dictionary)
signal strategic_betting_result_sent()
signal best_score_received(data: Dictionary)
signal recent_games_received(data: Dictionary)
signal command_error(command: String, status_code: int, message: String)

# ── Internal nodes ────────────────────────────────────────────────────────────

var _websocket: LuxoddWebSocket
var _bridge: LuxoddBridge
var _protocol: LuxoddProtocol
var _health_timer: Timer

var _config: LuxoddConfig
var _session_token: String = ""

var is_connected: bool:
	get: return _websocket.is_socket_connected() if _websocket else false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_config = _load_config()

	_websocket = LuxoddWebSocket.new()
	_websocket.name = "_websocket"
	add_child(_websocket)

	_bridge = LuxoddBridge.new()
	_bridge.name = "_bridge"
	add_child(_bridge)

	_protocol = LuxoddProtocol.new()
	_protocol.name = "_protocol"
	add_child(_protocol)

	# Wire up internal signals
	_websocket.configure(_config.max_reconnect_attempts, _config.reconnect_delay_seconds)
	_protocol.setup(_websocket)

	_websocket.ws_connected.connect(_on_ws_connected)
	_websocket.ws_disconnected.connect(_on_ws_disconnected)
	_websocket.ws_error.connect(_on_ws_error)
	_websocket.reconnect_attempt.connect(_on_reconnect_attempt)
	_websocket.reconnect_failed.connect(_on_reconnect_failed)

	_protocol.response_received.connect(_on_response)

	_bridge.jwt_received.connect(_on_bridge_jwt)
	_bridge.action_received.connect(_on_bridge_action)
	_bridge.initialize()

	# Health check timer (created but not started)
	_health_timer = Timer.new()
	_health_timer.name = "_health_timer"
	_health_timer.wait_time = _config.health_check_interval_seconds
	_health_timer.timeout.connect(_on_health_timer)
	add_child(_health_timer)


func _process(_delta: float) -> void:
	if _websocket:
		_websocket.poll()


# ── Connection ────────────────────────────────────────────────────────────────

func connect_to_server() -> void:
	var token := _resolve_token()
	if token.is_empty():
		connection_failed.emit("No authentication token available")
		return

	_session_token = token
	var url := "%s?token=%s" % [_config.server_address, token]
	_websocket.connect_to(url)


func disconnect_from_server() -> void:
	stop_health_check()
	_websocket.disconnect_ws()


# ── Host bridge ───────────────────────────────────────────────────────────────

func notify_game_ready() -> void:
	_bridge.post_game_ready()


func notify_session_end() -> void:
	_bridge.post_session_end()


func send_session_option(action: String) -> void:
	_bridge.post_session_option(action)


# ── User ──────────────────────────────────────────────────────────────────────

func get_profile() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_PROFILE)


func get_balance() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_USER_BALANCE)


func add_balance(amount: int, pin_code: int) -> void:
	var pin_hash := LuxoddPinCodeHasher.hash_with_key(str(pin_code), _session_token)
	_protocol.send_command(
		LuxoddCommandTypes.ADD_BALANCE,
		LuxoddPayloads.amount_payload(amount, pin_hash)
	)


func charge_balance(amount: int, pin_code: int) -> void:
	var pin_hash := LuxoddPinCodeHasher.hash_with_key(str(pin_code), _session_token)
	_protocol.send_command(
		LuxoddCommandTypes.CHARGE_BALANCE,
		LuxoddPayloads.amount_payload(amount, pin_hash)
	)


# ── Gameplay ──────────────────────────────────────────────────────────────────

func level_begin(level: int) -> void:
	_protocol.send_command(
		LuxoddCommandTypes.LEVEL_BEGIN,
		LuxoddPayloads.level_begin_payload(level)
	)


func level_end(
	level: int,
	score: int,
	accuracy: int = 0,
	time_taken: int = 0,
	enemies_killed: int = 0,
	completion_percentage: int = 0,
) -> void:
	_protocol.send_command(
		LuxoddCommandTypes.LEVEL_END,
		LuxoddPayloads.level_end_payload(
			level, score, accuracy, time_taken, enemies_killed, completion_percentage
		)
	)


func get_best_score() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_USER_BEST_SCORE)


func get_recent_games() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_USER_RECENT_GAMES)


func get_leaderboard() -> void:
	_protocol.send_command(LuxoddCommandTypes.LEADERBOARD)


# ── User data storage ────────────────────────────────────────────────────────

func get_user_data() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_USER_DATA)


func set_user_data(data: Variant) -> void:
	_protocol.send_command(
		LuxoddCommandTypes.SET_USER_DATA,
		LuxoddPayloads.user_data_payload(data)
	)


# ── Sessions & betting ───────────────────────────────────────────────────────

func get_session_info() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_GAME_SESSION_INFO)


func get_betting_session_missions() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_BETTING_SESSION_MISSIONS)


func send_strategic_betting_result(results: Array) -> void:
	_protocol.send_command(
		LuxoddCommandTypes.SEND_STRATEGIC_BETTING_RESULT,
		LuxoddPayloads.strategic_betting_result_payload(results)
	)


# ── Health check ──────────────────────────────────────────────────────────────

func start_health_check(interval: float = 0.0) -> void:
	if interval > 0.0:
		_health_timer.wait_time = interval
	_health_timer.start()


func stop_health_check() -> void:
	_health_timer.stop()


# ── Internal handlers ─────────────────────────────────────────────────────────

func _resolve_token() -> String:
	# In HTML5 builds, prefer the JWT from the host page or URL query string
	if OS.has_feature("web"):
		var url_token := _bridge.get_token_from_url()
		if not url_token.is_empty():
			return url_token

	# Fall back to the dev token from config (used in editor/desktop testing)
	return _config.developer_debug_token


func _load_config() -> LuxoddConfig:
	var path := "res://addons/luxodd/config/luxodd_config.tres"
	if ResourceLoader.exists(path):
		return load(path) as LuxoddConfig
	push_warning("[Luxodd] Config not found at %s, using defaults" % path)
	return LuxoddConfig.new()


func _on_ws_connected() -> void:
	connected.emit()


func _on_ws_disconnected(code: int) -> void:
	stop_health_check()
	disconnected.emit()


func _on_ws_error(error: String) -> void:
	connection_failed.emit(error)


func _on_reconnect_attempt(attempt: int, max_attempts: int) -> void:
	reconnecting.emit(attempt, max_attempts)


func _on_reconnect_failed() -> void:
	connection_failed.emit("Reconnection failed after max attempts")


func _on_bridge_jwt(token: String) -> void:
	_session_token = token
	host_jwt_received.emit(token)


func _on_bridge_action(action: String) -> void:
	host_action_received.emit(action)


func _on_health_timer() -> void:
	_protocol.send_command(LuxoddCommandTypes.HEALTH_STATUS_CHECK)


func _on_response(request_type: String, status_code: int, payload: Variant) -> void:
	if status_code != 200:
		command_error.emit(request_type, status_code, str(payload))
		return

	match request_type:
		LuxoddCommandTypes.GET_PROFILE:
			profile_received.emit(payload if payload is Dictionary else {})
		LuxoddCommandTypes.GET_USER_BALANCE:
			balance_received.emit(payload if payload is Dictionary else {})
		LuxoddCommandTypes.ADD_BALANCE:
			balance_added.emit()
		LuxoddCommandTypes.CHARGE_BALANCE:
			balance_charged.emit()
		LuxoddCommandTypes.HEALTH_STATUS_CHECK:
			health_check_ok.emit()
		LuxoddCommandTypes.LEVEL_BEGIN:
			level_begin_ok.emit()
		LuxoddCommandTypes.LEVEL_END:
			level_end_ok.emit()
		LuxoddCommandTypes.LEADERBOARD:
			leaderboard_received.emit(payload if payload is Dictionary else {})
		LuxoddCommandTypes.GET_USER_DATA:
			user_data_received.emit(payload)
		LuxoddCommandTypes.SET_USER_DATA:
			user_data_set.emit()
		LuxoddCommandTypes.GET_GAME_SESSION_INFO:
			session_info_received.emit(payload if payload is Dictionary else {})
		LuxoddCommandTypes.GET_BETTING_SESSION_MISSIONS:
			betting_missions_received.emit(payload if payload is Dictionary else {})
		LuxoddCommandTypes.SEND_STRATEGIC_BETTING_RESULT:
			strategic_betting_result_sent.emit()
		LuxoddCommandTypes.GET_USER_BEST_SCORE:
			best_score_received.emit(payload if payload is Dictionary else {})
		LuxoddCommandTypes.GET_USER_RECENT_GAMES:
			recent_games_received.emit(payload if payload is Dictionary else {})

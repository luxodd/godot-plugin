extends Node

## Main Luxodd autoload singleton — the single entry point for game developers.
## All platform communication flows through this node.
##
## Usage:
##   Luxodd.connected.connect(_on_connected)
##   Luxodd.connect_to_server()
##
## Backward compatibility: every method and signal of 1.0.0 is kept with the same arguments and
## the same frames on the wire. 1.1.0 only adds.

const PLUGIN_VERSION := "1.1.0"

# ── Connection ────────────────────────────────────────────────────────────────

signal connected()
signal disconnected()
signal connection_failed(error: String)
signal reconnecting(attempt: int, max_attempts: int)

# ── Host bridge ───────────────────────────────────────────────────────────────

signal host_jwt_received(token: String)
signal host_action_received(action: String)
## Fast Restart: the game is now on the replacement session. host_action_received("restart")
## follows right after; reset the run in place and send level_begin.
signal session_replaced()
## Fast Restart could not hand over to the replacement session. End the session
## (back_to_system_with_error) rather than wait.
signal fast_restart_failed(status_code: int, reason: String)
## Prepared Fast Restart: get ready, then call send_restart_ready(request_id).
signal restart_prepare_requested(request_id: String)
## The host told the game where it runs. platform: "web", "arcade" or ""; arcade_layout:
## "pawn", "rook" or "". See runtime_platform, is_arcade, is_rook, is_pawn.
signal runtime_context_changed(platform: String, arcade_layout: String)

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

# Added in 1.1.0
## GetMerchantPrizeInfoRequest. prize is the response payload ({} when none is active).
signal merchant_prize_info_received(is_active: bool, prize: Dictionary)
## leaderboard_around_score_request.
signal leaderboard_around_score_received(data: Dictionary)
## GetTournamentInfoRequest. result: {outcome, status_code, tournament_id, dynamic_hardness,
## min_score}; outcome is "active", "inactive", "unavailable", "timed_out" or "malformed".
signal tournament_info_received(result: Dictionary)
## The level_end reply carried prize tickets. The plugin has already posted prize_won to the
## arcade page; this is for display only.
signal prize_won(tickets: Array)
## A score_update was answered. response: {request_id, result, applied, score, level}.
signal score_update_handled(response: Dictionary)
signal score_update_failed(status_code: int, reason: String)

# ── Internal nodes ────────────────────────────────────────────────────────────

var _websocket: LuxoddWebSocket
var _bridge: LuxoddBridge
var _protocol: LuxoddProtocol
var _health_timer: Timer

var _config: LuxoddConfig
var _session_token: String = ""
var _pin_key_token: String = ""

var is_connected: bool:
	get: return _websocket.is_socket_connected() if _websocket else false

# Host session ('luxodd:session'), preferred over URL values when present.
var _host_session_token: String = ""
var _host_session_ws_url: String = ""
var _connect_requested: bool = false
var _endpoint: String = ""

# Runtime context (layout).
var has_host_runtime_context: bool = false
var runtime_platform: String = ""
var arcade_layout: String = ""
var is_web_runtime: bool:
	get: return runtime_platform == "web"
var is_arcade: bool:
	get: return runtime_platform == "arcade"
var is_pawn: bool:
	get: return is_arcade and arcade_layout == "pawn"
var is_rook: bool:
	get: return is_arcade and arcade_layout == "rook"

# Fast Restart.
const FAST_RESTART_HANDOFF_TIMEOUT := 10.0
var _fast_restart_pending: bool = false
var _fast_restart_selected: bool = false
var _fast_restart_deadline: float = 0.0
var _replacement_token: String = ""
var _replacement_ws_url: String = ""
var _replacement_connecting: bool = false
var _health_was_running: bool = false

# Built-in score reporting.
const SCORE_UPDATE_TIMEOUT := 2.0
var _last_level_begin_level: int = 0
var _score_tracking: bool = false
var _score_level: int = 0
var _score_value: int = 0
var _score_next_tick: float = 0.0
var _score_next_request_id: int = 1
var _score_pending_id: int = -1
var _score_pending_deadline: float = 0.0
var _score_final_callback: Callable = Callable()
var _score_final_deadline: float = 0.0
var _score_final_sent: bool = false

# Tournament info.
const TOURNAMENT_TIMEOUT := 10.0
var _tournament_requests: Dictionary = {}  # request_id -> deadline

var _warned_deprecated_balance: bool = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_config = _load_config()
	LuxoddLog.enabled = _config.logs_enabled

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
	_bridge.session_received.connect(_on_bridge_session)
	_bridge.restart_prepare_received.connect(_on_bridge_restart_prepare)
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
	var now := _now()
	_process_score(now)
	_process_tournament_timeouts(now)
	_process_fast_restart_timeout(now)


# ── Connection ────────────────────────────────────────────────────────────────

func connect_to_server() -> void:
	var token := _resolve_token()
	if token.is_empty():
		connection_failed.emit("No authentication token available")
		return

	_connect_requested = true
	_session_token = token
	_endpoint = _resolve_endpoint()
	_open_socket()


func disconnect_from_server() -> void:
	stop_health_check()
	_stop_score_tracking()
	_websocket.disconnect_ws()


## The WebSocket endpoint in use, without the token (for diagnostics; safe to show).
func get_server_endpoint() -> String:
	return _endpoint


# ── Host bridge ───────────────────────────────────────────────────────────────

func notify_game_ready() -> void:
	_bridge.post_game_ready()


func notify_session_end() -> void:
	_bridge.post_session_end()


## Ends the session and returns the player to the arcade, as Unity's BackToSystem().
## Send the final level_end first. Stops the health check and score reporting, so nothing is
## sent after session_end.
func back_to_system() -> void:
	LuxoddLog.info("back_to_system")
	stop_health_check()
	_stop_score_tracking()
	_fast_restart_pending = false
	_bridge.post_session_end()


## As back_to_system(), for a fatal error. The message is logged only when logs are on.
func back_to_system_with_error(message: String = "") -> void:
	LuxoddLog.info("back_to_system_with_error: %s" % message)
	back_to_system()


## 1.0.0 call, unchanged: posts {type: "session_options", action}. Prefer the named calls below.
func send_session_option(action: String) -> void:
	_bridge.post_session_option(action)


func send_session_option_continue() -> void:
	_bridge.post_session_option("continue")


## Legacy restart: the arcade reloads the game page on Restart.
func send_session_option_restart() -> void:
	_bridge.post_session_option("restart")


func send_session_option_end() -> void:
	_bridge.post_session_option("end")


## Continue and legacy Restart in one popup.
func send_session_option_both() -> void:
	_bridge.post_session_option("both")


## Fast Restart (Unity 1.2.0): the arcade keeps the game loaded on Restart and hands it the
## replacement session. The plugin switches over, then emits session_replaced and
## host_action_received("restart"); reset the run in place and send level_begin. Continue and
## End arrive as host_action_received as usual. On failure fast_restart_failed fires.
## include_continue: one popup with Continue as well. prepared: the arcade first sends
## restart_prepare_requested(request_id); answer with send_restart_ready(request_id).
func send_session_option_fast_restart(include_continue: bool = false, prepared: bool = false) -> void:
	if _fast_restart_pending and (_fast_restart_selected or _replacement_connecting):
		fast_restart_failed.emit(409, "A Fast Restart session handoff is already in progress.")
		return
	_fast_restart_pending = true
	_fast_restart_selected = false
	_fast_restart_deadline = 0.0
	_replacement_token = ""
	_replacement_ws_url = ""
	_bridge.post_fast_restart_session_option(include_continue, prepared)


func send_restart_ready(request_id: String) -> void:
	_bridge.post_restart_ready(request_id)


# ── User ──────────────────────────────────────────────────────────────────────

func get_profile() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_PROFILE)


func get_balance() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_USER_BALANCE)


## @deprecated Games must not change player credit: the Luxodd platform manages credits and
## payment (integration check CR-1). Kept only so games built on 1.0.0 keep working.
func add_balance(amount: int, pin_code: int) -> void:
	_warn_deprecated_balance()
	var pin_hash := LuxoddPinCodeHasher.hash_with_key(str(pin_code), _pin_key())
	_protocol.send_command(
		LuxoddCommandTypes.ADD_BALANCE,
		LuxoddPayloads.amount_payload(amount, pin_hash)
	)


## @deprecated Games must not change player credit: the Luxodd platform manages credits and
## payment (integration check CR-1). Kept only so games built on 1.0.0 keep working.
func charge_balance(amount: int, pin_code: int) -> void:
	_warn_deprecated_balance()
	var pin_hash := LuxoddPinCodeHasher.hash_with_key(str(pin_code), _pin_key())
	_protocol.send_command(
		LuxoddCommandTypes.CHARGE_BALANCE,
		LuxoddPayloads.amount_payload(amount, pin_hash)
	)


# ── Gameplay ──────────────────────────────────────────────────────────────────

func level_begin(level: int) -> void:
	_last_level_begin_level = level
	_protocol.send_command(
		LuxoddCommandTypes.LEVEL_BEGIN,
		LuxoddPayloads.level_begin_payload(level)
	)


## Sends the run's result. While score reporting is tracking the run, the final score goes out
## as an immediate score_update first (at most 2 s), so the last score_update equals this score.
func level_end(
	level: int,
	score: int,
	accuracy: int = 0,
	time_taken: int = 0,
	enemies_killed: int = 0,
	completion_percentage: int = 0,
) -> void:
	var send_level_end := func() -> void:
		_protocol.send_command(
			LuxoddCommandTypes.LEVEL_END,
			LuxoddPayloads.level_end_payload(
				level, score, accuracy, time_taken, enemies_killed, completion_percentage
			)
		)

	if _score_final_callback.is_valid():
		# A previous level_end is still waiting for its final score_update: send it now, in order.
		_stop_score_tracking()
	if not _score_tracking or not is_connected or level < 0 or score < 0:
		_stop_score_tracking()
		send_level_end.call()
		return

	_score_level = level
	_score_value = score
	_score_final_callback = send_level_end
	_score_final_deadline = _now() + SCORE_UPDATE_TIMEOUT
	_score_final_sent = false
	if _score_pending_id < 0:
		_score_final_sent = true
		_send_score_snapshot()


## Reports the run's current score. The plugin sends it as score_update every
## score_update_interval_seconds while a level runs (cabinet live leaderboard, prize progress)
## and sends the last value right before level_end. Call it whenever the score changes.
func report_score(level: int, score: int) -> void:
	if not _score_tracking or level < 0 or score < 0:
		return
	_score_level = level
	_score_value = score


func is_score_tracking() -> bool:
	return _score_tracking


func get_best_score() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_USER_BEST_SCORE)


func get_recent_games() -> void:
	_protocol.send_command(LuxoddCommandTypes.GET_USER_RECENT_GAMES)


func get_leaderboard() -> void:
	_protocol.send_command(LuxoddCommandTypes.LEADERBOARD)


## Score-centered leaderboard: the entries around target_score.
func get_leaderboard_around_score(target_score: int) -> void:
	_protocol.send_request(
		LuxoddCommandTypes.LEADERBOARD_AROUND_SCORE,
		LuxoddPayloads.leaderboard_around_score_payload(target_score),
		"", "1"
	)


# ── Prizes and tournaments ───────────────────────────────────────────────────

## Merchant prize for this session. Ask after connecting and before gameplay starts (PZ-1).
func get_merchant_prize_info() -> void:
	_protocol.send_request(LuxoddCommandTypes.GET_MERCHANT_PRIZE_INFO, null)


## Tournament for the current session, without Merchant Rewards. Answers once with
## tournament_info_received, within 10 s.
func get_tournament_info() -> void:
	if not is_connected:
		tournament_info_received.emit(_tournament_result("unavailable", 0))
		return
	var request_id := _uuid4()
	_tournament_requests[request_id] = _now() + TOURNAMENT_TIMEOUT
	_protocol.send_request(
		LuxoddCommandTypes.GET_TOURNAMENT_INFO,
		LuxoddPayloads.tournament_info_payload(request_id),
		"", "1"
	)


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


# ── Internal: connection ─────────────────────────────────────────────────────

func _open_socket() -> void:
	# Connect to /ws endpoint with token as query param
	# (Godot Web doesn't support custom WS headers)
	LuxoddLog.info("connecting to %s" % _endpoint)
	_websocket.connect_to("%s?token=%s" % [_endpoint, _session_token])


func _resolve_endpoint() -> String:
	if not _host_session_ws_url.is_empty():
		return _host_session_ws_url
	# In production HTML5: the ws or wsHost URL parameter set by the Luxodd embed page
	if OS.has_feature("web"):
		var url_endpoint := _bridge.get_ws_endpoint_from_url()
		if not url_endpoint.is_empty():
			return url_endpoint

	# Fall back to config (used in editor/desktop testing)
	return "%s/ws" % _config.server_address


## Kept for 1.0.0 callers: the server without the /ws path.
func _resolve_server_url() -> String:
	return _resolve_endpoint().trim_suffix("/ws")


func _resolve_token() -> String:
	# The arcade page's current session wins: a URL token can be stale after a relaunch.
	if not _host_session_token.is_empty():
		return _host_session_token
	# In HTML5 builds, prefer the JWT from the host page or URL query string
	if OS.has_feature("web"):
		var url_token := _bridge.get_token_from_url()
		if not url_token.is_empty():
			return url_token

	# Fall back to the dev token from config (used in editor/desktop testing)
	return _config.developer_debug_token


func _load_config() -> LuxoddConfig:
	# In web builds, skip dev config — only use addon default or production config
	var is_web := OS.has_feature("web")
	var paths: Array[String] = []
	if is_web:
		paths = ["res://luxodd_config.tres", "res://addons/luxodd/config/luxodd_config.tres"]
	else:
		paths = ["res://luxodd_config.tres", "res://luxodd_dev_config.tres", "res://addons/luxodd/config/luxodd_config.tres"]

	for path in paths:
		if ResourceLoader.exists(path):
			return load(path) as LuxoddConfig
	LuxoddLog.warn("No config found, using defaults")
	return LuxoddConfig.new()


func _pin_key() -> String:
	return _pin_key_token if not _pin_key_token.is_empty() else _session_token


func _warn_deprecated_balance() -> void:
	if _warned_deprecated_balance:
		return
	_warned_deprecated_balance = true
	LuxoddLog.warn("add_balance and charge_balance are deprecated: games must not change player credit.")


func _on_ws_connected() -> void:
	if _replacement_connecting:
		_finish_session_replacement()
		return
	connected.emit()


func _on_ws_disconnected(_code: int) -> void:
	stop_health_check()
	disconnected.emit()


func _on_ws_error(error: String) -> void:
	if _replacement_connecting:
		_fail_fast_restart(503, "The replacement session could not connect.")
		return
	connection_failed.emit(error)


func _on_reconnect_attempt(attempt: int, max_attempts: int) -> void:
	reconnecting.emit(attempt, max_attempts)


func _on_reconnect_failed() -> void:
	connection_failed.emit("Reconnection failed after max attempts")


# ── Internal: host session, Fast Restart, runtime context ────────────────────

func _on_bridge_jwt(token: String) -> void:
	# 1.0.0 stored it for PIN hashing; it still does. It never replaces the connected session.
	_pin_key_token = token
	host_jwt_received.emit(token)


func _on_bridge_action(action: String) -> void:
	if _fast_restart_pending and not _replacement_connecting:
		if action == "restart":
			_fast_restart_selected = true
			_fast_restart_deadline = _now() + FAST_RESTART_HANDOFF_TIMEOUT
			# The page sends token B in the same message as the action (and, same-origin,
			# in a luxodd:session event just before it).
			if _replacement_token.is_empty() and not _pin_key_token.is_empty() \
					and _pin_key_token != _session_token:
				_replacement_token = _pin_key_token
			if not _replacement_token.is_empty():
				_begin_session_replacement()
			return
		_clear_fast_restart()
	elif _replacement_connecting:
		# Already switching sessions; the result is reported when it completes.
		return
	host_action_received.emit(action)


func _on_bridge_restart_prepare(request_id: String) -> void:
	restart_prepare_requested.emit(request_id)


func _on_bridge_session(token: String, ws_url: String, runtime: Dictionary) -> void:
	_apply_runtime_context(runtime)
	if token.is_empty():
		return
	if token == _session_token or token == _replacement_token:
		# The page repeats the event every 2 s until it sees a socket it recognises; a Godot
		# game never shows it one, so repeats of the current session are expected and ignored.
		return

	if _fast_restart_pending:
		_replacement_token = token
		_replacement_ws_url = ws_url
		if _fast_restart_selected and not _replacement_connecting:
			_begin_session_replacement()
		return

	_host_session_token = token
	if not ws_url.is_empty():
		_host_session_ws_url = ws_url

	# Stale-token rescue: the game asked to connect, and its socket is closed for good.
	if _connect_requested and _websocket.is_idle():
		LuxoddLog.info("adopting the arcade page's current session after a closed socket")
		connect_to_server()


func _begin_session_replacement() -> void:
	LuxoddLog.info("Fast Restart: switching to the replacement session")
	_replacement_connecting = true
	_health_was_running = not _health_timer.is_stopped()
	stop_health_check()
	_stop_score_tracking()
	_fail_tournament_requests()
	_score_next_request_id = 1
	_websocket.disconnect_ws()
	_websocket.clear_queue()
	_session_token = _replacement_token
	_host_session_token = _replacement_token
	if not _replacement_ws_url.is_empty():
		_host_session_ws_url = _replacement_ws_url
	_endpoint = _resolve_endpoint()
	_fast_restart_deadline = _now() + FAST_RESTART_HANDOFF_TIMEOUT
	_open_socket()


func _finish_session_replacement() -> void:
	_clear_fast_restart()
	if _health_was_running:
		_health_timer.start()
	session_replaced.emit()
	host_action_received.emit("restart")


func _fail_fast_restart(status_code: int, reason: String) -> void:
	_clear_fast_restart()
	fast_restart_failed.emit(status_code, reason)


func _clear_fast_restart() -> void:
	_fast_restart_pending = false
	_fast_restart_selected = false
	_fast_restart_deadline = 0.0
	_replacement_token = ""
	_replacement_ws_url = ""
	_replacement_connecting = false


func _process_fast_restart_timeout(now: float) -> void:
	if _fast_restart_deadline > 0.0 and now >= _fast_restart_deadline:
		var reason := "Timed out waiting for the replacement session." if not _replacement_connecting \
			else "Timed out connecting the replacement session."
		_fail_fast_restart(408, reason)


func _apply_runtime_context(runtime: Dictionary) -> void:
	# Same mapping as Unity's LuxoddRuntimeContext.ApplyHostRuntimeContext.
	var has_runtime := not runtime.is_empty()
	var platform := ""
	var layout := ""
	if has_runtime:
		var p := str(runtime.get("platform", ""))
		if p == "web" or p == "arcade":
			platform = p
		if platform == "arcade":
			var l := str(runtime.get("arcadeLayout", ""))
			if l == "pawn" or l == "rook":
				layout = l
	if has_runtime == has_host_runtime_context and platform == runtime_platform and layout == arcade_layout:
		return
	has_host_runtime_context = has_runtime
	runtime_platform = platform
	arcade_layout = layout
	runtime_context_changed.emit(platform, layout)


# ── Internal: score reporting ────────────────────────────────────────────────

func _start_score_tracking(level: int) -> void:
	if not _config.built_in_score_reporting or _score_tracking or level < 0:
		return
	_score_tracking = true
	_score_level = level
	_score_value = 0
	_score_next_tick = _now() + maxf(0.01, _config.score_update_interval_seconds)


func _stop_score_tracking() -> void:
	_score_tracking = false
	_score_pending_id = -1
	var final_callback := _score_final_callback
	_score_final_callback = Callable()
	_score_final_sent = false
	if final_callback.is_valid():
		final_callback.call()


func _send_score_snapshot() -> void:
	var request_id := _score_next_request_id
	_score_next_request_id += 1
	_score_pending_id = request_id
	_score_pending_deadline = _now() + SCORE_UPDATE_TIMEOUT
	_protocol.send_request(
		LuxoddCommandTypes.SCORE_UPDATE,
		LuxoddPayloads.score_update_payload(request_id, _score_level, _score_value),
		"1.0"
	)


func _process_score(now: float) -> void:
	if not _score_tracking:
		return
	if _score_final_callback.is_valid() and now >= _score_final_deadline:
		_score_pending_id = -1
		_stop_score_tracking()  # sends level_end
		return
	if _score_pending_id >= 0 and now >= _score_pending_deadline:
		_score_pending_id = -1
		score_update_failed.emit(408, "Score update response timed out.")
		_after_score_response()
		return
	if _score_final_callback.is_valid() or now < _score_next_tick:
		return
	# Advance from now: missed ticks are dropped, never replayed.
	_score_next_tick = now + maxf(0.01, _config.score_update_interval_seconds)
	if _score_pending_id < 0 and is_connected:
		_send_score_snapshot()


func _on_score_update_response(status_code: int, payload: Variant) -> void:
	if _score_pending_id < 0 or not payload is Dictionary:
		return
	var response: Dictionary = payload
	if int(response.get("request_id", -1)) != _score_pending_id:
		LuxoddLog.warn("Ignoring a score_update response with an unmatched request_id.")
		return
	_score_pending_id = -1
	if status_code == 200:
		var result := str(response.get("result", ""))
		score_update_handled.emit(response)
		if (result == "finalized" or result == "session_ended") and not _score_final_callback.is_valid():
			_score_tracking = false
	else:
		score_update_failed.emit(status_code, str(response.get("error", "")))
	_after_score_response()


func _after_score_response() -> void:
	if not _score_final_callback.is_valid():
		return
	if not _score_final_sent and _now() < _score_final_deadline and is_connected:
		# A regular update was in flight when level_end was asked for; now send the final one.
		_score_final_sent = true
		_send_score_snapshot()
		return
	_stop_score_tracking()  # sends level_end


# ── Internal: tournaments ────────────────────────────────────────────────────

func _tournament_result(outcome: String, status_code: int, info: Dictionary = {}) -> Dictionary:
	var result := {"outcome": outcome, "status_code": status_code}
	result.merge(info)
	return result


func _process_tournament_timeouts(now: float) -> void:
	if _tournament_requests.is_empty():
		return
	for request_id in _tournament_requests.keys():
		if _tournament_requests[request_id] <= now:
			_tournament_requests.erase(request_id)
			tournament_info_received.emit(_tournament_result("timed_out", 408))


func _fail_tournament_requests() -> void:
	for request_id in _tournament_requests.keys():
		tournament_info_received.emit(_tournament_result("unavailable", 0))
	_tournament_requests.clear()


## Same checks as Unity's WebSocketService.HandleTournamentInfoResponse.
func _on_tournament_info_response(envelope: Dictionary) -> void:
	var request_id: Variant = envelope.get("request_id")
	if not request_id is String or not _tournament_requests.has(request_id):
		return
	_tournament_requests.erase(request_id)
	var status: Variant = envelope.get("status")
	var active: Variant = envelope.get("is_active")
	var ts: Variant = envelope.get("ts")
	if str(envelope.get("msgver", "")) != "1" or not ts is String or str(ts).strip_edges().is_empty() \
			or not (status is int or status is float) or not active is bool or not envelope.has("payload"):
		tournament_info_received.emit(_tournament_result("malformed", 0))
		return
	var code := int(status)
	var payload: Variant = envelope.get("payload")
	if code != 200:
		var outcome := "malformed" if (active or payload != null) else "unavailable"
		tournament_info_received.emit(_tournament_result(outcome, code))
		return
	if not active:
		tournament_info_received.emit(_tournament_result("inactive" if payload == null else "malformed", 200))
		return
	if not payload is Dictionary:
		tournament_info_received.emit(_tournament_result("malformed", 200))
		return
	var tid: Variant = payload.get("tournament_id")
	var hardness: Variant = payload.get("dynamic_hardness")
	var minimum: Variant = payload.get("min_score")
	if not tid is String or str(tid).is_empty() or not _is_whole_number(hardness) or not _is_whole_number(minimum):
		tournament_info_received.emit(_tournament_result("malformed", 200))
		return
	var h := int(hardness)
	var m := int(minimum)
	if h < 10 or h > 100 or h % 10 != 0 or m < 0:
		tournament_info_received.emit(_tournament_result("malformed", 200))
		return
	tournament_info_received.emit(_tournament_result("active", 200,
		{"tournament_id": tid, "dynamic_hardness": h, "min_score": m}))


static func _is_whole_number(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_equal_approx(value, roundf(value))


# ── Internal: responses ──────────────────────────────────────────────────────

func _on_health_timer() -> void:
	_protocol.send_command(LuxoddCommandTypes.HEALTH_STATUS_CHECK)


func _on_response(request_type: String, status_code: int, payload: Variant, envelope: Dictionary = {}) -> void:
	# Correlated responses are routed by request_id before the status check.
	if request_type == LuxoddCommandTypes.SCORE_UPDATE:
		_on_score_update_response(status_code, payload)
		return
	if request_type == LuxoddCommandTypes.GET_TOURNAMENT_INFO:
		_on_tournament_info_response(envelope)
		return

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
			# After the game's own handler, as in Unity.
			_start_score_tracking(_last_level_begin_level)
		LuxoddCommandTypes.LEVEL_END:
			_forward_prize_tickets(payload)
			level_end_ok.emit()
		LuxoddCommandTypes.LEADERBOARD:
			leaderboard_received.emit(payload if payload is Dictionary else {})
		LuxoddCommandTypes.LEADERBOARD_AROUND_SCORE:
			leaderboard_around_score_received.emit(payload if payload is Dictionary else {})
		LuxoddCommandTypes.GET_MERCHANT_PRIZE_INFO:
			merchant_prize_info_received.emit(
				envelope.get("is_active", false) == true, payload if payload is Dictionary else {}
			)
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


## Tickets come only from the server's level_end reply (PZ-5); the plugin forwards them to the
## arcade page as prize_won, as Unity does.
func _forward_prize_tickets(payload: Variant) -> void:
	if not payload is Dictionary:
		return
	var tickets: Variant = payload.get("prize_tickets")
	if tickets is Array and not tickets.is_empty():
		LuxoddLog.info("prize_won: %d tickets" % tickets.size())
		_bridge.post_prize_won(tickets)
		prize_won.emit(tickets)


# ── Internal: helpers ────────────────────────────────────────────────────────

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _uuid4() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]

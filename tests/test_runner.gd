extends Node

## Automated test runner for the Luxodd plugin.
## Connects to a mock WebSocket server, exercises every API method,
## validates responses, and exits with code 0 (pass) or 1 (fail).
##
## Run headless: godot --headless --path . -s tests/test_runner.gd

const TEST_CONFIG_PATH := "res://tests/test_config.tres"

var _tests_passed: int = 0
var _tests_failed: int = 0
var _tests_total: int = 0
var _current_test: String = ""
var _timeout_timer: Timer


func _ready() -> void:
	print("\n========================================")
	print("  Luxodd Godot Plugin — Automated Tests")
	print("========================================\n")

	# Override the config to point at mock server
	var config: LuxoddConfig = load(TEST_CONFIG_PATH)
	if config == null:
		_fail("Could not load test config at %s" % TEST_CONFIG_PATH)
		_finish()
		return

	# Inject test config into the autoload
	Luxodd._config = config
	LuxoddLog.enabled = config.logs_enabled
	Luxodd._websocket.configure(config.max_reconnect_attempts, config.reconnect_delay_seconds)

	# Global timeout — if tests hang, bail after 60 seconds
	_timeout_timer = Timer.new()
	_timeout_timer.wait_time = 60.0
	_timeout_timer.one_shot = true
	_timeout_timer.timeout.connect(_on_global_timeout)
	add_child(_timeout_timer)
	_timeout_timer.start()

	# Run test sequence
	await _run_tests()
	_finish()


func _run_tests() -> void:
	# ── Test 1: Connection ────────────────────────────────────────────────
	_begin("connect_to_server")
	Luxodd.connect_to_server()
	var result = await _wait_for_signal(Luxodd.connected, 5.0)
	_assert(result != null, "Should connect to mock server")

	if result == null:
		print("[SKIP] Skipping remaining tests — no connection")
		return

	# ── Test 2: Get Profile ───────────────────────────────────────────────
	_begin("get_profile")
	Luxodd.get_profile()
	var profile = await _wait_for_signal(Luxodd.profile_received, 3.0)
	_assert(profile != null, "Should receive profile response")
	if profile is Dictionary:
		_assert(profile.get("username") == "test_player", "Username should be 'test_player', got '%s'" % profile.get("username", ""))
		_assert(profile.has("email"), "Profile should have email field")

	# ── Test 3: Get Balance ───────────────────────────────────────────────
	_begin("get_balance")
	Luxodd.get_balance()
	var balance = await _wait_for_signal(Luxodd.balance_received, 3.0)
	_assert(balance != null, "Should receive balance response")
	if balance is Dictionary:
		_assert(balance.get("balance") == 1500, "Balance should be 1500, got %s" % str(balance.get("balance", "")))

	# ── Test 4: Charge Balance ────────────────────────────────────────────
	_begin("charge_balance")
	Luxodd.charge_balance(500, 1234)
	var charged = await _wait_for_signal(Luxodd.balance_charged, 3.0)
	_assert(charged != null, "Should receive charge confirmation")

	# ── Test 5: Add Balance ───────────────────────────────────────────────
	_begin("add_balance")
	Luxodd.add_balance(500, 1234)
	var added = await _wait_for_signal(Luxodd.balance_added, 3.0)
	_assert(added != null, "Should receive add balance confirmation")

	# ── Test 6: Level Begin ───────────────────────────────────────────────
	_begin("level_begin")
	Luxodd.level_begin(1)
	var lb = await _wait_for_signal(Luxodd.level_begin_ok, 3.0)
	_assert(lb != null, "Should receive level_begin OK")

	# ── Test 7: Level End ─────────────────────────────────────────────────
	_begin("level_end")
	Luxodd.level_end(1, 5000, 85, 120, 10, 95)
	var le = await _wait_for_signal(Luxodd.level_end_ok, 3.0)
	_assert(le != null, "Should receive level_end OK")

	# ── Test 7b: game_end (level_end is now a legacy alias) ────────────────
	_begin("game_end")
	Luxodd.level_begin(1)
	await _wait_for_signal(Luxodd.level_begin_ok, 3.0)
	Luxodd.game_end(4321)
	var ge = await _wait_for_signal(Luxodd.game_end_ok, 4.0)
	_assert(ge != null, "game_end emits game_end_ok")
	var ge_frame := _last_frame("level_end")
	_assert(ge_frame.get("payload", {}).get("score") == 4321,
		"game_end sends the level_end frame with the score")
	_assert(ge_frame.get("payload", {}).get("level") == 1, "game_end defaults to level 1")

	# ── Test 8: Leaderboard ───────────────────────────────────────────────
	_begin("get_leaderboard")
	Luxodd.get_leaderboard()
	var leaderboard = await _wait_for_signal(Luxodd.leaderboard_received, 3.0)
	_assert(leaderboard != null, "Should receive leaderboard response")
	if leaderboard is Dictionary:
		_assert(leaderboard.has("leaderboard"), "Response should have 'leaderboard' array")

	# ── Test 9: Get Best Score ────────────────────────────────────────────
	_begin("get_best_score")
	Luxodd.get_best_score()
	var best = await _wait_for_signal(Luxodd.best_score_received, 3.0)
	_assert(best != null, "Should receive best score response")

	# ── Test 10: Get Recent Games ─────────────────────────────────────────
	_begin("get_recent_games")
	Luxodd.get_recent_games()
	var recent = await _wait_for_signal(Luxodd.recent_games_received, 3.0)
	_assert(recent != null, "Should receive recent games response")

	# ── Test 11: Get User Data ────────────────────────────────────────────
	_begin("get_user_data")
	Luxodd.get_user_data()
	var udata = await _wait_for_signal(Luxodd.user_data_received, 3.0)
	_assert(udata != null, "Should receive user data response")

	# ── Test 12: Set User Data ────────────────────────────────────────────
	_begin("set_user_data")
	Luxodd.set_user_data({"my_key": "my_value"})
	var uset = await _wait_for_signal(Luxodd.user_data_set, 3.0)
	_assert(uset != null, "Should receive set user data confirmation")

	# ── Test 13: Get Session Info ─────────────────────────────────────────
	_begin("get_session_info")
	Luxodd.get_session_info()
	var sinfo = await _wait_for_signal(Luxodd.session_info_received, 3.0)
	_assert(sinfo != null, "Should receive session info")
	if sinfo is Dictionary:
		_assert(sinfo.get("session_type") == "Pay2Play", "Session type should be 'Pay2Play'")

	# ── Test 14: Get Betting Missions ─────────────────────────────────────
	_begin("get_betting_session_missions")
	Luxodd.get_betting_session_missions()
	var missions = await _wait_for_signal(Luxodd.betting_missions_received, 3.0)
	_assert(missions != null, "Should receive betting missions")

	# ── Test 15: Send Strategic Betting Result ────────────────────────────
	_begin("send_strategic_betting_result")
	Luxodd.send_strategic_betting_result([{"mission_id": "m1", "outcome": "win"}])
	var betting = await _wait_for_signal(Luxodd.strategic_betting_result_sent, 3.0)
	_assert(betting != null, "Should receive betting result confirmation")

	# ── Test 16: Health Check ─────────────────────────────────────────────
	_begin("health_check")
	Luxodd.start_health_check(0.5)
	var health = await _wait_for_signal(Luxodd.health_check_ok, 3.0)
	_assert(health != null, "Should receive health check OK")
	Luxodd.stop_health_check()

	# ── 1.1.0 tests ──────────────────────────────────────────────────────
	await _run_parity_tests()

	# ── Test 17: Disconnect ───────────────────────────────────────────────
	_begin("disconnect")
	Luxodd.disconnect_from_server()
	# Brief wait for disconnect to process
	await get_tree().create_timer(0.5).timeout
	_assert(not Luxodd.is_connected, "Should be disconnected")

	# ── Test 18: Pin Code Hasher ──────────────────────────────────────────
	_begin("pin_code_hasher")
	var hash1 := LuxoddPinCodeHasher.hash_with_key("1234", "secret_key")
	var hash2 := LuxoddPinCodeHasher.hash_with_key("1234", "secret_key")
	_assert(hash1 == hash2, "Same input should produce same hash")
	_assert(hash1.length() > 0, "Hash should not be empty")
	var hash3 := LuxoddPinCodeHasher.hash_with_key("1234", "different_key")
	_assert(hash1 != hash3, "Different keys should produce different hashes")

	# ── Test 19: Payload Builders ─────────────────────────────────────────
	_begin("payload_builders")
	var lp := LuxoddPayloads.level_end_payload(1, 500)
	_assert(lp.get("level") == 1, "level_end_payload should have level=1")
	_assert(lp.get("score") == 500, "level_end_payload should have score=500")
	_assert(not lp.has("accuracy"), "level_end_payload should omit zero optional fields")

	var lp2 := LuxoddPayloads.level_end_payload(2, 1000, 90)
	_assert(lp2.has("accuracy"), "level_end_payload should include non-zero accuracy")
	_assert(lp2.get("accuracy") == 90, "accuracy should be 90")

	var ap := LuxoddPayloads.amount_payload(100, "hash123")
	_assert(ap.get("amount") == 100, "amount_payload should have amount=100")
	_assert(ap.get("pin") == "hash123", "amount_payload should have pin hash")

	# ── Test 20: Command Types Constants ──────────────────────────────────
	_begin("command_types")
	_assert(LuxoddCommandTypes.GET_PROFILE == "GetProfileRequest", "GET_PROFILE constant")
	_assert(LuxoddCommandTypes.LEVEL_BEGIN == "level_begin", "LEVEL_BEGIN constant")
	_assert(LuxoddCommandTypes.RESPONSE_TO_REQUEST.has("GetProfileResponse"), "RESPONSE_TO_REQUEST should map GetProfileResponse")
	_assert(
		LuxoddCommandTypes.RESPONSE_TO_REQUEST["GetProfileResponse"] == "GetProfileRequest",
		"GetProfileResponse should map to GetProfileRequest"
	)


# ── 1.1.0: Unity parity ──────────────────────────────────────────────────────

func _run_parity_tests() -> void:
	_begin("merchant_prize_info")
	Luxodd.get_merchant_prize_info()
	var prize = await _wait_for_signal(Luxodd.merchant_prize_info_received, 3.0)
	_assert(prize == true, "is_active should be true")
	var prize_frame := _last_frame("GetMerchantPrizeInfoRequest")
	_assert(prize_frame.has("payload") and prize_frame["payload"] == null and not prize_frame.has("version"),
		"GetMerchantPrizeInfoRequest wire format matches Unity: {type, payload: null}")

	_begin("leaderboard_around_score")
	Luxodd.get_leaderboard_around_score(1000)
	var around = await _wait_for_signal(Luxodd.leaderboard_around_score_received, 3.0)
	_assert(around is Dictionary and around.has("leaderboard"), "Should receive leaderboard around score")
	var around_frame := _last_frame("leaderboard_around_score_request")
	_assert(around_frame.get("msgver") == "1" and around_frame.get("payload", {}).get("target_score") == 1000,
		"leaderboard_around_score_request carries msgver 1 and target_score")

	_begin("tournament_info")
	Luxodd.get_tournament_info()
	var tournament = await _wait_for_signal(Luxodd.tournament_info_received, 3.0)
	_assert(tournament is Dictionary and tournament.get("outcome") == "active", "Tournament outcome should be active")
	if tournament is Dictionary:
		_assert(tournament.get("dynamic_hardness") == 40 and tournament.get("min_score") == 250,
			"Tournament hardness 40, min_score 250")
	var t_frame := _last_frame("GetTournamentInfoRequest")
	_assert(t_frame.get("msgver") == "1" and str(t_frame.get("payload", {}).get("request_id", "")).length() == 36,
		"GetTournamentInfoRequest carries msgver 1 and a UUID request_id")

	_begin("tournament_validation")
	var bad_id := "00000000-0000-4000-8000-000000000001"
	Luxodd._tournament_requests[bad_id] = Luxodd._now() + 5.0
	var got_bad: Array = []
	var bad_cb := func(r): got_bad.append(r)
	Luxodd.tournament_info_received.connect(bad_cb, CONNECT_ONE_SHOT)
	Luxodd._on_tournament_info_response({"type": "GetTournamentInfoResponse", "msgver": "1", "request_id": bad_id,
		"ts": "2026-11-17T00:00:00Z", "status": 200, "is_active": true,
		"payload": {"tournament_id": "t", "dynamic_hardness": 35, "min_score": 0}})
	_assert(got_bad.size() == 1 and got_bad[0].get("outcome") == "malformed", "Hardness 35 is rejected as malformed")

	_begin("score_update_builtin")
	Luxodd.level_begin(2)
	await _wait_for_signal(Luxodd.level_begin_ok, 3.0)
	_assert(Luxodd.is_score_tracking(), "Tracking starts on the level_begin ack")
	for i in range(8):
		Luxodd.report_score(2, (i + 1) * 100)
		await get_tree().create_timer(0.15).timeout
	var handled = await _wait_for_signal(Luxodd.score_update_handled, 2.0)
	_assert(handled is Dictionary and handled.get("result") == "applied", "score_update answered with applied")
	Luxodd.level_end(2, 1234)
	await _wait_for_signal(Luxodd.level_end_ok, 4.0)
	_assert(not Luxodd.is_score_tracking(), "Tracking stops at level_end")
	var frames := _frames()
	var last_su := -1
	var le_index := -1
	for i in range(frames.size()):
		var t: String = frames[i]["request"].get("type", "")
		if t == "score_update":
			last_su = i
		elif t == "level_end" and frames[i]["request"].get("payload", {}).get("score") == 1234:
			le_index = i
	_assert(last_su >= 0 and le_index > last_su, "A score_update precedes level_end")
	if last_su >= 0:
		var su: Dictionary = frames[last_su]["request"]
		_assert(su.get("version") == "1.0" and su["payload"].get("score") == 1234 and su["payload"].get("level") == 2,
			"The last score_update equals the level_end score (TP-2), version 1.0")
		_assert(su["payload"].has("request_id"), "score_update carries request_id")
	var count := 0
	for f in frames:
		if f["request"].get("type") == "score_update":
			count += 1
	_assert(count >= 3, "Periodic score_update frames were sent during play (%d)" % count)

	_begin("score_update_disabled")
	Luxodd._config.built_in_score_reporting = false
	Luxodd.level_begin(3)
	await _wait_for_signal(Luxodd.level_begin_ok, 3.0)
	_assert(not Luxodd.is_score_tracking(), "No tracking when built_in_score_reporting is off")
	Luxodd.level_end(3, 10)
	await _wait_for_signal(Luxodd.level_end_ok, 3.0)
	Luxodd._config.built_in_score_reporting = true

	_begin("prize_won")
	Luxodd.level_end(1, 7777)
	var tickets = await _wait_for_signal(Luxodd.prize_won, 3.0)
	_assert(tickets is Array and tickets.size() == 1, "prize_tickets from level_end are forwarded as prize_won")

	_begin("runtime_context")
	Luxodd._on_bridge_session("", "", {"platform": "arcade", "arcadeLayout": "rook"})
	_assert(Luxodd.is_arcade and Luxodd.is_rook and not Luxodd.is_pawn, "arcade/rook from luxodd:session runtime")
	Luxodd._on_bridge_session("", "", {"platform": "arcade", "arcadeLayout": "bishop"})
	_assert(Luxodd.is_arcade and Luxodd.arcade_layout == "", "Unknown layout maps to none")
	Luxodd._on_bridge_session("", "", {})
	_assert(not Luxodd.has_host_runtime_context and Luxodd.runtime_platform == "", "No runtime clears the context")

	_begin("session_event_repeat_ignored")
	var conns_before := _connections().size()
	Luxodd._on_bridge_session(Luxodd._session_token, "", {})
	await get_tree().create_timer(0.3).timeout
	_assert(_connections().size() == conns_before and Luxodd.is_connected, "A repeat of the current session does not reconnect")

	_begin("fast_restart_continue")
	Luxodd.send_session_option_fast_restart(true)
	var cont: Array = []
	var cont_cb := func(a): cont.append(a)
	Luxodd.host_action_received.connect(cont_cb, CONNECT_ONE_SHOT)
	Luxodd._on_bridge_action("continue")
	_assert(cont == ["continue"] and not Luxodd._fast_restart_pending, "Continue passes through and clears Fast Restart")

	_begin("fast_restart_handoff")
	Luxodd.start_health_check(0.5)
	Luxodd.level_begin(1)
	await _wait_for_signal(Luxodd.level_begin_ok, 3.0)
	Luxodd.send_session_option_fast_restart(true)
	var actions: Array = []
	var act_cb := func(a): actions.append(a)
	Luxodd.host_action_received.connect(act_cb)
	# The page dispatches luxodd:session with token B, then posts {action: "restart", jwt: B}.
	Luxodd._on_bridge_session("test_token_B", "", {"platform": "arcade", "arcadeLayout": "pawn"})
	Luxodd._on_bridge_jwt("test_token_B")
	Luxodd._on_bridge_action("restart")
	_assert(actions.is_empty(), "restart is held until the replacement session is up")
	var replaced = await _wait_for_signal(Luxodd.session_replaced, 4.0)
	_assert(replaced != null, "session_replaced fires")
	await get_tree().process_frame
	_assert(actions == ["restart"], "host_action_received(restart) follows the handoff")
	Luxodd.host_action_received.disconnect(act_cb)
	var conns := _connections()
	_assert(conns.size() > 0 and conns[-1].get("token") == "test_token_B", "The new socket uses token B")
	_assert(Luxodd.is_pawn, "Runtime context from the handoff event applied")
	_assert(not Luxodd.is_score_tracking(), "Score tracking of the old session stopped")
	_assert(not Luxodd._health_timer.is_stopped(), "Health check resumed on the new session")
	var health_b = await _wait_for_signal(Luxodd.health_check_ok, 3.0)
	_assert(health_b != null, "Health check answered on the new session")
	var new_conn: int = conns[-1].get("conn")
	Luxodd.level_begin(1)
	await _wait_for_signal(Luxodd.level_begin_ok, 3.0)
	var lb_frame := _last_frame("level_begin")
	_assert(not lb_frame.is_empty(), "level_begin on the replacement session")
	var lb_conn := -1
	for f in _frames():
		if f["request"].get("type") == "level_begin":
			lb_conn = f.get("conn")
	_assert(lb_conn == new_conn, "That level_begin went over the new connection")
	Luxodd.level_end(1, 5)
	await _wait_for_signal(Luxodd.level_end_ok, 3.0)

	_begin("fast_restart_busy")
	Luxodd.send_session_option_fast_restart()
	Luxodd._on_bridge_action("restart")  # selected, no token yet
	var busy = await _wait_for_signal_now(Luxodd.fast_restart_failed, func(): Luxodd.send_session_option_fast_restart())
	_assert(busy == 409, "A second Fast Restart during a handoff is refused with 409")
	Luxodd._clear_fast_restart()

	_begin("ws_endpoint")
	_assert(Luxodd._resolve_endpoint() == "ws://localhost:8765/ws", "Desktop endpoint is <server_address>/ws")
	_assert(Luxodd._resolve_server_url() == "ws://localhost:8765", "1.0.0 _resolve_server_url unchanged")

	_begin("protocol_envelopes")
	var proto_frames := _frames()
	var legacy_ok := true
	for f in proto_frames:
		var r: Dictionary = f["request"]
		if r.get("type") in ["GetProfileRequest", "level_begin", "health_status_check", "SetUserDataRequest"]:
			if r.get("version") != "1.0" or not r.get("payload") is Dictionary:
				legacy_ok = false
	_assert(legacy_ok, "1.0.0 commands keep {type, version: 1.0, payload: {}}")


func _wait_for_signal_now(sig: Signal, trigger: Callable) -> Variant:
	var result: Array = []
	var cb := func(a = null, _b = null): result.append(a)
	sig.connect(cb, CONNECT_ONE_SHOT)
	trigger.call()
	if sig.is_connected(cb):
		sig.disconnect(cb)
	return result[0] if result.size() > 0 else null


func _record() -> Dictionary:
	var path := OS.get_environment("LUXODD_MOCK_FRAMES")
	if path.is_empty():
		path = ProjectSettings.globalize_path("res://tests/.mock_frames.json")
	if not FileAccess.file_exists(path):
		return {"connections": [], "frames": []}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {"connections": [], "frames": []}


func _frames() -> Array:
	return _record().get("frames", [])


func _connections() -> Array:
	return _record().get("connections", [])


func _last_frame(type: String) -> Dictionary:
	var frames := _frames()
	for i in range(frames.size() - 1, -1, -1):
		if frames[i]["request"].get("type") == type:
			return frames[i]["request"]
	return {}


# ── Test helpers ──────────────────────────────────────────────────────────────

## Wait for a signal with a timeout. Returns the first signal argument, or null on timeout.
func _wait_for_signal(sig: Signal, timeout: float) -> Variant:
	var result: Array = []
	var timed_out := false

	var timer := get_tree().create_timer(timeout)

	# Connect to capture the signal payload
	var cb := func(arg1 = null, arg2 = null, arg3 = null):
		if arg1 != null:
			result.append(arg1)
		else:
			result.append(true)

	if sig.get_connections().size() > 20:
		# Safety: don't pile up connections
		pass

	sig.connect(cb, CONNECT_ONE_SHOT)

	# Wait for whichever fires first
	while result.is_empty() and not timed_out:
		await get_tree().process_frame
		if timer.time_left <= 0:
			timed_out = true

	if timed_out and result.is_empty():
		# Disconnect our callback if it didn't fire
		if sig.is_connected(cb):
			sig.disconnect(cb)
		return null

	return result[0] if result.size() > 0 else null


func _begin(test_name: String) -> void:
	_current_test = test_name
	_tests_total += 1


func _assert(condition: bool, message: String) -> void:
	if condition:
		_tests_passed += 1
		print("  PASS  %s: %s" % [_current_test, message])
	else:
		_tests_failed += 1
		print("  FAIL  %s: %s" % [_current_test, message])


func _fail(message: String) -> void:
	_tests_failed += 1
	print("  FAIL  %s" % message)


func _finish() -> void:
	_timeout_timer.stop()

	print("\n========================================")
	print("  Results: %d passed, %d failed (of %d tests)" % [_tests_passed, _tests_failed, _tests_total])
	print("========================================\n")

	if _tests_failed > 0:
		print("FAILED")
		get_tree().quit(1)
	else:
		print("ALL TESTS PASSED")
		get_tree().quit(0)


func _on_global_timeout() -> void:
	print("\n  TIMEOUT  Tests exceeded 15 second global timeout")
	_tests_failed += 1
	_finish()

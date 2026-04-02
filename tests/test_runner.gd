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
	Luxodd._websocket.configure(config.max_reconnect_attempts, config.reconnect_delay_seconds)

	# Global timeout — if tests hang, bail after 15 seconds
	_timeout_timer = Timer.new()
	_timeout_timer.wait_time = 15.0
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

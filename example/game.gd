extends Control

## Target Pop — Example arcade game demonstrating the Luxodd plugin.
##
## Flow: Connect → Menu (profile + balance) → Pay to Play → Gameplay → Game Over → Leaderboard
##
## Demonstrates: connect_to_server, get_profile, get_balance, charge_balance,
## level_begin, level_end, get_leaderboard, health_check, session actions.

const TARGET_SCENE := preload("res://target.tscn")
const ROUND_DURATION := 30.0
const SPAWN_INTERVAL_START := 1.2
const SPAWN_INTERVAL_MIN := 0.4
const PLAY_COST := 100

# ── State ─────────────────────────────────────────────────────────────────────

enum State { CONNECTING, MENU, PLAYING, GAME_OVER }

var _state: State = State.CONNECTING
var _score: int = 0
var _combo: int = 0
var _max_combo: int = 0
var _misses: int = 0
var _time_left: float = 0.0
var _spawn_timer: float = 0.0
var _spawn_interval: float = SPAWN_INTERVAL_START
var _level: int = 1
var _balance: int = 0
var _username: String = "Player"

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var _game_area: Node2D = %GameArea
@onready var _hud: Control = %HUD
@onready var _menu_panel: Control = %MenuPanel
@onready var _game_over_panel: Control = %GameOverPanel
@onready var _connecting_label: Label = %ConnectingLabel

# HUD elements
@onready var _score_label: Label = %ScoreLabel
@onready var _time_label: Label = %TimeLabel
@onready var _combo_label: Label = %ComboLabel
@onready var _miss_label: Label = %MissLabel

# Menu elements
@onready var _welcome_label: Label = %WelcomeLabel
@onready var _balance_label: Label = %BalanceLabel
@onready var _play_button: Button = %PlayButton
@onready var _cost_label: Label = %CostLabel

# Game over elements
@onready var _final_score_label: Label = %FinalScoreLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _leaderboard_list: RichTextLabel = %LeaderboardList
@onready var _play_again_button: Button = %PlayAgainButton


func _ready() -> void:
	_set_state(State.CONNECTING)

	# Wire up Luxodd signals
	Luxodd.connected.connect(_on_connected)
	Luxodd.connection_failed.connect(_on_connection_failed)
	Luxodd.profile_received.connect(_on_profile)
	Luxodd.balance_received.connect(_on_balance)
	Luxodd.balance_charged.connect(_on_charged)
	Luxodd.level_begin_ok.connect(func(): print("[game] Level begin confirmed"))
	Luxodd.level_end_ok.connect(func(): print("[game] Level end confirmed"))
	Luxodd.leaderboard_received.connect(_on_leaderboard)
	Luxodd.command_error.connect(_on_command_error)
	Luxodd.host_action_received.connect(_on_host_action)

	Luxodd.connect_to_server()


func _process(delta: float) -> void:
	if _state != State.PLAYING:
		return

	# Countdown
	_time_left -= delta
	_time_label.text = "%02d" % max(0, ceili(_time_left))

	if _time_left <= 0.0:
		_end_round()
		return

	# Spawn targets
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_target()
		_spawn_timer = _spawn_interval
		# Accelerate spawns over time
		var progress := 1.0 - (_time_left / ROUND_DURATION)
		_spawn_interval = lerpf(SPAWN_INTERVAL_START, SPAWN_INTERVAL_MIN, progress)


# ── State management ──────────────────────────────────────────────────────────

func _set_state(new_state: State) -> void:
	_state = new_state
	_connecting_label.visible = new_state == State.CONNECTING
	_menu_panel.visible = new_state == State.MENU
	_hud.visible = new_state == State.PLAYING
	_game_over_panel.visible = new_state == State.GAME_OVER
	_game_area.visible = new_state == State.PLAYING


# ── Luxodd callbacks ─────────────────────────────────────────────────────────

func _on_connected() -> void:
	Luxodd.notify_game_ready()
	Luxodd.start_health_check()
	Luxodd.get_profile()
	Luxodd.get_balance()
	_set_state(State.MENU)


func _on_connection_failed(error: String) -> void:
	_connecting_label.text = "Connection failed: %s\nRetrying..." % error
	await get_tree().create_timer(2.0).timeout
	Luxodd.connect_to_server()


func _on_profile(profile: Dictionary) -> void:
	_username = profile.get("name", profile.get("username", "Player"))
	_welcome_label.text = "Welcome, %s!" % _username


func _on_balance(balance_data: Dictionary) -> void:
	_balance = int(balance_data.get("balance", 0))
	_balance_label.text = "%d credits" % _balance
	_play_button.disabled = _balance < PLAY_COST
	if _balance < PLAY_COST:
		_cost_label.text = "Not enough credits (%d required)" % PLAY_COST
	else:
		_cost_label.text = "Costs %d credits to play" % PLAY_COST


func _on_charged() -> void:
	# Payment went through — start the game
	_start_round()


func _on_leaderboard(data: Dictionary) -> void:
	_leaderboard_list.clear()
	_leaderboard_list.push_bold()
	_leaderboard_list.append_text("  LEADERBOARD\n")
	_leaderboard_list.pop()
	_leaderboard_list.append_text("  ─────────────────────\n")

	var entries: Array = data.get("leaderboard", [])
	for i in range(mini(entries.size(), 10)):
		var entry: Dictionary = entries[i]
		var rank: int = entry.get("rank", i + 1)
		var name: String = entry.get("username", "???")
		var score: int = int(entry.get("total_score", 0))
		var prefix := "► " if name == _username else "  "
		_leaderboard_list.append_text("%s%d. %s — %d\n" % [prefix, rank, name, score])


func _on_command_error(command: String, code: int, message: String) -> void:
	print("[game] Error [%s] %d: %s" % [command, code, message])
	if command == "ChargeUserBalanceRequest":
		_cost_label.text = "Payment failed! Try again."
		_play_button.disabled = false


func _on_host_action(action: String) -> void:
	match action:
		"restart":
			_cleanup_targets()
			_set_state(State.MENU)
			Luxodd.get_balance()
		"end":
			Luxodd.notify_session_end()


# ── Gameplay ──────────────────────────────────────────────────────────────────

func _on_play_pressed() -> void:
	_play_button.disabled = true
	_cost_label.text = "Charging..."
	Luxodd.charge_balance(PLAY_COST, 0000)


func _start_round() -> void:
	_score = 0
	_combo = 0
	_max_combo = 0
	_misses = 0
	_time_left = ROUND_DURATION
	_spawn_timer = 0.5
	_spawn_interval = SPAWN_INTERVAL_START

	_score_label.text = "0"
	_combo_label.text = ""
	_miss_label.text = ""
	_time_label.text = str(int(ROUND_DURATION))

	_set_state(State.PLAYING)
	Luxodd.level_begin(_level)


func _end_round() -> void:
	_cleanup_targets()
	_set_state(State.GAME_OVER)

	_final_score_label.text = "%d" % _score
	_stats_label.text = "Combo: x%d  |  Misses: %d  |  Accuracy: %d%%" % [
		_max_combo,
		_misses,
		_get_accuracy(),
	]

	Luxodd.level_end(_level, _score, _get_accuracy(), int(ROUND_DURATION))
	Luxodd.get_leaderboard()
	Luxodd.get_balance()
	_level += 1


func _spawn_target() -> void:
	var target: Area2D = TARGET_SCENE.instantiate()
	var margin := 50.0
	var area_size := get_viewport_rect().size
	target.position = Vector2(
		randf_range(margin, area_size.x - margin),
		randf_range(margin + 80, area_size.y - margin),
	)
	# Vary difficulty
	var progress := 1.0 - (_time_left / ROUND_DURATION)
	target.lifetime = lerpf(2.5, 1.2, progress)
	target.points = 100 + int(progress * 50.0)

	target.scored.connect(_on_target_scored)
	target.missed.connect(_on_target_missed)
	_game_area.add_child(target)


func _on_target_scored(points: int) -> void:
	_combo += 1
	if _combo > _max_combo:
		_max_combo = _combo
	var combo_bonus := mini(_combo - 1, 5) * 25
	var total := points + combo_bonus
	_score += total

	_score_label.text = str(_score)
	if _combo > 1:
		_combo_label.text = "x%d COMBO!" % _combo
		_combo_label.modulate = Color.YELLOW
	else:
		_combo_label.text = "+%d" % total


func _on_target_missed() -> void:
	_misses += 1
	_combo = 0
	_combo_label.text = "MISS"
	_combo_label.modulate = Color.RED
	_miss_label.text = "%d missed" % _misses


func _cleanup_targets() -> void:
	for child in _game_area.get_children():
		child.queue_free()


func _get_accuracy() -> int:
	var total := _score / 100 + _misses  # rough total targets
	if total == 0:
		return 100
	return int(float(_score / 100) / float(total) * 100.0)


func _on_play_again_pressed() -> void:
	_play_button.disabled = _balance < PLAY_COST
	if _balance >= PLAY_COST:
		_cost_label.text = "Costs %d credits to play" % PLAY_COST
	else:
		_cost_label.text = "Not enough credits (%d required)" % PLAY_COST
	_set_state(State.MENU)

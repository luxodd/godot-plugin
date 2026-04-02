extends Control

## TOWER STACKER — Arcade prize game with Luxodd betting integration.
##
## Blocks slide back and forth. Tap to drop. Only the overlap carries up.
## Each level speeds up. Reach betting tiers to multiply your wager.
##
## Controls: Space / Enter / Gamepad A to drop block.

# ── Constants ─────────────────────────────────────────────────────────────────

const GRID_COLS := 7
const GRID_ROWS := 15
const CELL_SIZE := 48.0
const BASE_SPEED := 3.0         # cells per second at level 0
const SPEED_INCREASE := 0.35    # additional cells/sec per level
const START_WIDTH := 4           # block width at level 0
const MIN_WIDTH := 1
const PLAY_COST := 100

# Betting tiers: [level_threshold, multiplier_label]
const TIERS := [
	[12, "JACKPOT 10x"],
	[10, "MAJOR 5x"],
	[8,  "MINOR 3x"],
	[5,  "MINI 2x"],
]

# Neon color cycle per level
const LEVEL_COLORS := [
	Color(0.0, 0.9, 1.0),    # cyan
	Color(0.2, 0.8, 1.0),    # light blue
	Color(0.4, 0.4, 1.0),    # blue
	Color(0.6, 0.2, 1.0),    # purple
	Color(1.0, 0.2, 0.8),    # magenta
	Color(1.0, 0.2, 0.4),    # pink-red
	Color(1.0, 0.5, 0.1),    # orange
	Color(1.0, 0.9, 0.1),    # yellow
	Color(0.4, 1.0, 0.2),    # green
	Color(0.0, 1.0, 0.6),    # teal
	Color(0.0, 0.9, 1.0),    # cyan again
	Color(1.0, 1.0, 1.0),    # white (jackpot level)
	Color(1.0, 0.85, 0.0),   # gold (jackpot)
]

# ── State ─────────────────────────────────────────────────────────────────────

enum State { CONNECTING, MENU, PLAYING, DROPPING, GAME_OVER }

var _state: State = State.CONNECTING
var _level: int = 0
var _score: int = 0
var _balance: int = 0
var _username: String = "Player"

# Stack data: array of { x: int, width: int, color: Color } per completed row
var _stack: Array[Dictionary] = []

# Current sliding block
var _block_x: float = 0.0     # current x position (float for smooth sliding)
var _block_width: int = START_WIDTH
var _block_dir: float = 1.0   # 1.0 = right, -1.0 = left
var _block_speed: float = BASE_SPEED

# Drop animation
var _drop_y: float = 0.0
var _drop_target_y: float = 0.0
var _drop_data: Dictionary = {}
var _chopped_piece: Dictionary = {}  # the cut-off piece that falls away
var _chop_fall_y: float = 0.0

# Grid origin (bottom-left of the playfield in screen coords)
var _grid_origin: Vector2

# Shake effect
var _shake_amount: float = 0.0
var _shake_timer: float = 0.0

# Perfect placement streak
var _perfect_streak: int = 0
var _show_perfect: bool = false
var _perfect_timer: float = 0.0

# ── Node refs ─────────────────────────────────────────────────────────────────

@onready var _menu_panel: Control = %MenuPanel
@onready var _game_over_panel: Control = %GameOverPanel
@onready var _connecting_label: Label = %ConnectingLabel
@onready var _hud: Control = %HUD

# Menu
@onready var _welcome_label: Label = %WelcomeLabel
@onready var _balance_label: Label = %BalanceLabel
@onready var _play_button: Button = %PlayButton
@onready var _cost_label: Label = %CostLabel

# HUD
@onready var _level_label: Label = %LevelLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _tier_label: Label = %TierLabel

# Game Over
@onready var _result_title: Label = %ResultTitle
@onready var _final_score_label: Label = %FinalScoreLabel
@onready var _tier_result_label: Label = %TierResultLabel
@onready var _leaderboard_list: RichTextLabel = %LeaderboardList
@onready var _play_again_button: Button = %PlayAgainButton


func _ready() -> void:
	# Center the grid
	var grid_width := GRID_COLS * CELL_SIZE
	var grid_height := GRID_ROWS * CELL_SIZE
	var vp := get_viewport_rect().size
	_grid_origin = Vector2(
		(vp.x - grid_width) * 0.5,
		vp.y - 40.0  # 40px bottom margin
	)

	_apply_theme()
	_set_state(State.CONNECTING)

	Luxodd.connected.connect(_on_connected)
	Luxodd.connection_failed.connect(_on_connection_failed)
	Luxodd.profile_received.connect(_on_profile)
	Luxodd.balance_received.connect(_on_balance)
	Luxodd.balance_charged.connect(_on_charged)
	Luxodd.leaderboard_received.connect(_on_leaderboard)
	Luxodd.command_error.connect(_on_command_error)
	Luxodd.host_action_received.connect(_on_host_action)

	Luxodd.connect_to_server()


func _process(delta: float) -> void:
	match _state:
		State.PLAYING:
			_update_sliding(delta)
		State.DROPPING:
			_update_drop(delta)

	# Shake decay
	if _shake_timer > 0.0:
		_shake_timer -= delta
		_shake_amount *= 0.85
	else:
		_shake_amount = 0.0

	# Perfect text fade
	if _show_perfect:
		_perfect_timer -= delta
		if _perfect_timer <= 0.0:
			_show_perfect = false

	queue_redraw()


func _input(event: InputEvent) -> void:
	if _state != State.PLAYING:
		return

	var drop := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER]:
			drop = true
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X]:
			drop = true

	if drop:
		_drop_block()


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var shake_offset := Vector2(
		randf_range(-_shake_amount, _shake_amount),
		randf_range(-_shake_amount, _shake_amount)
	) if _shake_amount > 0.5 else Vector2.ZERO

	_draw_background()
	_draw_grid(shake_offset)
	_draw_tier_markers(shake_offset)
	_draw_stack(shake_offset)

	if _state == State.PLAYING:
		_draw_sliding_block(shake_offset)
	elif _state == State.DROPPING:
		_draw_dropping_block(shake_offset)
		_draw_chopped_piece(shake_offset)

	if _show_perfect:
		_draw_perfect_text(shake_offset)


func _draw_background() -> void:
	# Dark background
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.03, 0.03, 0.06))

	# Subtle grid glow behind playfield
	var grid_rect := Rect2(
		_grid_origin + Vector2(0, -GRID_ROWS * CELL_SIZE),
		Vector2(GRID_COLS * CELL_SIZE, GRID_ROWS * CELL_SIZE)
	)
	draw_rect(grid_rect, Color(0.05, 0.05, 0.1))


func _draw_grid(offset: Vector2) -> void:
	var grid_w := GRID_COLS * CELL_SIZE
	var grid_h := GRID_ROWS * CELL_SIZE
	var origin := _grid_origin + offset
	var line_color := Color(0.12, 0.12, 0.2, 0.5)

	# Vertical lines
	for i in range(GRID_COLS + 1):
		var x := origin.x + i * CELL_SIZE
		draw_line(
			Vector2(x, origin.y - grid_h),
			Vector2(x, origin.y),
			line_color, 1.0
		)

	# Horizontal lines
	for i in range(GRID_ROWS + 1):
		var y := origin.y - i * CELL_SIZE
		draw_line(
			Vector2(origin.x, y),
			Vector2(origin.x + grid_w, y),
			line_color, 1.0
		)

	# Border glow
	var border_color := Color(0.2, 0.3, 0.5, 0.6)
	var r := Rect2(origin + Vector2(0, -grid_h), Vector2(grid_w, grid_h))
	draw_rect(r, border_color, false, 2.0)


func _draw_tier_markers(offset: Vector2) -> void:
	var origin := _grid_origin + offset
	for tier in TIERS:
		var row: int = tier[0]
		var label: String = tier[1]
		if row > GRID_ROWS:
			continue
		var y := origin.y - row * CELL_SIZE
		var left := origin.x - 8.0
		# Dashed line
		var tier_color := Color(1.0, 0.85, 0.0, 0.4) if "JACKPOT" in label else Color(0.5, 0.5, 0.8, 0.3)
		draw_dashed_line(
			Vector2(origin.x, y),
			Vector2(origin.x + GRID_COLS * CELL_SIZE, y),
			tier_color, 1.0, 6.0
		)


func _draw_stack(offset: Vector2) -> void:
	var origin := _grid_origin + offset
	for i in range(_stack.size()):
		var row: Dictionary = _stack[i]
		var rect := Rect2(
			origin.x + row["x"] * CELL_SIZE + 1,
			origin.y - (i + 1) * CELL_SIZE + 1,
			row["width"] * CELL_SIZE - 2,
			CELL_SIZE - 2,
		)
		var col: Color = row["color"]
		# Filled block
		draw_rect(rect, col * 0.4)
		# Neon border
		draw_rect(rect, col, false, 2.0)


func _draw_sliding_block(offset: Vector2) -> void:
	var origin := _grid_origin + offset
	var row_y := _level
	var rect := Rect2(
		origin.x + _block_x * CELL_SIZE + 1,
		origin.y - (row_y + 1) * CELL_SIZE + 1,
		_block_width * CELL_SIZE - 2,
		CELL_SIZE - 2,
	)
	var col := _get_level_color(_level)
	# Bright fill for active block
	draw_rect(rect, col * 0.7)
	draw_rect(rect, col, false, 2.5)
	# Glow effect
	var glow_rect := rect.grow(3.0)
	var glow_col := col
	glow_col.a = 0.15 + 0.1 * sin(Time.get_ticks_msec() / 150.0)
	draw_rect(glow_rect, glow_col)


func _draw_dropping_block(offset: Vector2) -> void:
	if _drop_data.is_empty():
		return
	var origin := _grid_origin + offset
	var rect := Rect2(
		origin.x + _drop_data["x"] * CELL_SIZE + 1,
		origin.y - (_drop_y + 1) * CELL_SIZE + 1,
		_drop_data["width"] * CELL_SIZE - 2,
		CELL_SIZE - 2,
	)
	var col: Color = _drop_data["color"]
	draw_rect(rect, col * 0.7)
	draw_rect(rect, col, false, 2.5)


func _draw_chopped_piece(offset: Vector2) -> void:
	if _chopped_piece.is_empty():
		return
	var origin := _grid_origin + offset
	var rect := Rect2(
		origin.x + _chopped_piece["x"] * CELL_SIZE + 1,
		origin.y - (_chop_fall_y + 1) * CELL_SIZE + 1,
		_chopped_piece["width"] * CELL_SIZE - 2,
		CELL_SIZE - 2,
	)
	var col: Color = _chopped_piece["color"]
	col.a = clampf(_chop_fall_y / float(_level), 0.0, 1.0)
	draw_rect(rect, col * 0.5)
	draw_rect(rect, col, false, 1.5)


func _draw_perfect_text(offset: Vector2) -> void:
	var origin := _grid_origin + offset
	var y := origin.y - (_level) * CELL_SIZE - 10.0
	var x := origin.x + GRID_COLS * CELL_SIZE * 0.5
	var alpha := clampf(_perfect_timer / 0.5, 0.0, 1.0)
	var text := "PERFECT!" if _perfect_streak < 3 else "PERFECT x%d!" % _perfect_streak
	var col := Color(1.0, 1.0, 0.2, alpha)
	var font := ThemeDB.fallback_font
	var fsize := 22 if _perfect_streak < 3 else 28
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
	draw_string(font, Vector2(x - text_size.x * 0.5, y - _perfect_timer * 20.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, col)


# ── Game logic ────────────────────────────────────────────────────────────────

func _update_sliding(delta: float) -> void:
	_block_x += _block_dir * _block_speed * delta

	# Bounce off walls
	if _block_x + _block_width > GRID_COLS:
		_block_x = float(GRID_COLS - _block_width)
		_block_dir = -1.0
	elif _block_x < 0.0:
		_block_x = 0.0
		_block_dir = 1.0


func _drop_block() -> void:
	var drop_x := roundi(_block_x)  # snap to nearest grid cell
	# Clamp
	drop_x = clampi(drop_x, 0, GRID_COLS - _block_width)

	var color := _get_level_color(_level)

	if _level == 0:
		# First block always lands perfectly
		_land_block(drop_x, _block_width, color, true)
		return

	# Calculate overlap with the block below
	var prev: Dictionary = _stack[_level - 1]
	var prev_left: int = prev["x"]
	var prev_right: int = prev["x"] + prev["width"]
	var curr_left: int = drop_x
	var curr_right: int = drop_x + _block_width

	var overlap_left: int = maxi(prev_left, curr_left)
	var overlap_right: int = mini(prev_right, curr_right)
	var overlap_width: int = overlap_right - overlap_left

	if overlap_width <= 0:
		# Complete miss — game over
		_start_game_over()
		return

	var is_perfect: bool = (overlap_width == _block_width and _block_width == int(prev["width"]))

	# Calculate chopped piece
	_chopped_piece = {}
	if not is_perfect:
		if curr_left < overlap_left:
			# Chopped off left side
			_chopped_piece = {
				"x": curr_left,
				"width": overlap_left - curr_left,
				"color": color,
			}
		elif curr_right > overlap_right:
			# Chopped off right side
			_chopped_piece = {
				"x": overlap_right,
				"width": curr_right - overlap_right,
				"color": color,
			}
		_chop_fall_y = float(_level)

	# Animate the drop
	_drop_data = { "x": overlap_left, "width": overlap_width, "color": color }
	_drop_y = float(_level) + 3.0  # start slightly above
	_drop_target_y = float(_level)
	_state = State.DROPPING
	_land_block(overlap_left, overlap_width, color, is_perfect)


func _land_block(x: int, width: int, color: Color, is_perfect: bool) -> void:
	_stack.append({ "x": x, "width": width, "color": color })

	# Scoring
	var level_score := 100 + _level * 25
	if is_perfect:
		_perfect_streak += 1
		level_score += 50 * _perfect_streak
		_show_perfect = true
		_perfect_timer = 1.0
	else:
		_perfect_streak = 0

	_score += level_score
	_score_label.text = str(_score)

	# Screen shake
	_shake_amount = 4.0 + _level * 0.3
	_shake_timer = 0.2

	# Advance
	_level += 1
	_level_label.text = "LEVEL %d" % _level

	# Update tier display
	_update_tier_display()

	# Check if topped out
	if _level >= GRID_ROWS:
		_start_game_over()
		return

	# Next block — inherits the width of what landed
	_block_width = width
	_block_speed = BASE_SPEED + _level * SPEED_INCREASE
	_block_x = 0.0 if _block_dir > 0 else float(GRID_COLS - _block_width)

	# Animate drop then resume
	if _state != State.DROPPING:
		_state = State.PLAYING


func _update_drop(delta: float) -> void:
	# Animate block dropping into place
	_drop_y = move_toward(_drop_y, _drop_target_y, delta * 40.0)

	# Animate chopped piece falling away
	if not _chopped_piece.is_empty():
		_chop_fall_y -= delta * 12.0

	if absf(_drop_y - _drop_target_y) < 0.05:
		_drop_data = {}
		_chopped_piece = {}
		if _level < GRID_ROWS and _state == State.DROPPING:
			_state = State.PLAYING


func _get_level_color(level: int) -> Color:
	return LEVEL_COLORS[level % LEVEL_COLORS.size()]


func _get_current_tier() -> Array:
	# Returns [threshold, label] of highest tier reached, or []
	for tier in TIERS:
		if _level >= tier[0]:
			return tier
	return []


func _update_tier_display() -> void:
	# Show next tier to reach
	var next_tier := []
	for i in range(TIERS.size() - 1, -1, -1):
		if _level < TIERS[i][0]:
			next_tier = TIERS[i]
			break

	if next_tier.is_empty():
		_tier_label.text = "MAX TIER!"
		_tier_label.modulate = Color.GOLD
	else:
		var remaining: int = next_tier[0] - _level
		_tier_label.text = "%s in %d" % [next_tier[1], remaining]
		if remaining <= 2:
			_tier_label.modulate = Color.YELLOW
		else:
			_tier_label.modulate = Color.WHITE


# ── State management ──────────────────────────────────────────────────────────

func _set_state(new_state: State) -> void:
	_state = new_state
	_connecting_label.visible = new_state == State.CONNECTING
	_menu_panel.visible = new_state == State.MENU
	_hud.visible = new_state in [State.PLAYING, State.DROPPING]
	_game_over_panel.visible = new_state == State.GAME_OVER


func _start_game() -> void:
	_stack.clear()
	_level = 0
	_score = 0
	_perfect_streak = 0
	_block_width = START_WIDTH
	_block_speed = BASE_SPEED
	_block_x = 0.0
	_block_dir = 1.0
	_drop_data = {}
	_chopped_piece = {}
	_show_perfect = false

	_score_label.text = "0"
	_level_label.text = "LEVEL 0"
	_update_tier_display()

	_set_state(State.PLAYING)
	Luxodd.level_begin(1)


func _start_game_over() -> void:
	_set_state(State.GAME_OVER)

	var tier := _get_current_tier()
	if tier.is_empty():
		_result_title.text = "GAME OVER"
		_result_title.modulate = Color.RED
		_tier_result_label.text = "No tier reached"
		_tier_result_label.modulate = Color(0.6, 0.6, 0.6)
	else:
		_result_title.text = tier[1]
		_result_title.modulate = Color.GOLD if "JACKPOT" in tier[1] else Color.YELLOW
		_tier_result_label.text = "Level %d reached!" % _level
		_tier_result_label.modulate = Color.WHITE

	_final_score_label.text = "%d pts" % _score

	Luxodd.level_end(1, _score, _level)
	Luxodd.get_leaderboard()
	Luxodd.get_balance()


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_play_pressed() -> void:
	_play_button.disabled = true
	_cost_label.text = "Charging..."
	Luxodd.charge_balance(PLAY_COST, 0000)


func _on_play_again_pressed() -> void:
	_balance_label.text = "%d credits" % _balance
	_play_button.disabled = _balance < PLAY_COST
	_cost_label.text = "Costs %d credits" % PLAY_COST if _balance >= PLAY_COST else "Not enough credits"
	_set_state(State.MENU)


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
	_welcome_label.text = "Welcome, %s" % _username


func _on_balance(balance_data: Dictionary) -> void:
	_balance = int(balance_data.get("balance", 0))
	_balance_label.text = "%d credits" % _balance
	_play_button.disabled = _balance < PLAY_COST
	if _balance < PLAY_COST:
		_cost_label.text = "Not enough credits (%d needed)" % PLAY_COST
	else:
		_cost_label.text = "Costs %d credits" % PLAY_COST


func _on_charged() -> void:
	_start_game()


func _on_leaderboard(data: Dictionary) -> void:
	_leaderboard_list.clear()
	_leaderboard_list.push_bold()
	_leaderboard_list.append_text("  LEADERBOARD\n")
	_leaderboard_list.pop()

	var entries: Array = data.get("leaderboard", [])
	for i in range(mini(entries.size(), 8)):
		var entry: Dictionary = entries[i]
		var rank: int = entry.get("rank", i + 1)
		var uname: String = entry.get("username", "???")
		var sc: int = int(entry.get("total_score", 0))
		var highlight := "► " if uname == _username else "  "
		_leaderboard_list.append_text("%s%d. %s — %d\n" % [highlight, rank, uname, sc])


func _on_command_error(command: String, code: int, message: String) -> void:
	print("[stacker] Error [%s] %d: %s" % [command, code, message])
	if command == "ChargeUserBalanceRequest":
		_cost_label.text = "Payment failed!"
		_play_button.disabled = false


func _on_host_action(action: String) -> void:
	match action:
		"restart":
			_set_state(State.MENU)
			Luxodd.get_balance()
		"end":
			Luxodd.notify_session_end()


func _apply_theme() -> void:
	# Title screen
	_connecting_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	_connecting_label.add_theme_font_size_override("font_size", 20)

	# HUD
	_level_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	_level_label.add_theme_font_size_override("font_size", 20)
	_score_label.add_theme_font_size_override("font_size", 26)
	_tier_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	_tier_label.add_theme_font_size_override("font_size", 16)

	# Menu
	var title_node: Label = %MenuPanel.get_node("VBox/Title")
	title_node.add_theme_color_override("font_color", Color(0.0, 0.9, 1.0))
	title_node.add_theme_font_size_override("font_size", 36)
	var subtitle_node: Label = %MenuPanel.get_node("VBox/Subtitle")
	subtitle_node.add_theme_color_override("font_color", Color(0.5, 0.5, 0.7))
	subtitle_node.add_theme_font_size_override("font_size", 14)
	_welcome_label.add_theme_font_size_override("font_size", 18)
	_balance_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_balance_label.add_theme_font_size_override("font_size", 24)
	_play_button.add_theme_font_size_override("font_size", 22)
	_cost_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_cost_label.add_theme_font_size_override("font_size", 14)

	# Game over
	_result_title.add_theme_font_size_override("font_size", 32)
	_final_score_label.add_theme_font_size_override("font_size", 28)
	_tier_result_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_tier_result_label.add_theme_font_size_override("font_size", 16)
	_play_again_button.add_theme_font_size_override("font_size", 18)

	# Drop hint
	var hint: Label = %HUD.get_node("DropHint")
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.6))
	hint.add_theme_font_size_override("font_size", 14)

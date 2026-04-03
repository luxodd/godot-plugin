extends Node2D

## VOID RUN — One-button auto-runner with Luxodd betting integration.
## Controls: Space / Enter / Gamepad A/B to jump.

# ── Tuning ────────────────────────────────────────────────────────────────────

const GRAVITY := 2400.0
const JUMP_FORCE := -680.0
const APEX_GRAVITY_MULT := 0.45
const BASE_SPEED := 250.0
const MAX_SPEED := 580.0
const SPEED_RAMP := 3.5

const GROUND_Y := 500.0
const CUBE_SIZE := 26.0
const HITBOX_SHRINK := 5.0

const OBSTACLE_MIN_GAP := 280.0
const OBSTACLE_MAX_GAP := 420.0
const SAFE_ZONE := 500.0

const PLAY_COST := 100
const AFTERIMAGE_COUNT := 5

const TIERS: Array = [
	[2000, "MINI 2x", Color(0.3, 0.8, 1.0)],
	[4000, "MINOR 3x", Color(0.3, 1.0, 0.5)],
	[7000, "MAJOR 5x", Color(1.0, 0.85, 0.0)],
	[12000, "JACKPOT 10x", Color(1.0, 0.3, 0.3)],
]

# ── State ─────────────────────────────────────────────────────────────────────

enum State { CONNECTING, TAP_TO_START, MENU, COUNTDOWN, PLAYING, DEAD, GAME_OVER }

var _state: State = State.CONNECTING

# Player
var _cube_y: float = GROUND_Y - CUBE_SIZE
var _vel_y: float = 0.0
var _on_ground: bool = true
var _was_on_ground: bool = true
var _rotation: float = 0.0
var _jumps_queued: bool = false
var _squash: float = 1.0          # 1.0 = normal, <1 = squash, >1 = stretch
var _afterimages: Array[Dictionary] = []
var _afterimage_timer: float = 0.0

# World
var _speed: float = BASE_SPEED
var _distance: float = 0.0
var _score: int = 0
var _obstacles: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _float_texts: Array[Dictionary] = []
var _ground_offset: float = 0.0
var _obstacles_passed: int = 0
var _last_tier_reached: int = -1

# Screen effects
var _shake: float = 0.0
var _flash_alpha: float = 0.0
var _flash_color: Color = Color.WHITE
var _death_timer: float = 0.0
var _speed_lines: Array[Dictionary] = []
var _countdown_timer: float = 0.0
var _countdown_text: String = ""
var _bg_pulse: float = 0.0        # background color pulse intensity
var _ground_pulse: float = 0.0    # ground glow pulse

# Grid background
var _grid_offset: float = 0.0

# Platform
var _free_play: bool = false
var _balance: int = 0
var _username: String = "Player"
var _best_distance: int = 0

# ── UI refs ───────────────────────────────────────────────────────────────────

var _sfx: Node  # SFX manager

@onready var _connecting_label: Label = %ConnectingLabel
@onready var _menu_panel: Control = %MenuPanel
@onready var _game_over_panel: Control = %GameOverPanel
@onready var _hud: Control = %HUD

@onready var _welcome_label: Label = %WelcomeLabel
@onready var _balance_label: Label = %BalanceLabel
@onready var _play_button: Button = %PlayButton
@onready var _cost_label: Label = %CostLabel

@onready var _dist_label: Label = %DistLabel
@onready var _speed_label: Label = %SpeedLabel
@onready var _tier_label: Label = %TierLabel

@onready var _result_title: Label = %ResultTitle
@onready var _final_dist_label: Label = %FinalDistLabel
@onready var _tier_result_label: Label = %TierResultLabel
@onready var _leaderboard_list: RichTextLabel = %LeaderboardList
@onready var _play_again_button: Button = %PlayAgainButton

var _viewport_size: Vector2
var _cube_x: float


func _ready() -> void:
	_viewport_size = get_viewport_rect().size
	_cube_x = _viewport_size.x * 0.18

	# Sound effects
	var sfx_script := load("res://sfx.gd")
	_sfx = sfx_script.new()
	add_child(_sfx)

	_apply_theme()
	_set_state(State.CONNECTING)

	for i in range(20):
		_speed_lines.append({
			"x": randf() * _viewport_size.x,
			"y": randf() * _viewport_size.y,
			"speed": randf_range(0.3, 1.0),
		})

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
		State.COUNTDOWN:
			_update_countdown(delta)
		State.PLAYING:
			_update_game(delta)
		State.DEAD:
			_update_death(delta)

	_shake *= 0.86
	if _shake < 0.3:
		_shake = 0.0
	_flash_alpha = move_toward(_flash_alpha, 0.0, delta * 3.5)
	_squash = lerpf(_squash, 1.0, delta * 12.0)
	_bg_pulse = move_toward(_bg_pulse, 0.0, delta * 2.0)
	_ground_pulse = move_toward(_ground_pulse, 0.0, delta * 3.0)

	_update_speed_lines(delta)
	_update_particles(delta)
	_update_float_texts(delta)
	queue_redraw()


func _input(event: InputEvent) -> void:
	# TAP_TO_START: any input unlocks audio and starts the game
	if _state == State.TAP_TO_START:
		var any_press := false
		if event is InputEventKey and event.pressed:
			any_press = true
		if event is InputEventMouseButton and event.pressed:
			any_press = true
		if event is InputEventJoypadButton and event.pressed:
			any_press = true
		if event is InputEventScreenTouch and event.pressed:
			any_press = true
		if any_press:
			if _free_play:
				_welcome_label.text = "Welcome!"
				_balance = 999999
				_balance_label.text = "FREE PLAY"
				_play_button.disabled = false
				_cost_label.text = "No server — free play mode"
				_set_state(State.MENU)
			else:
				_start_game()
		return

	if _state != State.PLAYING:
		return
	var jump := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_UP, KEY_W]:
			jump = true
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X]:
			jump = true
	if jump:
		if _on_ground:
			_do_jump()
		else:
			_jumps_queued = true


func _do_jump() -> void:
	_vel_y = JUMP_FORCE
	_on_ground = false
	_jumps_queued = false
	_squash = 1.35
	_sfx.play("jump", -6.0)

	for i in range(8):
		_particles.append({
			"x": _cube_x + CUBE_SIZE * 0.5 + randf_range(-10, 10),
			"y": GROUND_Y,
			"vx": randf_range(-60.0, 60.0),
			"vy": randf_range(-80.0, -20.0),
			"life": randf_range(0.2, 0.4),
			"max_life": 0.4,
			"size": randf_range(2.0, 5.0),
			"color": _get_distance_color().darkened(0.2),
		})


func _land() -> void:
	_squash = 0.6
	_shake = 1.5
	_sfx.play("land", -10.0)
	for i in range(5):
		_particles.append({
			"x": _cube_x + CUBE_SIZE * 0.5 + randf_range(-6, 6),
			"y": GROUND_Y,
			"vx": randf_range(-40.0, 40.0),
			"vy": randf_range(-40.0, -10.0),
			"life": randf_range(0.1, 0.25),
			"max_life": 0.25,
			"size": randf_range(1.5, 3.5),
			"color": _get_distance_color().darkened(0.3),
		})


# ── Countdown ─────────────────────────────────────────────────────────────────

var _last_countdown: String = ""

func _update_countdown(delta: float) -> void:
	_countdown_timer -= delta
	_ground_offset = fmod(_ground_offset + BASE_SPEED * 0.5 * delta, 40.0)
	_grid_offset += BASE_SPEED * 0.3 * delta
	var prev := _countdown_text
	if _countdown_timer > 2.0:
		_countdown_text = "3"
	elif _countdown_timer > 1.0:
		_countdown_text = "2"
	elif _countdown_timer > 0.0:
		_countdown_text = "1"
	else:
		_countdown_text = "GO!"
		if _countdown_timer < -0.3:
			_state = State.PLAYING
			_flash_alpha = 0.2
			_flash_color = Color(0.2, 1.0, 0.4)
			_sfx.start_music()

	# Play beep on each countdown change
	if _countdown_text != prev:
		if _countdown_text == "GO!":
			_sfx.play("go")
		elif _countdown_text in ["3", "2", "1"]:
			_sfx.play("countdown", -3.0)


# ── Game update ───────────────────────────────────────────────────────────────

func _update_game(delta: float) -> void:
	_was_on_ground = _on_ground
	_speed = minf(_speed + SPEED_RAMP * delta, MAX_SPEED)
	_distance += _speed * delta
	_score = int(_distance / 10.0)

	# Physics with apex float
	var grav_mult := APEX_GRAVITY_MULT if (absf(_vel_y) < 130.0 and not _on_ground) else 1.0
	_vel_y += GRAVITY * grav_mult * delta
	_cube_y += _vel_y * delta

	if _cube_y >= GROUND_Y - CUBE_SIZE:
		_cube_y = GROUND_Y - CUBE_SIZE
		_vel_y = 0.0
		_on_ground = true
		if not _was_on_ground:
			_land()
		if _jumps_queued:
			_do_jump()

	# Cube rotation
	if not _on_ground:
		_rotation += delta * 7.0
	else:
		_rotation = lerpf(_rotation, roundf(_rotation / (PI * 0.5)) * PI * 0.5, delta * 18.0)

	_ground_offset = fmod(_ground_offset + _speed * delta, 40.0)
	_grid_offset += _speed * delta * 0.6

	# Afterimage trail
	_afterimage_timer -= delta
	if _afterimage_timer <= 0.0:
		_afterimage_timer = 0.025
		_afterimages.append({
			"x": _cube_x + CUBE_SIZE * 0.5,
			"y": _cube_y + CUBE_SIZE * 0.5,
			"rot": _rotation,
			"life": 0.2,
		})
		if _afterimages.size() > 12:
			_afterimages.pop_front()

	# Decay afterimages
	var ai := 0
	while ai < _afterimages.size():
		_afterimages[ai]["life"] -= delta
		if _afterimages[ai]["life"] <= 0.0:
			_afterimages.remove_at(ai)
		else:
			ai += 1

	_manage_obstacles(delta)
	_check_collision()
	_check_tier_milestone()

	if randi() % 3 == 0:
		_spawn_trail_particle()

	_dist_label.text = "%dm" % _score
	_speed_label.text = "%d km/h" % int(_speed * 0.36)
	_update_tier_hud()


func _manage_obstacles(_delta: float) -> void:
	var i := 0
	while i < _obstacles.size():
		if _obstacles[i]["x"] < -80:
			_obstacles.remove_at(i)
		else:
			i += 1

	for obs in _obstacles:
		obs["x"] -= _speed * _delta
		if not obs["passed"] and obs["x"] + float(obs["width"]) < _cube_x:
			obs["passed"] = true
			_obstacles_passed += 1
			_on_obstacle_passed(obs)

	var rightmost: float = _viewport_size.x + SAFE_ZONE if _obstacles.is_empty() else 0.0
	for obs in _obstacles:
		rightmost = maxf(rightmost, obs["x"] + float(obs["width"]))

	while rightmost < _viewport_size.x + 600:
		var progress := clampf(_obstacles_passed / 50.0, 0.0, 1.0)
		var min_gap := lerpf(OBSTACLE_MIN_GAP, 200.0, progress)
		var max_gap := lerpf(OBSTACLE_MAX_GAP, 280.0, progress)
		var gap := randf_range(min_gap, max_gap)
		var x := rightmost + gap
		_obstacles.append(_generate_obstacle(x))
		rightmost = x + float(_obstacles.back()["width"])


func _generate_obstacle(x: float) -> Dictionary:
	var difficulty := clampf(_obstacles_passed / 60.0, 0.0, 1.0)
	if randf() < 0.55:
		var h := randf_range(28.0, 40.0 + difficulty * 22.0)
		return {"x": x, "type": "spike", "height": h, "width": 22.0, "passed": false}
	else:
		var h := randf_range(34.0, 48.0 + difficulty * 18.0)
		var w := randf_range(16.0, 24.0 + difficulty * 10.0)
		return {"x": x, "type": "wall", "height": h, "width": w, "passed": false}


func _on_obstacle_passed(obs: Dictionary) -> void:
	var points := 10 + _obstacles_passed
	var near_miss := _check_near_miss(obs)
	if near_miss:
		points += 25

	_spawn_float_text(
		Vector2(obs["x"], GROUND_Y - float(obs["height"]) - 20),
		"+%d%s" % [points, " CLOSE!" if near_miss else ""],
		Color.YELLOW if near_miss else _get_distance_color().lightened(0.4),
	)

	# Obstacle pass particles
	var obs_col := _get_distance_color().lightened(0.2)
	for j in range(4 if not near_miss else 10):
		_particles.append({
			"x": obs["x"] + float(obs["width"]) * 0.5,
			"y": GROUND_Y - float(obs["height"]) * randf(),
			"vx": randf_range(-80.0, -30.0),
			"vy": randf_range(-60.0, 60.0),
			"life": randf_range(0.15, 0.35),
			"max_life": 0.35,
			"size": randf_range(2.0, 4.0) if not near_miss else randf_range(3.0, 6.0),
			"color": obs_col if not near_miss else Color.YELLOW,
		})

	if near_miss:
		_shake = 3.0
		_flash_alpha = 0.1
		_flash_color = Color.YELLOW
		_sfx.play("near_miss", -2.0)
	else:
		_sfx.play("pass", -8.0)


func _check_near_miss(obs: Dictionary) -> bool:
	if obs["type"] not in ["spike", "wall"]:
		return false
	var obs_top: float = GROUND_Y - float(obs["height"])
	var cube_bottom: float = _cube_y + CUBE_SIZE
	return cube_bottom > obs_top - 25.0 and cube_bottom < obs_top + 5.0


func _check_tier_milestone() -> void:
	for i in range(TIERS.size()):
		if _score >= TIERS[i][0] and i > _last_tier_reached:
			_last_tier_reached = i
			_celebrate_tier(TIERS[i])


func _celebrate_tier(tier: Array) -> void:
	_sfx.play("tier")
	var col: Color = tier[2]
	_flash_alpha = 0.4
	_flash_color = col
	_shake = 8.0
	_bg_pulse = 1.0
	_ground_pulse = 1.0

	_spawn_float_text(
		Vector2(_viewport_size.x * 0.5, _viewport_size.y * 0.3),
		tier[1], col,
	)

	# Big particle burst
	for j in range(40):
		var angle := randf() * TAU
		var spd := randf_range(100.0, 400.0)
		_particles.append({
			"x": _cube_x + CUBE_SIZE * 0.5,
			"y": _cube_y,
			"vx": cos(angle) * spd,
			"vy": sin(angle) * spd - 50.0,
			"life": randf_range(0.4, 1.0),
			"max_life": 1.0,
			"size": randf_range(3.0, 8.0),
			"color": col,
		})


func _check_collision() -> void:
	var cube_rect := Rect2(
		_cube_x + HITBOX_SHRINK, _cube_y + HITBOX_SHRINK,
		CUBE_SIZE - HITBOX_SHRINK * 2, CUBE_SIZE - HITBOX_SHRINK * 2,
	)
	for obs in _obstacles:
		if obs["passed"]:
			continue
		if obs["type"] in ["spike", "wall"]:
			var obs_rect := Rect2(
				obs["x"], GROUND_Y - float(obs["height"]),
				float(obs["width"]), float(obs["height"])
			)
			if cube_rect.intersects(obs_rect):
				_die()
				return


func _die() -> void:
	_state = State.DEAD
	_death_timer = 1.2
	_shake = 18.0
	_sfx.play("death")
	_sfx.stop_music()
	_flash_alpha = 1.0
	_flash_color = Color(1.0, 0.3, 0.2)

	for i in range(40):
		var angle := randf() * TAU
		var spd := randf_range(80.0, 400.0)
		_particles.append({
			"x": _cube_x + CUBE_SIZE * 0.5,
			"y": _cube_y + CUBE_SIZE * 0.5,
			"vx": cos(angle) * spd,
			"vy": sin(angle) * spd - 100.0,
			"life": randf_range(0.5, 1.3),
			"max_life": 1.3,
			"size": randf_range(3.0, 10.0),
			"color": _get_distance_color(),
		})

	_spawn_float_text(Vector2(_cube_x, _cube_y - 30), "CRASHED!", Color(1.0, 0.3, 0.3))


func _update_death(delta: float) -> void:
	_death_timer -= delta
	for obs in _obstacles:
		obs["x"] -= _speed * 0.03 * delta
	if _death_timer <= 0.0:
		_show_game_over()


func _show_game_over() -> void:
	_state = State.GAME_OVER
	_set_state(State.GAME_OVER)
	# Hide play again on platform — session end returns to arcade
	_play_again_button.visible = _free_play
	var tier := _get_reached_tier()
	if tier.is_empty():
		_result_title.text = "CRASHED"
		_result_title.modulate = Color.RED
		_tier_result_label.text = "No tier reached"
		_tier_result_label.modulate = Color(0.6, 0.6, 0.6)
	else:
		_result_title.text = tier[1]
		_result_title.modulate = tier[2]
		_tier_result_label.text = "%dm — %s!" % [_score, tier[1]]
		_tier_result_label.modulate = tier[2]
	_final_dist_label.text = "%dm" % _score
	if _score > _best_distance:
		_best_distance = _score
	if not _free_play:
		Luxodd.level_end(1, _score, int(_speed))
		# Signal session end after a delay so player can see their score
		await get_tree().create_timer(3.0).timeout
		Luxodd.notify_session_end()


# ── Particles & effects ──────────────────────────────────────────────────────

func _spawn_trail_particle() -> void:
	var col := _get_distance_color()
	col.a = 0.6
	_particles.append({
		"x": _cube_x + randf_range(-2, 3),
		"y": _cube_y + CUBE_SIZE * 0.5 + randf_range(-3, 3),
		"vx": randf_range(-50.0, -100.0),
		"vy": randf_range(-15.0, 15.0),
		"life": randf_range(0.12, 0.3),
		"max_life": 0.3,
		"size": randf_range(2.0, 4.5),
		"color": col,
	})


func _spawn_float_text(pos: Vector2, text: String, color: Color) -> void:
	_float_texts.append({
		"x": pos.x, "y": pos.y, "text": text, "color": color,
		"life": 1.2, "max_life": 1.2,
		"scale": 1.5,  # starts big, shrinks
	})


func _update_particles(delta: float) -> void:
	var i := 0
	while i < _particles.size():
		var p: Dictionary = _particles[i]
		p["x"] += p["vx"] * delta
		p["y"] += p["vy"] * delta
		p["vy"] += 300.0 * delta
		p["life"] -= delta
		if p["life"] <= 0.0:
			_particles.remove_at(i)
		else:
			i += 1


func _update_float_texts(delta: float) -> void:
	var i := 0
	while i < _float_texts.size():
		_float_texts[i]["y"] -= 45.0 * delta
		_float_texts[i]["life"] -= delta
		_float_texts[i]["scale"] = lerpf(float(_float_texts[i]["scale"]), 1.0, delta * 6.0)
		if _float_texts[i]["life"] <= 0.0:
			_float_texts.remove_at(i)
		else:
			i += 1


func _update_speed_lines(delta: float) -> void:
	var line_speed := _speed if _state in [State.PLAYING, State.COUNTDOWN] else BASE_SPEED * 0.3
	for line in _speed_lines:
		line["x"] = float(line["x"]) - line_speed * float(line["speed"]) * delta
		if line["x"] < -20:
			line["x"] = _viewport_size.x + randf() * 50.0
			line["y"] = randf() * _viewport_size.y
			line["speed"] = randf_range(0.3, 1.0)


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var so := Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))

	_draw_background(so)
	_draw_perspective_grid(so)
	_draw_speed_lines(so)
	_draw_ground(so)
	_draw_obstacles(so)
	_draw_particles(so)

	if _state in [State.PLAYING, State.DEAD, State.COUNTDOWN]:
		_draw_afterimages(so)
		_draw_cube(so)
		_draw_tier_markers(so)

	_draw_float_texts(so)

	if _state == State.COUNTDOWN:
		_draw_countdown()

	if _flash_alpha > 0.01:
		var fc := _flash_color
		fc.a = _flash_alpha
		draw_rect(Rect2(Vector2.ZERO, _viewport_size), fc)


func _draw_background(offset: Vector2) -> void:
	var base_col := _get_distance_color() * 0.08
	var pulse_add := _bg_pulse * 0.06
	var top := Color(0.02 + pulse_add, 0.02 + pulse_add, 0.06 + pulse_add) + base_col * 0.3
	var bottom := Color(0.05 + pulse_add, 0.03 + pulse_add, 0.1 + pulse_add) + base_col * 0.5
	for i in range(20):
		var t := float(i) / 20.0
		var y := t * _viewport_size.y
		var h := _viewport_size.y / 20.0 + 1.0
		draw_rect(Rect2(offset.x, y + offset.y, _viewport_size.x, h), top.lerp(bottom, t))


func _draw_perspective_grid(offset: Vector2) -> void:
	# Tron-style vanishing point grid behind the ground
	var vp_x := _viewport_size.x * 0.5
	var horizon_y := GROUND_Y - 250.0
	var grid_col := _get_distance_color() * 0.12
	grid_col.a = 0.15 + _bg_pulse * 0.1

	# Horizontal lines converging to horizon
	for i in range(12):
		var t := float(i) / 11.0
		var y := lerpf(horizon_y, GROUND_Y, t * t)  # quadratic for perspective feel
		var spread := lerpf(0.1, 1.0, t)
		var left := vp_x - _viewport_size.x * 0.6 * spread
		var right := vp_x + _viewport_size.x * 0.6 * spread
		var alpha := t * 0.4
		var lc := grid_col
		lc.a = alpha * grid_col.a
		draw_line(Vector2(left, y) + offset, Vector2(right, y) + offset, lc, 1.0)

	# Vertical lines from horizon
	var scroll := fmod(_grid_offset * 0.01, 1.0)
	for i in range(-6, 7):
		var base_x := vp_x + float(i) * 50.0 + scroll * 50.0
		var top_x := lerpf(vp_x, base_x, 0.15)
		var lc := grid_col
		lc.a = grid_col.a * (1.0 - absf(float(i)) / 7.0)
		draw_line(
			Vector2(top_x, horizon_y) + offset,
			Vector2(base_x, GROUND_Y) + offset,
			lc, 1.0
		)


func _draw_speed_lines(offset: Vector2) -> void:
	var intensity := clampf((_speed - BASE_SPEED) / (MAX_SPEED - BASE_SPEED), 0.0, 1.0)
	var base_alpha := maxf(intensity, 0.08)
	for line in _speed_lines:
		var spd: float = float(line["speed"])
		var alpha: float = base_alpha * spd * 0.4
		var length: float = 15.0 + intensity * 80.0 * spd
		var col := _get_distance_color()
		col.a = alpha
		draw_line(
			Vector2(line["x"], line["y"]) + offset,
			Vector2(line["x"] + length, line["y"]) + offset,
			col, 1.0 + intensity
		)


func _draw_ground(offset: Vector2) -> void:
	var ground_col := _get_distance_color() * 0.8
	ground_col.a = 0.95
	var pulse_bright := 1.0 + _ground_pulse * 0.5
	var gc := ground_col * pulse_bright
	gc.a = ground_col.a

	# Main line
	draw_line(Vector2(0, GROUND_Y) + offset, Vector2(_viewport_size.x, GROUND_Y) + offset, gc, 3.0)

	# Glow
	var glow := gc
	glow.a = 0.2 + _ground_pulse * 0.15
	draw_line(Vector2(0, GROUND_Y + 1) + offset, Vector2(_viewport_size.x, GROUND_Y + 1) + offset, glow, 8.0)

	# Ticks
	var tick_col := gc * 0.4
	tick_col.a = 0.35
	var x := -_ground_offset
	while x < _viewport_size.x + 40:
		draw_line(Vector2(x, GROUND_Y) + offset, Vector2(x - 12, GROUND_Y + 25) + offset, tick_col, 1.0)
		x += 40.0

	# Fill below
	draw_rect(Rect2(offset.x, GROUND_Y + offset.y, _viewport_size.x, 100), Color(0.03, 0.02, 0.05))


func _draw_obstacles(offset: Vector2) -> void:
	for obs in _obstacles:
		var col := _get_distance_color().lightened(0.35)
		col.a = 0.95
		match obs["type"]:
			"spike":
				var h: float = obs["height"]
				var w: float = obs["width"]
				var tip := Vector2(obs["x"] + w * 0.5, GROUND_Y - h) + offset
				var bl := Vector2(obs["x"], GROUND_Y) + offset
				var br := Vector2(obs["x"] + w, GROUND_Y) + offset
				var pts := PackedVector2Array([tip, bl, br])
				draw_colored_polygon(pts, col * 0.35)
				draw_line(tip, bl, col, 2.0, true)
				draw_line(tip, br, col, 2.0, true)
				draw_line(bl, br, col, 2.0, true)
				# Tip glow
				var tg := col
				tg.a = 0.3
				draw_circle(tip, 6.0, tg)

			"wall":
				var h: float = obs["height"]
				var w: float = obs["width"]
				var rect := Rect2(Vector2(obs["x"], GROUND_Y - h) + offset, Vector2(w, h))
				draw_rect(rect, col * 0.25)
				draw_rect(rect, col, false, 2.0)
				# Top glow
				var eg := col
				eg.a = 0.2
				draw_line(rect.position, rect.position + Vector2(w, 0), eg, 5.0)


func _draw_afterimages(offset: Vector2) -> void:
	var col := _get_distance_color()
	for ai in _afterimages:
		var alpha: float = clampf(float(ai["life"]) / 0.2, 0.0, 1.0) * 0.2
		var center := Vector2(float(ai["x"]), float(ai["y"])) + offset
		var rot: float = ai["rot"]
		var half := CUBE_SIZE * 0.45
		var xf := Transform2D(
			Vector2(cos(rot), sin(rot)) * half,
			Vector2(-sin(rot), cos(rot)) * half,
			center
		)
		var corners := PackedVector2Array([
			xf * Vector2(-1, -1), xf * Vector2(1, -1),
			xf * Vector2(1, 1), xf * Vector2(-1, 1),
		])
		var ac := col
		ac.a = alpha
		draw_colored_polygon(corners, ac)


func _draw_cube(offset: Vector2) -> void:
	if _state == State.DEAD and _death_timer < 0.5:
		return

	var center := Vector2(_cube_x + CUBE_SIZE * 0.5, _cube_y + CUBE_SIZE * 0.5) + offset
	var col := _get_distance_color()
	var half_x := CUBE_SIZE * 0.5 / _squash
	var half_y := CUBE_SIZE * 0.5 * _squash

	var xf := Transform2D(
		Vector2(cos(_rotation), sin(_rotation)),
		Vector2(-sin(_rotation), cos(_rotation)),
		center
	)

	var corners := PackedVector2Array([
		xf * Vector2(-half_x, -half_y) + center - xf.origin,
		xf * Vector2(half_x, -half_y) + center - xf.origin,
		xf * Vector2(half_x, half_y) + center - xf.origin,
		xf * Vector2(-half_x, half_y) + center - xf.origin,
	])

	# Actually let me simplify the transform
	corners = PackedVector2Array()
	for pt in [Vector2(-half_x, -half_y), Vector2(half_x, -half_y), Vector2(half_x, half_y), Vector2(-half_x, half_y)]:
		var rotated := Vector2(
			pt.x * cos(_rotation) - pt.y * sin(_rotation),
			pt.x * sin(_rotation) + pt.y * cos(_rotation),
		)
		corners.append(center + rotated)

	# Outer glow
	var glow_corners := PackedVector2Array()
	for c in corners:
		glow_corners.append(center + (c - center) * 1.5)
	var gc := col
	gc.a = 0.1
	draw_colored_polygon(glow_corners, gc)

	# Fill
	draw_colored_polygon(corners, col * 0.55)

	# Outline
	for j in range(4):
		draw_line(corners[j], corners[(j + 1) % 4], col, 2.5, true)

	# Center dot
	draw_circle(center, 2.5, Color(1, 1, 1, 0.7))


func _draw_particles(offset: Vector2) -> void:
	for p in _particles:
		var alpha: float = clampf(float(p["life"]) / float(p["max_life"]), 0.0, 1.0)
		var col: Color = p["color"]
		col.a = alpha
		var size: float = float(p["size"]) * (0.5 + alpha * 0.5)
		draw_rect(
			Rect2(Vector2(p["x"] - size * 0.5, p["y"] - size * 0.5) + offset, Vector2(size, size)),
			col
		)


func _draw_float_texts(offset: Vector2) -> void:
	var font := ThemeDB.fallback_font
	for ft in _float_texts:
		var alpha: float = clampf(float(ft["life"]) / float(ft["max_life"]), 0.0, 1.0)
		var col: Color = ft["color"]
		col.a = alpha
		var text: String = ft["text"]
		var sc: float = float(ft["scale"])
		var fsize := int(18.0 * sc) if "CLOSE" not in text and "MINI" not in text and "MINOR" not in text and "MAJOR" not in text and "JACKPOT" not in text else int(26.0 * sc)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
		draw_string(font, Vector2(ft["x"] - tw * 0.5, ft["y"]) + offset, text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, col)


func _draw_countdown() -> void:
	var font := ThemeDB.fallback_font
	var phase := _countdown_timer - floorf(_countdown_timer)
	var scale := 1.0 + (1.0 - phase) * 0.3
	var col := Color(1, 1, 1, clampf(phase, 0.4, 1.0))
	if _countdown_text == "GO!":
		col = Color(0.2, 1.0, 0.4)
		scale = 1.2
	var fsize := int(72.0 * scale)
	var tw := font.get_string_size(_countdown_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
	draw_string(font, Vector2(_viewport_size.x * 0.5 - tw * 0.5, _viewport_size.y * 0.38), _countdown_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, col)


func _draw_tier_markers(offset: Vector2) -> void:
	for tier in TIERS:
		var tier_dist: int = tier[0]
		if _score >= tier_dist:
			continue
		var tier_x: float = _cube_x + (tier_dist - _distance / 10.0) * 3.0
		if tier_x < 0 or tier_x > _viewport_size.x + 50:
			continue
		var col: Color = tier[2]
		col.a = 0.3
		draw_dashed_line(Vector2(tier_x, 60) + offset, Vector2(tier_x, GROUND_Y) + offset, col, 1.0, 8.0)
		var font := ThemeDB.fallback_font
		var lc := col
		lc.a = 0.55
		draw_string(font, Vector2(tier_x + 5, 75) + offset, tier[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, lc)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_distance_color() -> Color:
	var t := clampf(_distance / 12000.0, 0.0, 1.0)
	if t < 0.25:
		return Color(0.0, 0.85, 1.0).lerp(Color(0.3, 0.5, 1.0), t / 0.25)
	elif t < 0.5:
		return Color(0.3, 0.5, 1.0).lerp(Color(0.8, 0.2, 1.0), (t - 0.25) / 0.25)
	elif t < 0.75:
		return Color(0.8, 0.2, 1.0).lerp(Color(1.0, 0.4, 0.3), (t - 0.5) / 0.25)
	else:
		return Color(1.0, 0.4, 0.3).lerp(Color(1.0, 0.85, 0.0), (t - 0.75) / 0.25)


func _get_reached_tier() -> Array:
	for i in range(TIERS.size() - 1, -1, -1):
		if _score >= TIERS[i][0]:
			return TIERS[i]
	return []


func _update_tier_hud() -> void:
	var next: Array = []
	for tier in TIERS:
		if _score < tier[0]:
			next = tier
			break
	if next.is_empty():
		_tier_label.text = "ALL TIERS!"
		_tier_label.modulate = Color.GOLD
	else:
		var remaining: int = next[0] - _score
		_tier_label.text = "%s in %dm" % [next[1], remaining]
		_tier_label.modulate = next[2] if remaining < 200 else Color.WHITE


# ── State management ──────────────────────────────────────────────────────────

func _set_state(new_state: State) -> void:
	_state = new_state
	_connecting_label.visible = new_state in [State.CONNECTING, State.TAP_TO_START]
	_menu_panel.visible = new_state == State.MENU
	_hud.visible = new_state in [State.PLAYING, State.DEAD, State.COUNTDOWN]
	_game_over_panel.visible = new_state == State.GAME_OVER

	if new_state == State.TAP_TO_START:
		_connecting_label.text = "TAP TO START"


func _start_game() -> void:
	_cube_y = GROUND_Y - CUBE_SIZE
	_vel_y = 0.0
	_on_ground = true
	_was_on_ground = true
	_jumps_queued = false
	_rotation = 0.0
	_squash = 1.0
	_afterimages.clear()
	_speed = BASE_SPEED
	_distance = 0.0
	_score = 0
	_obstacles_passed = 0
	_last_tier_reached = -1
	_obstacles.clear()
	_particles.clear()
	_float_texts.clear()
	_ground_offset = 0.0
	_grid_offset = 0.0
	_shake = 0.0
	_flash_alpha = 0.0
	_bg_pulse = 0.0
	_ground_pulse = 0.0

	_dist_label.text = "0m"
	_speed_label.text = "%d km/h" % int(BASE_SPEED * 0.36)
	_update_tier_hud()

	_countdown_timer = 3.3
	_countdown_text = "3"
	_set_state(State.COUNTDOWN)
	if not _free_play:
		Luxodd.level_begin(1)


func _on_play_pressed() -> void:
	_sfx.play("menu_select")
	if _free_play:
		_start_game()
		return
	_play_button.disabled = true
	_cost_label.text = "Charging..."
	Luxodd.charge_balance(PLAY_COST, 1234)


func _on_play_again_pressed() -> void:
	if _free_play:
		_play_button.disabled = false
		_balance_label.text = "FREE PLAY"
		_cost_label.text = "No server — free play mode"
	else:
		_balance_label.text = "%d credits" % _balance
		_play_button.disabled = _balance < PLAY_COST
		_cost_label.text = "Costs %d credits" % PLAY_COST if _balance >= PLAY_COST else "Not enough credits"
	_set_state(State.MENU)


# ── Luxodd ────────────────────────────────────────────────────────────────────

func _on_connected() -> void:
	Luxodd.notify_game_ready()
	Luxodd.start_health_check()
	# Need a user tap to unlock web audio
	_set_state(State.TAP_TO_START)

func _on_connection_failed(_error: String) -> void:
	_free_play = true
	_set_state(State.TAP_TO_START)

func _on_profile(profile: Dictionary) -> void:
	_username = profile.get("name", profile.get("username", "Player"))
	_welcome_label.text = "Welcome, %s" % _username

func _on_balance(balance_data: Dictionary) -> void:
	_balance = int(balance_data.get("balance", 0))
	_balance_label.text = "%d credits" % _balance
	_play_button.disabled = _balance < PLAY_COST
	_cost_label.text = "Costs %d credits" % PLAY_COST if _balance >= PLAY_COST else "Not enough credits (%d needed)" % PLAY_COST

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
		var hl := "> " if uname == _username else "  "
		_leaderboard_list.append_text("%s%d. %s  %dm\n" % [hl, rank, uname, sc])

func _on_command_error(command: String, _code: int, _message: String) -> void:
	if command == "ChargeUserBalanceRequest":
		_cost_label.text = "Payment failed!"
		_play_button.disabled = false

func _on_host_action(action: String) -> void:
	match action:
		"restart":
			_start_game()
		"continue":
			_start_game()
		"end":
			Luxodd.notify_session_end()

func _apply_theme() -> void:
	_connecting_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	_connecting_label.add_theme_font_size_override("font_size", 20)
	_dist_label.add_theme_font_size_override("font_size", 28)
	_speed_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.7))
	_speed_label.add_theme_font_size_override("font_size", 14)
	_tier_label.add_theme_font_size_override("font_size", 16)
	var title_node: Label = %MenuPanel.get_node("VBox/Title")
	title_node.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	title_node.add_theme_font_size_override("font_size", 42)
	var sub_node: Label = %MenuPanel.get_node("VBox/Subtitle")
	sub_node.add_theme_color_override("font_color", Color(0.4, 0.4, 0.6))
	sub_node.add_theme_font_size_override("font_size", 14)
	_welcome_label.add_theme_font_size_override("font_size", 18)
	_balance_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_balance_label.add_theme_font_size_override("font_size", 24)
	_play_button.add_theme_font_size_override("font_size", 24)
	_cost_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	_cost_label.add_theme_font_size_override("font_size", 13)
	_result_title.add_theme_font_size_override("font_size", 34)
	_final_dist_label.add_theme_font_size_override("font_size", 28)
	_tier_result_label.add_theme_font_size_override("font_size", 16)
	_play_again_button.add_theme_font_size_override("font_size", 18)

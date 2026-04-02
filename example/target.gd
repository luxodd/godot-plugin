extends Area2D

## A clickable target that shrinks over its lifetime then disappears.
## Emits scored when clicked, missed when it expires.

signal scored(points: int)
signal missed()

const RADIUS := 32.0

var points: int = 100
var lifetime: float = 2.0
var _age: float = 0.0
var _base_scale: Vector2
var _color: Color


func _ready() -> void:
	_base_scale = scale
	input_pickable = true
	_color = Color.from_hsv(randf(), 0.75, 1.0)
	queue_redraw()


func _draw() -> void:
	# Outer ring
	draw_circle(Vector2.ZERO, RADIUS, _color)
	# Inner highlight
	draw_circle(Vector2.ZERO, RADIUS * 0.6, _color.lightened(0.3))
	# Center dot
	draw_circle(Vector2.ZERO, RADIUS * 0.2, Color.WHITE)


func _process(delta: float) -> void:
	_age += delta
	var t := _age / lifetime

	if t >= 1.0:
		missed.emit()
		queue_free()
		return

	# Shrink as it ages
	var s := lerpf(1.0, 0.3, t)
	scale = _base_scale * s

	# Gentle float upward
	position.y -= 15.0 * delta

	# Flash when about to expire
	if t > 0.7:
		modulate.a = 0.5 + 0.5 * sin(_age * 12.0)


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pop()


func _pop() -> void:
	var time_bonus := int((1.0 - _age / lifetime) * 50.0)
	scored.emit(points + time_bonus)
	_spawn_pop_particles()
	queue_free()


func _spawn_pop_particles() -> void:
	var particles := CPUParticles2D.new()
	particles.position = global_position
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 12
	particles.lifetime = 0.4
	particles.explosiveness = 1.0
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.initial_velocity_min = 80.0
	particles.initial_velocity_max = 160.0
	particles.gravity = Vector2(0, 200)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = _color
	get_parent().add_child(particles)
	get_tree().create_timer(0.5).timeout.connect(particles.queue_free)

extends RigidBody2D


@export var speed := 300.0
@export var color_change_duration := 0.3
@export var colors: Array[Color] = [
	Color.RED,
	Color.ORANGE,
	Color.YELLOW,
	Color.GREEN,
	Color.BLUE,
	Color.INDIGO,
	Color.VIOLET,
]

var _direction := Vector2.RIGHT
var _start_color := Color.WHITE
var _current_color := Color.WHITE
var _target_color := Color.WHITE
var _color_elapsed := 0.0
var _changing_color := false

@onready var texture := $Texture as TextureRect
@onready var collision := $Collision as CollisionShape2D


func _ready() -> void:
	position = _random_position()
	_set_random_velocity()
	_current_color = _random_color()
	texture.self_modulate = _current_color
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if not _changing_color:
		return

	_color_elapsed = minf(_color_elapsed + delta, color_change_duration)
	var weight := _color_elapsed / color_change_duration
	_current_color = _start_color.lerp(_target_color, weight)
	texture.self_modulate = _current_color

	if weight == 1.0:
		_changing_color = false


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if state.linear_velocity.length_squared() > 0.001:
		_direction = state.linear_velocity.normalized()

	state.linear_velocity = _direction * speed
	state.angular_velocity = 0.0


func _set_random_velocity() -> void:
	_direction = Vector2.RIGHT.rotated(randf() * TAU)
	linear_velocity = _direction * speed


func _random_position() -> Vector2:
	var bounds := Game.instance.world_bounds
	var radius := (collision.shape as CircleShape2D).radius
	var minimum := bounds.position + Vector2.ONE * radius
	var maximum := bounds.end - Vector2.ONE * radius
	return Vector2(
		randf_range(minimum.x, maximum.x),
		randf_range(minimum.y, maximum.y)
	)


func _on_body_entered(_body: Node) -> void:
	_start_color = _current_color
	_target_color = _random_color()
	_color_elapsed = 0.0
	_changing_color = true


func _random_color() -> Color:
	if colors.is_empty():
		return Color.WHITE
	if colors.size() == 1:
		return colors[0]

	var next_color: Color = colors.pick_random()
	while next_color == _current_color:
		next_color = colors.pick_random()
	return next_color

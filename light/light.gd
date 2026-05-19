extends RigidBody2D

const DIAGONAL_DIRECTIONS := [
	Vector2(-1, -1),
	Vector2(1, -1),
	Vector2(-1, 1),
	Vector2(1, 1),
]

@export var speed := 300.0
@export var color_change_duration := 0.3

var _direction := Vector2.ZERO
var _start_color := Color.WHITE
var _current_color := Color.WHITE
var _target_color := Color.WHITE
var _color_elapsed := 0.0
var _changing_color := false


func _ready() -> void:
	set_process(false)
	Fusion.room_joined.connect(_joined)
	%FusionSharedReplicator.authority_changed.connect(_on_authority_changed)


func _joined() -> void:
	Fusion.register_current_scene()
	_on_authority_changed(%FusionSharedReplicator.has_authority())

func _on_authority_changed(has_authority: bool) -> void:
	set_process(has_authority)
	%Collision.disabled = not has_authority
	
	if not has_authority:
		return
	
	_current_color = Game.instance.random_color()
	modulate = _current_color
	body_entered.connect(_on_body_entered)

	_set_random_velocity()


func _process(delta: float) -> void:
	if not _changing_color:
		return

	_color_elapsed = minf(_color_elapsed + delta, color_change_duration)
	var weight := _color_elapsed / color_change_duration
	_current_color = _start_color.lerp(_target_color, weight)
	modulate = _current_color

	if weight == 1.0:
		_changing_color = false


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _direction == Vector2.ZERO:
		return
	
	if state.linear_velocity.length_squared() > 0.001:
		_direction = state.linear_velocity.normalized()

	state.linear_velocity = _direction * speed
	state.angular_velocity = 0.0


func _set_random_velocity() -> void:
	_direction = DIAGONAL_DIRECTIONS.pick_random().normalized()
	linear_velocity = _direction * speed


func _on_body_entered(__) -> void:
	_start_color = _current_color
	_target_color = Game.instance.random_color(_current_color)
	_color_elapsed = 0.0
	_changing_color = true

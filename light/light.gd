extends RigidBody2D

const DIAGONAL_DIRECTIONS := [
	Vector2(-1, -1),
	Vector2(1, -1),
	Vector2(-1, 1),
	Vector2(1, 1),
]

const LIGHT_SYNC_RATE_SAMPLE_INTERVAL := 1.0

@export var speed := 300.0
@export var color_change_duration := 0.3

var sync_probe: int:
	set(value):
		_sync_probe = value
		if not has_authority:
			_sync_down_samples += 1
	get:
		return _sync_probe

var has_authority: bool:
	get:
		return _has_authority_safe()

var _direction := Vector2.ZERO
var _start_color := Color.WHITE
var _current_color := Color.WHITE
var _target_color := Color.WHITE
var _color_elapsed := 0.0
var _changing_color := false
var _last_has_authority := -1
var _sync_probe := 0
var _sync_up_samples := 0
var _sync_down_samples := 0
var _sync_up_rate := 0.0
var _sync_down_rate := 0.0
var _sync_rate_elapsed := 0.0

@onready var _stats_label: Label = %StatsLabel


func _ready() -> void:
	set_process(true)
	Fusion.room_joined.connect(_joined)
	Fusion.player_left.connect(_on_fusion_player_left)
	%FusionSharedReplicator.authority_changed.connect(_on_authority_changed)
	_update_stats_label()


func _joined() -> void:
	Fusion.register_current_scene()
	_on_authority_changed(%FusionSharedReplicator.has_authority())


func _on_fusion_player_left(_player_id: int, _is_inactive: bool) -> void:
	_on_authority_changed(has_authority)


func _on_authority_changed(current_authority: bool) -> void:
	var current_has_authority := int(current_authority)
	if _last_has_authority == current_has_authority:
		return

	_last_has_authority = current_has_authority

	set_process(true)
	%Collision.disabled = not current_authority
	_update_stats_label()
	
	if not current_authority:
		if body_entered.is_connected(_on_body_entered):
			body_entered.disconnect(_on_body_entered)
		return
	
	_current_color = Game.instance.random_color()
	modulate = _current_color
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	_set_random_velocity()


func _process(delta: float) -> void:
	if has_authority:
		sync_probe = _sync_probe + 1
		_sync_up_samples += 1

	_sync_rate_elapsed += delta
	if _sync_rate_elapsed >= LIGHT_SYNC_RATE_SAMPLE_INTERVAL:
		_sync_up_rate = _sync_up_samples / _sync_rate_elapsed
		_sync_down_rate = _sync_down_samples / _sync_rate_elapsed
		_sync_up_samples = 0
		_sync_down_samples = 0
		_sync_rate_elapsed = 0.0
		_update_stats_label()

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


func _update_stats_label() -> void:
	var lines := ["id %s" % _format_owner_id()]
	lines.append("local" if has_authority else "remote")
	lines.append(_format_sync_direction_rate())
	_stats_label.text = "\n".join(lines)


func _get_owner_id() -> int:
	return int(%FusionSharedReplicator.get_owner_id())


func _format_owner_id() -> String:
	var owner_id := _get_owner_id()
	return str(owner_id) if owner_id > 0 else "-"


func _format_sync_direction_rate() -> String:
	if has_authority:
		return "up %.1f Hz" % _sync_up_rate

	return "down %.1f Hz" % _sync_down_rate


func _has_authority_safe() -> bool:
	var replicator := get_node_or_null("FusionSharedReplicator") as FusionReplicator
	return replicator != null and replicator.has_authority()

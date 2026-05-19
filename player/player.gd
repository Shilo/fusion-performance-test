class_name Player extends CharacterBody2D

const GROUP_PLAYERS := "players"
const MANUAL_SYNC_RATE_SAMPLE_INTERVAL := 1.0

@export var speed := 300.0

var manual_sync_probe: int:
	set(value):
		_manual_sync_set_calls += 1
		_manual_sync_probe = value
	get:
		_manual_sync_get_calls += 1
		return _manual_sync_probe

var extents: Vector2:
	get:
		if extents == Vector2():
			extents = %Sprite.get_rect().size / 2
		return extents

var has_authority: bool:
	get:
		return %FusionSharedReplicator.has_authority()

var _manual_sync_probe := 0
var _manual_sync_get_calls := 0
var _manual_sync_set_calls := 0
var _manual_sync_get_rate := 0.0
var _manual_sync_set_rate := 0.0
var _manual_sync_rate_elapsed := 0.0

@onready var _call_rate_label: Label = %CallRateLabel


func _enter_tree() -> void:
	add_to_group(GROUP_PLAYERS)


func _ready() -> void:
	set_process(true)
	set_physics_process(has_authority)
	_update_call_rate_label()
	
	if has_authority:
		modulate = Game.instance.random_color()
		z_index += 1


func _process(delta: float) -> void:
	if has_authority:
		manual_sync_probe = _manual_sync_probe + 1

	_manual_sync_rate_elapsed += delta
	if _manual_sync_rate_elapsed >= MANUAL_SYNC_RATE_SAMPLE_INTERVAL:
		_manual_sync_get_rate = _manual_sync_get_calls / _manual_sync_rate_elapsed
		_manual_sync_set_rate = _manual_sync_set_calls / _manual_sync_rate_elapsed
		_manual_sync_get_calls = 0
		_manual_sync_set_calls = 0
		_manual_sync_rate_elapsed = 0.0
		_update_call_rate_label()


func _physics_process(__) -> void:
	velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * speed
	move_and_slide()


func _update_call_rate_label() -> void:
	var lines := []
	if _is_master_player():
		lines.append("master")

	var role := "local" if has_authority else "remote"
	lines.append("id %s" % _format_owner_id())
	lines.append(role)
	lines.append("get %.1f/s set %.1f/s" % [
		_manual_sync_get_rate,
		_manual_sync_set_rate,
	])
	lines.append("snap %s" % _format_snapshot_delay())
	_call_rate_label.text = "\n".join(lines)


func _is_master_player() -> bool:
	var owner_id := _get_owner_id()
	if owner_id <= 0 or not Fusion.is_in_room():
		return false

	var room: FusionRoom = Fusion.get_room()
	if room == null:
		return false

	return owner_id == int(room.get_master_client_id())


func _get_owner_id() -> int:
	return int(%FusionSharedReplicator.get_owner_id())


func _format_owner_id() -> String:
	var owner_id := _get_owner_id()
	return str(owner_id) if owner_id > 0 else "-"


func _format_snapshot_delay() -> String:
	var delay := float(%FusionSharedReplicator.get_snapshot_current_delay())
	if delay > 0.0 and delay < 1.0:
		return "%.0f ms" % (delay * 1000.0)
	return "%.2f s" % delay

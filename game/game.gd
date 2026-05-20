class_name Game extends Node

static var instance: Game

@export var player_scene: PackedScene
@onready var world: Node2D = %World
@onready var ui: UI = %UI

var _world_bounds := Rect2()

var world_bounds: Rect2:
	get:
		if _world_bounds == Rect2():
			_world_bounds = get_viewport().get_visible_rect()
		return _world_bounds


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.connected_to_photon.connect(_on_connected)
	_connect.call_deferred()


func _connect() -> void:
	Fusion.connect_to_photon()


func _on_connected() -> void:
	Fusion.join_or_create_room("lobby")


func _on_room_joined() -> void:
	spawn_player()


func spawn_player() -> void:
	if not Fusion.is_in_room():
		return

	%FusionSpawner.spawn(null, func(__, player: Player) -> void:
		var bounds := get_player_spawn_bounds(player)
		player.global_position = Vector2(
			randf_range(bounds.position.x, bounds.end.x),
			randf_range(bounds.position.y, bounds.end.y)
		)
		ui.apply_player_network_settings(player)
	)


func get_player_spawn_bounds(player: Player) -> Rect2:
	return Rect2(world_bounds.position + player.extents, world_bounds.size - player.extents * 2)


func random_color(excluded_color := Color.TRANSPARENT) -> Color:
	const COLORS := [
		Color(1.0, 0.35, 0.55), # Red
		Color(0.95, 0.42, 0.0), # Orange
		Color(0.54, 0.54, 0.0), # Yellow
		Color(0.0, 0.68, 0.18), # Green
		Color(0.3, 0.51, 1.0),  # Blue
		Color(0.48, 0.45, 1.0), # Indigo
		Color(0.84, 0.35, 1.0), # Violet
	]

	var next_color: Color = COLORS.pick_random()
	while next_color == excluded_color:
		next_color = COLORS.pick_random()
	return next_color

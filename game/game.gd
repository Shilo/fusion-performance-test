class_name Game extends Node

static var instance: Game

@export var player_scene: PackedScene
@onready var world: Node2D = %World


var world_bounds: Rect2:
	get:
		if world_bounds == Rect2():
			world_bounds = get_viewport().get_visible_rect()
		return world_bounds


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	_spawn_player()


func _spawn_player() -> void:
	var player: Player = player_scene.instantiate()
	world.add_child(player)

	var bounds := get_player_spawn_bounds(player)
	player.position = Vector2(
		randf_range(bounds.position.x, bounds.end.x),
		randf_range(bounds.position.y, bounds.end.y)
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

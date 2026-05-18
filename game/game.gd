class_name Game extends Node

static var instance: Game
const LIGHT_WALL_COLLISION_LAYER := 2
const WALL_THICKNESS := 64.0

@export var player_scene: PackedScene
@onready var world := %World


var world_bounds: Rect2:
	get:
		if world_bounds == Rect2():
			world_bounds = get_viewport().get_visible_rect()
		return world_bounds



func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	_spawn_world_walls()
	_spawn_player()


func _spawn_player() -> void:
	var player: Player = player_scene.instantiate()
	world.add_child(player)
	
	var bounds = get_player_world_bounds(player)
	player.position = Vector2(
		randf_range(bounds.position.x, bounds.end.x),
		randf_range(bounds.position.y, bounds.end.y)
	)


func _spawn_world_walls() -> void:
	var bounds := world_bounds
	_spawn_wall("TopWall", Rect2(
		bounds.position - Vector2(WALL_THICKNESS, WALL_THICKNESS),
		Vector2(bounds.size.x + WALL_THICKNESS * 2, WALL_THICKNESS)
	))
	_spawn_wall("BottomWall", Rect2(
		Vector2(bounds.position.x - WALL_THICKNESS, bounds.end.y),
		Vector2(bounds.size.x + WALL_THICKNESS * 2, WALL_THICKNESS)
	))
	_spawn_wall("LeftWall", Rect2(
		bounds.position - Vector2(WALL_THICKNESS, 0),
		Vector2(WALL_THICKNESS, bounds.size.y)
	))
	_spawn_wall("RightWall", Rect2(
		Vector2(bounds.end.x, bounds.position.y),
		Vector2(WALL_THICKNESS, bounds.size.y)
	))


func _spawn_wall(wall_name: String, rect: Rect2) -> void:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.collision_layer = LIGHT_WALL_COLLISION_LAYER
	wall.collision_mask = LIGHT_WALL_COLLISION_LAYER
	wall.position = rect.get_center()

	var shape := RectangleShape2D.new()
	shape.size = rect.size

	var collision := CollisionShape2D.new()
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)


func get_player_world_bounds(player: Player) -> Rect2:
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
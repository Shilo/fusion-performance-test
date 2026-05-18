class_name Game extends Node

@export var player_scene: PackedScene
@onready var world := %World


var world_bounds: Rect2:
	get:
		if world_bounds == Rect2():
			world_bounds = get_viewport().get_visible_rect()
		return world_bounds


func get_player_world_bounds(player: Player) -> Rect2:
	return Rect2(world_bounds.position + player.sprite_extends, world_bounds.size - player.sprite_extends * 2)


func _ready() -> void:
	_spawn_player()


func _spawn_player() -> void:
	var player: Player = player_scene.instantiate()
	world.add_child(player)
	
	var bounds = get_player_world_bounds(player)
	player.position = Vector2(
		randf_range(bounds.position.x, bounds.end.x),
		randf_range(bounds.position.y, bounds.end.y)
	)

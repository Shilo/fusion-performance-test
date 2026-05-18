class_name Player extends CharacterBody2D

@export var speed := 300.0
@onready var sprite_extends: Vector2 = %Sprite.get_rect().size / 2


var game: Game:
	get:
		return get_tree().current_scene


func _physics_process(__) -> void:
	velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * speed
	move_and_slide()
	
	var bounds := game.get_player_world_bounds(self)
	position = position.clamp(bounds.position, bounds.end)

class_name Player extends CharacterBody2D

@export var speed := 300.0
@onready var extents: Vector2 = %Sprite.get_rect().size / 2


func _physics_process(__) -> void:
	velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * speed
	move_and_slide()
	
	var bounds := Game.instance.get_player_world_bounds(self)
	position = position.clamp(bounds.position, bounds.end)

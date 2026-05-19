class_name Player extends CharacterBody2D

@export var speed := 300.0

var extents: Vector2:
	get:
		if extents == Vector2():
			extents = %Sprite.get_rect().size / 2
		return extents

var has_authority: bool:
	get:
		return %FusionSharedReplicator.has_authority()


func _ready() -> void:
	set_physics_process(has_authority)
	
	if has_authority:
		modulate = Game.instance.random_color()
		z_index += 1


func _physics_process(__) -> void:
	velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * speed
	move_and_slide()

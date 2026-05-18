class_name Player extends CharacterBody2D

@export var speed := 300.0
@onready var extents: Vector2 = %Sprite.get_rect().size / 2


func _ready() -> void:
	modulate = Game.instance.random_color()


func _physics_process(__) -> void:
	velocity = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * speed
	move_and_slide()

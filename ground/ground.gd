class_name Ground extends TextureRect


var _start_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _start_color := Color.WHITE
var _target_color := Color.WHITE
var _elapsed := 0.0
var _moving := false
var _move_timer: Timer

var gradient_texture: GradientTexture2D:
	get:
		return texture as GradientTexture2D

var gradient: Gradient:
	get:
		return gradient_texture.gradient


func _ready() -> void:
	_move_timer = Timer.new()
	_move_timer.wait_time = 1
	_move_timer.timeout.connect(move_to_random)
	add_child(_move_timer)
	
	_move_timer.start()
	move_to_random()


func _process(delta: float) -> void:
	if not _moving:
		return

	var duration := _move_timer.wait_time
	_elapsed = minf(_elapsed + delta, duration)
	var weight := _elapsed / duration
	gradient_texture.fill_from = _start_position.lerp(_target_position, weight)
	gradient.set_color(0, _start_color.lerp(_target_color, weight))

	if weight == 1.0:
		_moving = false


func move_to(target_position: Vector2, target_color: Color) -> void:
	_start_position = gradient_texture.fill_from
	_target_position = target_position.clamp(Vector2.ZERO, Vector2.ONE)
	_start_color = gradient.get_color(0)
	_target_color = target_color
	_elapsed = 0.0
	_moving = true


func move_to_random() -> void:
	move_to(Vector2(randf(), randf()), Color(randf(), randf(), randf()))

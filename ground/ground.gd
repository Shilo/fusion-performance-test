class_name Ground extends TextureRect


@export var radius := 100.0

var _start_position := Vector2.ZERO
var _current_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _start_color := Color.WHITE
var _current_color := Color.WHITE
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
	_current_position = _clamp_center(Game.instance.world_bounds.get_center())
	_target_position = _current_position
	_update_gradient()

	_move_timer = Timer.new()
	_move_timer.wait_time = 1
	_move_timer.timeout.connect(move_to_random)
	add_child(_move_timer)

	_move_timer.start()
	move_to_random()


func _process(delta: float) -> void:
	_current_position = _clamp_center(_current_position)
	_target_position = _clamp_center(_target_position)

	if not _moving:
		_update_gradient()
		return

	var duration := _move_timer.wait_time
	_elapsed = minf(_elapsed + delta, duration)
	var weight := _elapsed / duration
	_current_position = _clamp_center(_start_position.lerp(_target_position, weight))
	_current_color = _start_color.lerp(_target_color, weight)
	_update_gradient()

	if weight == 1.0:
		_moving = false


func move_to(target_position: Vector2, target_color: Color) -> void:
	_start_position = _current_position
	_target_position = _clamp_center(target_position)
	_start_color = _current_color
	_target_color = target_color
	_elapsed = 0.0
	_moving = true


func move_to_random() -> void:
	var bounds := _center_bounds()
	move_to(
		Vector2(
			randf_range(bounds.position.x, bounds.end.x),
			randf_range(bounds.position.y, bounds.end.y)
		),
		Color(randf(), randf(), randf())
	)


func _center_bounds() -> Rect2:
	var bounds := Game.instance.world_bounds
	var minimum := bounds.position + Vector2.ONE * radius
	var maximum := bounds.end - Vector2.ONE * radius
	if maximum.x < minimum.x:
		minimum.x = bounds.get_center().x
		maximum.x = minimum.x
	if maximum.y < minimum.y:
		minimum.y = bounds.get_center().y
		maximum.y = minimum.y
	return Rect2(minimum, maximum - minimum)


func _clamp_center(center: Vector2) -> Vector2:
	var bounds := _center_bounds()
	return center.clamp(bounds.position, bounds.end)


func _update_gradient() -> void:
	var local_center := _current_position - Game.instance.world_bounds.position
	var texture_size := float(gradient_texture.width)
	gradient_texture.fill_from = local_center / texture_size
	gradient_texture.fill_to = gradient_texture.fill_from + Vector2(radius / texture_size, 0.0)
	gradient.set_color(0, _current_color)

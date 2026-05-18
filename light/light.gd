extends TextureRect


var _start_center := Vector2.ZERO
var _current_center := Vector2.ZERO
var _target_center := Vector2.ZERO
var _start_color := Color.WHITE
var _current_color := Color.WHITE
var _target_color := Color.WHITE
var _elapsed := 0.0
var _moving := false
var _move_timer: Timer


func _ready() -> void:
	_current_center = _clamp_center(Game.instance.world_bounds.get_center())
	_target_center = _current_center
	_update_light()

	_move_timer = Timer.new()
	_move_timer.wait_time = 1
	_move_timer.timeout.connect(move_to_random)
	add_child(_move_timer)

	_move_timer.start()
	move_to_random()


func _process(delta: float) -> void:
	_current_center = _clamp_center(_current_center)
	_target_center = _clamp_center(_target_center)

	if not _moving:
		return

	var duration := _move_timer.wait_time
	_elapsed = minf(_elapsed + delta, duration)
	var weight := _elapsed / duration
	_current_center = _clamp_center(_start_center.lerp(_target_center, weight))
	_current_color = _start_color.lerp(_target_color, weight)
	_update_light()

	if weight == 1.0:
		_moving = false


func move_to(target_center: Vector2, target_color: Color) -> void:
	_start_center = _current_center
	_target_center = _clamp_center(target_center)
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
	var extents := size / 2
	var minimum := bounds.position + extents
	var maximum := bounds.end - extents
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


func _update_light() -> void:
	position = _current_center - size / 2
	self_modulate = _current_color

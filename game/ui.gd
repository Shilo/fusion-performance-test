class_name UI extends CanvasLayer

const PLAYER_GROUP := "players"
const SAMPLE_INTERVAL := 1.0
const PLAYER_SCAN_INTERVAL := 0.25
const MOVEMENT_EPSILON_SQUARED := 0.0001
const ROTATION_EPSILON := 0.0001
const MONITOR_METHODS := {
	"sent_bps": &"_get_monitor_bps_sent",
	"recv_bps": &"_get_monitor_bps_recv",
	"sync_outbound_us": &"_get_monitor_sync_outbound_us",
	"sync_inbound_us": &"_get_monitor_sync_inbound_us",
	"service_us": &"_get_monitor_service_us",
	"update_us": &"_get_monitor_update_total_us",
}

var _labels := {}
var _tracked_players := {}
var _scan_elapsed := 0.0
var _sample_elapsed := 0.0
var _player_sync_up_samples := 0
var _player_sync_down_samples := 0
var _player_sync_up_hz := 0.0
var _player_sync_down_hz := 0.0
var _authority_player_count := 0
var _remote_player_count := 0


func _ready() -> void:
	_build_panel()
	_scan_players()
	_refresh_stats()


func _process(delta: float) -> void:
	_scan_elapsed += delta
	_sample_elapsed += delta

	if _scan_elapsed >= PLAYER_SCAN_INTERVAL:
		_scan_elapsed = 0.0
		_scan_players()

	if _sample_elapsed >= SAMPLE_INTERVAL:
		_player_sync_up_hz = _player_sync_up_samples / _sample_elapsed
		_player_sync_down_hz = _player_sync_down_samples / _sample_elapsed
		_player_sync_up_samples = 0
		_player_sync_down_samples = 0
		_sample_elapsed = 0.0
		_refresh_stats()


func _physics_process(_delta: float) -> void:
	for id in _tracked_players.keys():
		var tracker: Dictionary = _tracked_players[id]
		var player := _get_tracker_player(tracker)
		var replicator := _get_tracker_replicator(tracker)
		if player == null or replicator == null:
			_untrack_player(id)
			continue
		if not replicator.has_authority():
			continue

		var update_interval := maxi(1, replicator.get_update_interval())
		tracker["ticks_since_outbound_sample"] = int(tracker.get("ticks_since_outbound_sample", 0)) + 1
		if int(tracker["ticks_since_outbound_sample"]) < update_interval:
			_tracked_players[id] = tracker
			continue

		tracker["ticks_since_outbound_sample"] = 0
		if _player_state_changed(player, tracker):
			_player_sync_up_samples += 1
			_store_player_state(player, tracker)

		_tracked_players[id] = tracker


func _build_panel() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 12.0
	margin.offset_top = 12.0
	add_child(margin)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300.0, 0.0)
	margin.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.018, 0.022, 0.78)
	style.border_color = Color(0.25, 0.55, 0.9, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_left", 10)
	padding.add_theme_constant_override("margin_top", 8)
	padding.add_theme_constant_override("margin_right", 10)
	padding.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(padding)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	padding.add_child(layout)

	var title := Label.new()
	title.text = "Network"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0))
	layout.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	layout.add_child(grid)

	_add_row(grid, &"status", "Status")
	_add_row(grid, &"room", "Room")
	_add_row(grid, &"players", "Players")
	_add_row(grid, &"local_player", "Local")
	_add_row(grid, &"rtt", "RTT")
	_add_row(grid, &"network_time", "Net Time")
	_add_row(grid, &"traffic", "Traffic")
	_add_row(grid, &"fusion_sync", "Fusion Sync")
	_add_row(grid, &"fusion_loop", "Fusion Loop")
	_add_row(grid, &"player_sync_up", "Player Up")
	_add_row(grid, &"player_sync_down", "Player Down")


func _add_row(grid: GridContainer, key: StringName, label_text: String) -> void:
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size.x = 92.0
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.55, 0.64, 0.72))
	grid.add_child(name_label)

	var value_label := Label.new()
	value_label.text = "-"
	value_label.custom_minimum_size.x = 170.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	grid.add_child(value_label)
	_labels[key] = value_label


func _refresh_stats() -> void:
	_authority_player_count = 0
	_remote_player_count = 0
	for tracker in _tracked_players.values():
		var player := _get_tracker_player(tracker)
		var replicator := _get_tracker_replicator(tracker)
		if player == null or replicator == null:
			continue
		if replicator.has_authority():
			_authority_player_count += 1
		else:
			_remote_player_count += 1

	_set_label(&"status", _connection_status_text())
	_set_label(&"room", _room_text())
	_set_label(&"players", _players_text())
	_set_label(&"local_player", _local_player_text())
	_set_label(&"rtt", _format_rtt(_safe_fusion_call(&"get_rtt")))
	_set_label(&"network_time", "%.2f s" % float(_safe_fusion_call(&"get_network_time")))
	_set_label(&"traffic", "Up %s / Down %s" % [
		_format_bps(_fusion_monitor("sent_bps")),
		_format_bps(_fusion_monitor("recv_bps")),
	])
	_set_label(&"fusion_sync", "Out %.1f us / In %.1f us" % [
		_fusion_monitor("sync_outbound_us"),
		_fusion_monitor("sync_inbound_us"),
	])
	_set_label(&"fusion_loop", "Svc %.1f us / Upd %.1f us" % [
		_fusion_monitor("service_us"),
		_fusion_monitor("update_us"),
	])
	_set_label(&"player_sync_up", _format_sync_rate(_player_sync_up_hz, _authority_player_count))
	_set_label(&"player_sync_down", _format_sync_rate(_player_sync_down_hz, _remote_player_count))


func _scan_players() -> void:
	var seen := {}
	for player in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if player is Player:
			seen[player.get_instance_id()] = true
			_track_player(player)

	for id in _tracked_players.keys():
		var tracker: Dictionary = _tracked_players[id]
		var player := _get_tracker_player(tracker)
		if player == null or not seen.has(id):
			_untrack_player(id)


func _track_player(player: Player) -> void:
	var id := player.get_instance_id()
	if _tracked_players.has(id):
		return

	var replicator := player.get_node_or_null("FusionSharedReplicator") as FusionReplicator
	if replicator == null:
		return

	var tracker := {
		"player": player,
		"replicator": replicator,
		"ticks_since_outbound_sample": 0,
	}
	_store_player_state(player, tracker)

	var reset_callback := Callable(self, "_on_player_state_reset").bind(id)
	replicator.state_reset.connect(reset_callback)
	tracker["reset_callback"] = reset_callback

	_tracked_players[id] = tracker


func _untrack_player(id: int) -> void:
	if not _tracked_players.has(id):
		return

	var tracker: Dictionary = _tracked_players[id]
	var replicator := _get_tracker_replicator(tracker)
	var reset_callback: Callable = tracker.get("reset_callback", Callable())
	if replicator != null and reset_callback.is_valid() and replicator.state_reset.is_connected(reset_callback):
		replicator.state_reset.disconnect(reset_callback)

	_tracked_players.erase(id)


func _on_player_state_reset(_info: FusionStateResetInfo, id: int) -> void:
	if not _tracked_players.has(id):
		return

	var tracker: Dictionary = _tracked_players[id]
	var replicator := _get_tracker_replicator(tracker)
	if replicator != null and not replicator.has_authority():
		_player_sync_down_samples += 1


func _get_tracker_player(tracker: Dictionary) -> Player:
	var player = tracker.get("player")
	if not is_instance_valid(player):
		return null
	return player as Player


func _get_tracker_replicator(tracker: Dictionary) -> FusionReplicator:
	var replicator = tracker.get("replicator")
	if not is_instance_valid(replicator):
		return null
	return replicator as FusionReplicator


func _player_state_changed(player: Player, tracker: Dictionary) -> bool:
	var last_position: Vector2 = tracker.get("last_position", player.global_position)
	var last_velocity: Vector2 = tracker.get("last_velocity", player.velocity)
	var last_rotation := float(tracker.get("last_rotation", player.global_rotation))

	return (
		player.global_position.distance_squared_to(last_position) > MOVEMENT_EPSILON_SQUARED
		or player.velocity.distance_squared_to(last_velocity) > MOVEMENT_EPSILON_SQUARED
		or absf(angle_difference(player.global_rotation, last_rotation)) > ROTATION_EPSILON
	)


func _store_player_state(player: Player, tracker: Dictionary) -> void:
	tracker["last_position"] = player.global_position
	tracker["last_velocity"] = player.velocity
	tracker["last_rotation"] = player.global_rotation


func _connection_status_text() -> String:
	match int(_safe_fusion_call(&"get_connection_status")):
		FusionClient.STATUS_DISCONNECTED:
			return "Disconnected"
		FusionClient.STATUS_CONNECTING_TO_PHOTON:
			return "Connecting"
		FusionClient.STATUS_CONNECTED_TO_PHOTON:
			return "Connected"
		FusionClient.STATUS_JOINING_ROOM:
			return "Joining"
		FusionClient.STATUS_IN_ROOM:
			return "In Room"
		FusionClient.STATUS_ERROR:
			return "Error"
		_:
			return "Unknown"


func _room_text() -> String:
	if not Fusion.is_in_room():
		return "-"

	var room: FusionRoom = Fusion.get_room()
	if room == null:
		return "-"

	var max_players := room.get_max_players()
	var capacity := str(max_players) if max_players > 0 else "-"
	return "%s (%d/%s)" % [room.get_room_name(), room.get_player_count(), capacity]


func _players_text() -> String:
	return "%d tracked, %d local" % [_tracked_players.size(), _authority_player_count]


func _local_player_text() -> String:
	var local_id := int(_safe_fusion_call(&"get_local_player_id"))
	return str(local_id) if local_id > 0 else "-"


func _safe_fusion_call(method: StringName) -> Variant:
	if Fusion.has_method(method):
		return Fusion.call(method)
	return 0


func _fusion_monitor(key: String) -> float:
	var method: StringName = MONITOR_METHODS.get(key, &"")
	if method != &"" and Fusion.has_method(method):
		return maxf(0.0, float(Fusion.call(method)))
	return 0.0


func _format_bps(value: float) -> String:
	if value >= 1024.0 * 1024.0:
		return "%.2f MiB/s" % (value / (1024.0 * 1024.0))
	if value >= 1024.0:
		return "%.1f KiB/s" % (value / 1024.0)
	return "%d B/s" % int(roundf(value))


func _format_rtt(value: Variant) -> String:
	var rtt := maxf(0.0, float(value))
	if rtt > 0.0 and rtt < 1.0:
		rtt *= 1000.0
	return "%.0f ms" % rtt


func _format_sync_rate(total_hz: float, player_count: int) -> String:
	if player_count <= 0:
		return "0.0 Hz/player"

	return "%.1f Hz/player (%.1f total)" % [total_hz / player_count, total_hz]


func _set_label(key: StringName, value: String) -> void:
	var label: Label = _labels.get(key)
	if label != null:
		label.text = value

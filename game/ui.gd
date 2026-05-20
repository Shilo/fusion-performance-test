class_name UI extends CanvasLayer

const PLAYER_GROUP := "players"
const SAMPLE_INTERVAL := 1.0
const PLAYER_SCAN_INTERVAL := 0.25
const INTEREST_AREA_ROOM_PROPERTY := "interest_area_enabled"
const SYNC_RATE_ROOM_PROPERTY := "sync_update_interval"
const SYNC_UPDATE_INTERVALS := [1, 2, 4, 8]
const RPC_RATE_ROOM_PROPERTY := "rpc_probe_rate_hz"
const RPC_PROBE_RATES_HZ := [15, 30, 60]
const SMOOTHING_ROOM_PROPERTY := "smoothing_enabled"
const ACTION_BLUE_LABEL_COLOR := Color(0.18, 0.58, 0.68, 1)
const ACTION_BLUE_VALUE_COLOR := Color(0.68, 0.98, 1, 1)
const ACTION_DISABLED_COLOR := Color(0.32, 0.4, 0.45, 1)
const ACTION_PANEL_MARGIN := 12.0
const MOVEMENT_EPSILON_SQUARED := 0.0001
const ROTATION_EPSILON := 0.0001
const MONITOR_METHODS := {
	"recv_bps": &"_get_monitor_bps_recv",
	"sent_bps": &"_get_monitor_bps_sent",
	"sync_inbound_us": &"_get_monitor_sync_inbound_us",
	"sync_outbound_us": &"_get_monitor_sync_outbound_us",
	"service_us": &"_get_monitor_service_us",
	"update_us": &"_get_monitor_update_total_us",
}

@onready var _values := {
	&"status": %StatusValue,
	&"room": %RoomValue,
	&"players": %PlayersValue,
	&"local_player": %LocalPlayerValue,
	&"rtt": %RttValue,
	&"network_time": %NetworkTimeValue,
	&"traffic_receive": %TrafficReceiveValue,
	&"traffic_send": %TrafficSendValue,
	&"fusion_sync_receive": %FusionSyncReceiveValue,
	&"fusion_sync_send": %FusionSyncSendValue,
	&"fusion_loop_network": %FusionLoopNetworkValue,
	&"fusion_loop_update": %FusionLoopUpdateValue,
	&"rpc_probe_receive": %RpcProbeReceiveValue,
	&"rpc_probe_send": %RpcProbeSendValue,
	&"player_sync_receive": %PlayerSyncReceiveValue,
	&"player_sync_send": %PlayerSyncSendValue,
	&"interest_area": %InterestAreaValue,
	&"sync_rate": %SyncRateValue,
	&"rpc_rate": %RpcRateValue,
	&"smoothing": %SmoothingValue,
	&"spawn_player": %SpawnPlayerValue,
}
@onready var _toggle_shortcuts := {
	&"toggle_interest_area": %InterestAreaShortcut,
	&"toggle_sync_rate": %SyncRateShortcut,
	&"toggle_rpc_rate": %RpcRateShortcut,
	&"toggle_smoothing": %SmoothingShortcut,
	&"spawn_extra_player": %SpawnPlayerShortcut,
}
@onready var _network_margin: MarginContainer = %NetworkMargin
@onready var _network_panel: PanelContainer = %NetworkPanel
@onready var _toggle_margin: MarginContainer = %ToggleMargin
@onready var _toggle_panel: PanelContainer = %TogglePanel
@onready var _rpc_probe_receive_row := [
	%RpcProbeReceiveLabel,
	%RpcProbeReceiveValue,
	%RpcProbeReceiveUnit,
	%RpcProbeReceiveDirection,
]
@onready var _rpc_probe_send_row := [
	%RpcProbeLabel,
	%RpcProbeSendValue,
	%RpcProbeSendUnit,
	%RpcProbeSendDirection,
]
@onready var _interest_area_action_row := [
	%InterestAreaLabel,
	%InterestAreaValue,
	%InterestAreaShortcut,
]

var _tracked_players := {}
var _scan_elapsed := 0.0
var _sample_elapsed := 0.0
var _player_sync_up_samples := 0
var _player_sync_down_samples := 0
var _player_sync_up_hz := 0.0
var _player_sync_down_hz := 0.0
var _rpc_probe_send_elapsed := 0.0
var _rpc_probe_send_samples := 0
var _rpc_probe_receive_samples := 0
var _rpc_probe_send_hz := 0.0
var _rpc_probe_receive_hz := 0.0
var _interest_area_enabled := false
var _interest_area_toggle_locked := false
var _sync_update_interval := 1
var _rpc_probe_rate_hz := 60
var _smoothing_enabled := false
var _network_size_reset := false
var _toggle_size_reset := false


func _ready() -> void:
	set_process_unhandled_input(true)
	_refresh_toggle_shortcuts()
	Fusion.room_joined.connect(_on_room_joined)
	Fusion.register_broadcast_receiver(self)
	_scan_players()
	if Fusion.is_in_room():
		_sync_interest_area_from_room()
		_sync_sync_rate_from_room()
		_sync_rpc_rate_from_room()
		_sync_smoothing_from_room()
	_refresh_stats()


func _exit_tree() -> void:
	if Fusion.room_joined.is_connected(_on_room_joined):
		Fusion.room_joined.disconnect(_on_room_joined)
	Fusion.unregister_broadcast_receiver(self)


func _process(delta: float) -> void:
	_scan_elapsed += delta
	_sample_elapsed += delta
	_send_rpc_probe(delta)

	if _scan_elapsed >= PLAYER_SCAN_INTERVAL:
		_scan_elapsed = 0.0
		_scan_players()

	if _sample_elapsed >= SAMPLE_INTERVAL:
		var local_player_count := maxi(1, _tracked_player_count(true))
		var remote_player_count := maxi(1, _tracked_player_count(false))
		_player_sync_up_hz = _player_sync_up_samples / _sample_elapsed / local_player_count
		_player_sync_down_hz = _player_sync_down_samples / _sample_elapsed / remote_player_count
		_rpc_probe_send_hz = _rpc_probe_send_samples / _sample_elapsed
		_rpc_probe_receive_hz = _rpc_probe_receive_samples / _sample_elapsed
		_player_sync_up_samples = 0
		_player_sync_down_samples = 0
		_rpc_probe_send_samples = 0
		_rpc_probe_receive_samples = 0
		_sample_elapsed = 0.0
		_refresh_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_interest_area"):
		if not _interest_area_toggle_locked:
			_toggle_player_interest_areas()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_sync_rate"):
		_toggle_sync_rate()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_rpc_rate"):
		_toggle_rpc_rate()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_smoothing"):
		_toggle_smoothing()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"spawn_extra_player"):
		_spawn_extra_player()
		get_viewport().set_input_as_handled()


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


func _refresh_stats() -> void:
	var is_in_room := Fusion.is_in_room()
	var is_master := is_in_room and Fusion.is_master_client()

	_refresh_rpc_probe_rows(is_in_room, is_master)
	_set_label(&"player_sync_receive", _format_hz_value(_player_sync_down_hz))
	_set_label(&"player_sync_send", _format_hz_value(_player_sync_up_hz))
	_set_label(&"rpc_probe_receive", _format_hz_value(_rpc_probe_receive_hz) if is_in_room else "-")
	_set_label(&"rpc_probe_send", _format_hz_value(_rpc_probe_send_hz) if is_in_room else "-")
	_set_label(&"traffic_receive", _format_whole_number_value(_fusion_monitor("recv_bps")))
	_set_label(&"traffic_send", _format_whole_number_value(_fusion_monitor("sent_bps")))
	_set_label(&"fusion_sync_receive", _format_whole_number_value(_fusion_monitor("sync_inbound_us")))
	_set_label(&"fusion_sync_send", _format_whole_number_value(_fusion_monitor("sync_outbound_us")))
	_set_label(&"fusion_loop_network", _format_whole_number_value(_fusion_monitor("service_us")))
	_set_label(&"fusion_loop_update", _format_whole_number_value(_fusion_monitor("update_us")))
	_set_label(&"rtt", _format_rtt_value(_safe_fusion_call(&"get_rtt")))
	_set_label(&"players", _players_text())
	_set_label(&"local_player", _local_player_text())
	_set_label(&"network_time", _format_duration_value(float(_safe_fusion_call(&"get_network_time"))))
	_set_label(&"room", _room_text())
	_set_label(&"status", _connection_status_text())
	_set_label(&"interest_area", _interest_area_text())
	_set_label(&"sync_rate", _sync_rate_text())
	_set_label(&"rpc_rate", _rpc_rate_text())
	_set_label(&"smoothing", _smoothing_text())
	_set_label(&"spawn_player", "+1")
	if not _toggle_size_reset:
		_toggle_size_reset = true
		_reset_toggle_size.call_deferred()


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

	var replicator := player.get_node_or_null("%FusionSharedReplicator") as FusionReplicator
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
	apply_player_network_settings(player)


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


func _tracked_player_count(authority: bool) -> int:
	var count := 0
	for tracker in _tracked_players.values():
		var replicator := _get_tracker_replicator(tracker)
		if replicator != null and replicator.has_authority() == authority:
			count += 1

	return count


func _player_state_changed(player: Player, tracker: Dictionary) -> bool:
	var last_position: Vector2 = tracker.get("last_position", player.global_position)
	var last_velocity: Vector2 = tracker.get("last_velocity", player.velocity)
	var last_rotation := float(tracker.get("last_rotation", player.global_rotation))
	var last_manual_sync_probe := int(tracker.get("last_manual_sync_probe", player.manual_sync_probe))

	return (
		player.global_position.distance_squared_to(last_position) > MOVEMENT_EPSILON_SQUARED
		or player.velocity.distance_squared_to(last_velocity) > MOVEMENT_EPSILON_SQUARED
		or absf(angle_difference(player.global_rotation, last_rotation)) > ROTATION_EPSILON
		or player.manual_sync_probe != last_manual_sync_probe
	)


func _store_player_state(player: Player, tracker: Dictionary) -> void:
	tracker["last_position"] = player.global_position
	tracker["last_velocity"] = player.velocity
	tracker["last_rotation"] = player.global_rotation
	tracker["last_manual_sync_probe"] = player.manual_sync_probe


func _send_rpc_probe(delta: float) -> void:
	if not Fusion.is_in_room() or not Fusion.is_master_client():
		_rpc_probe_send_elapsed = 0.0
		return

	_rpc_probe_send_elapsed += delta
	var rpc_probe_interval := 1.0 / float(_rpc_probe_rate_hz)
	while _rpc_probe_send_elapsed >= rpc_probe_interval:
		_rpc_probe_send_elapsed -= rpc_probe_interval
		_rpc_probe_send_samples += 1
		Fusion.rpc(rpc_probe)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_probe() -> void:
	if not _rpc_probe_sender_is_master():
		return

	_rpc_probe_receive_samples += 1


func _rpc_probe_sender_is_master() -> bool:
	if not Fusion.is_in_room():
		return false

	var room: FusionRoom = Fusion.get_room()
	if room == null:
		return false

	return int(Fusion.get_rpc_sender()) == int(room.get_master_client_id())


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

	return room.get_room_name()


func _players_text() -> String:
	return str(_tracked_players.size())


func _local_player_text() -> String:
	var local_id := int(_safe_fusion_call(&"get_local_player_id"))
	return str(local_id) if local_id > 0 else "-"


func _on_room_joined() -> void:
	_sync_interest_area_from_room()
	_sync_sync_rate_from_room()
	_sync_rpc_rate_from_room()
	_sync_smoothing_from_room()


func _toggle_player_interest_areas() -> void:
	if _interest_area_toggle_locked:
		return

	if not Fusion.is_in_room():
		return

	var next_enabled := not _interest_area_enabled
	_store_interest_area_in_room(next_enabled)
	Fusion.rpc(rpc_set_interest_area_enabled, next_enabled)
	_lock_interest_area_toggle()


@rpc("any_peer", "call_local", "reliable")
func rpc_set_interest_area_enabled(enabled: bool) -> void:
	_set_interest_area_enabled(enabled)
	_lock_interest_area_toggle()


func _toggle_sync_rate() -> void:
	if not Fusion.is_in_room():
		return

	var next_interval := _next_sync_update_interval()
	_store_sync_rate_in_room(next_interval)
	Fusion.rpc(rpc_set_sync_update_interval, next_interval)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_sync_update_interval(interval: int) -> void:
	_set_sync_update_interval(interval)


func _toggle_rpc_rate() -> void:
	if not Fusion.is_in_room():
		return

	var next_rate := _next_rpc_probe_rate()
	_store_rpc_rate_in_room(next_rate)
	Fusion.rpc(rpc_set_rpc_probe_rate, next_rate)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_rpc_probe_rate(rate_hz: int) -> void:
	_set_rpc_probe_rate(rate_hz)


func _toggle_smoothing() -> void:
	if not Fusion.is_in_room():
		return

	var next_enabled := not _smoothing_enabled
	_store_smoothing_in_room(next_enabled)
	Fusion.rpc(rpc_set_smoothing_enabled, next_enabled)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_smoothing_enabled(enabled: bool) -> void:
	_set_smoothing_enabled(enabled)


func _spawn_extra_player() -> void:
	if Game.instance != null:
		Game.instance.spawn_player()


func _sync_interest_area_from_room() -> void:
	var room: FusionRoom = Fusion.get_room()
	if room == null:
		return

	var custom_properties := room.get_custom_properties()
	if custom_properties.has(INTEREST_AREA_ROOM_PROPERTY):
		_set_interest_area_enabled(bool(custom_properties[INTEREST_AREA_ROOM_PROPERTY]))
		_lock_interest_area_toggle()


func _sync_sync_rate_from_room() -> void:
	var room: FusionRoom = Fusion.get_room()
	if room == null:
		return

	var custom_properties := room.get_custom_properties()
	if custom_properties.has(SYNC_RATE_ROOM_PROPERTY):
		_set_sync_update_interval(int(custom_properties[SYNC_RATE_ROOM_PROPERTY]))


func _sync_rpc_rate_from_room() -> void:
	var room: FusionRoom = Fusion.get_room()
	if room == null:
		return

	var custom_properties := room.get_custom_properties()
	if custom_properties.has(RPC_RATE_ROOM_PROPERTY):
		_set_rpc_probe_rate(int(custom_properties[RPC_RATE_ROOM_PROPERTY]))


func _sync_smoothing_from_room() -> void:
	var room: FusionRoom = Fusion.get_room()
	if room == null:
		return

	var custom_properties := room.get_custom_properties()
	if custom_properties.has(SMOOTHING_ROOM_PROPERTY):
		_set_smoothing_enabled(bool(custom_properties[SMOOTHING_ROOM_PROPERTY]))


func _store_interest_area_in_room(enabled: bool) -> void:
	var room: FusionRoom = Fusion.get_room()
	if room != null:
		room.set_property(INTEREST_AREA_ROOM_PROPERTY, enabled)


func _store_sync_rate_in_room(interval: int) -> void:
	var room: FusionRoom = Fusion.get_room()
	if room != null:
		room.set_property(SYNC_RATE_ROOM_PROPERTY, _normalize_sync_update_interval(interval))


func _store_rpc_rate_in_room(rate_hz: int) -> void:
	var room: FusionRoom = Fusion.get_room()
	if room != null:
		room.set_property(RPC_RATE_ROOM_PROPERTY, _normalize_rpc_probe_rate(rate_hz))


func _store_smoothing_in_room(enabled: bool) -> void:
	var room: FusionRoom = Fusion.get_room()
	if room != null:
		room.set_property(SMOOTHING_ROOM_PROPERTY, enabled)


func _set_interest_area_enabled(enabled: bool) -> void:
	_interest_area_enabled = enabled
	var player_parent := Game.instance.world if Game.instance != null else null
	if player_parent != null:
		for node in player_parent.get_children():
			var player := node as Player
			if player != null:
				player.interest_area_enabled = enabled if player.has_authority else false

	_refresh_stats()


func apply_player_network_settings(player: Player) -> void:
	player.interest_area_enabled = _interest_area_enabled if player.has_authority else false

	var replicator := player.get_node_or_null("%FusionSharedReplicator") as FusionReplicator
	if replicator == null:
		return

	replicator.set_update_interval(_sync_update_interval)
	replicator.set_root_smoothing(_smoothing_enabled)


func _set_sync_update_interval(interval: int) -> void:
	_sync_update_interval = _normalize_sync_update_interval(interval)
	_apply_world_replicators(func(replicator: FusionReplicator) -> void:
		replicator.set_update_interval(_sync_update_interval)
	)
	_refresh_stats()


func _set_rpc_probe_rate(rate_hz: int) -> void:
	_rpc_probe_rate_hz = _normalize_rpc_probe_rate(rate_hz)
	_rpc_probe_send_elapsed = 0.0
	_refresh_stats()


func _set_smoothing_enabled(enabled: bool) -> void:
	_smoothing_enabled = enabled
	_apply_world_replicators(func(replicator: FusionReplicator) -> void:
		replicator.set_root_smoothing(enabled)
	)
	_refresh_stats()


func _interest_area_text() -> String:
	return "On" if _interest_area_enabled else "Off"


func _lock_interest_area_toggle() -> void:
	_interest_area_toggle_locked = true
	_refresh_interest_area_action_row()
	_reset_toggle_size.call_deferred()


func _refresh_interest_area_action_row() -> void:
	if _interest_area_toggle_locked:
		%InterestAreaShortcut.text = "(Reload)"
		for label in _interest_area_action_row:
			_set_label_color(label, ACTION_DISABLED_COLOR)
		return

	%InterestAreaShortcut.text = _action_shortcut_text(&"toggle_interest_area")
	_set_label_color(%InterestAreaLabel, ACTION_BLUE_LABEL_COLOR)
	_set_label_color(%InterestAreaValue, ACTION_BLUE_VALUE_COLOR)
	_set_label_color(%InterestAreaShortcut, ACTION_BLUE_LABEL_COLOR)


func _sync_rate_text() -> String:
	return str(_sync_update_interval)


func _rpc_rate_text() -> String:
	return "%d Hz" % _rpc_probe_rate_hz


func _smoothing_text() -> String:
	return "On" if _smoothing_enabled else "Off"


func _next_sync_update_interval() -> int:
	var current_index := SYNC_UPDATE_INTERVALS.find(_sync_update_interval)
	if current_index == -1:
		return int(SYNC_UPDATE_INTERVALS[0])

	return int(SYNC_UPDATE_INTERVALS[(current_index + 1) % SYNC_UPDATE_INTERVALS.size()])


func _normalize_sync_update_interval(interval: int) -> int:
	return interval if SYNC_UPDATE_INTERVALS.has(interval) else int(SYNC_UPDATE_INTERVALS[0])


func _next_rpc_probe_rate() -> int:
	var current_index := RPC_PROBE_RATES_HZ.find(_rpc_probe_rate_hz)
	if current_index == -1:
		return int(RPC_PROBE_RATES_HZ[0])

	return int(RPC_PROBE_RATES_HZ[(current_index + 1) % RPC_PROBE_RATES_HZ.size()])


func _normalize_rpc_probe_rate(rate_hz: int) -> int:
	return rate_hz if RPC_PROBE_RATES_HZ.has(rate_hz) else int(RPC_PROBE_RATES_HZ[0])


func _apply_world_replicators(callback: Callable) -> void:
	var world := Game.instance.world if Game.instance != null else null
	if world == null:
		return

	for node in world.get_children():
		var replicator := node.get_node_or_null("%FusionSharedReplicator") as FusionReplicator
		if replicator != null:
			callback.call(replicator)


func _safe_fusion_call(method: StringName) -> Variant:
	if Fusion.has_method(method):
		return Fusion.call(method)
	return 0


func _fusion_monitor(key: String) -> float:
	var method: StringName = MONITOR_METHODS.get(key, &"")
	if method != &"" and Fusion.has_method(method):
		return maxf(0.0, float(Fusion.call(method)))
	return 0.0


func _format_whole_number_value(value: float) -> String:
	return "%.0f" % maxf(0.0, value)


func _format_duration_value(seconds: float) -> String:
	var whole_seconds := maxi(0, int(roundf(seconds)))
	var hours := int(float(whole_seconds) / 3600.0)
	var minutes := int(float(whole_seconds) / 60.0)
	var remaining_seconds := whole_seconds % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes % 60, remaining_seconds]

	return "%d:%02d" % [minutes, remaining_seconds]


func _format_rtt_value(value: Variant) -> String:
	var rtt := maxf(0.0, float(value))
	if rtt > 0.0 and rtt < 1.0:
		rtt *= 1000.0
	return "%.0f" % rtt


func _format_hz_value(value: float) -> String:
	return "%.1f" % maxf(0.0, value)


func _set_label(key: StringName, value: String) -> void:
	var label: Label = _values.get(key)
	if label != null:
		label.text = value


func _set_label_color(label: Label, color: Color) -> void:
	label.add_theme_color_override(&"font_color", color)


func _refresh_toggle_shortcuts() -> void:
	for action in _toggle_shortcuts.keys():
		var label: Label = _toggle_shortcuts[action]
		label.text = _action_shortcut_text(action)
	_refresh_interest_area_action_row()


func _action_shortcut_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event == null:
			continue

		var keycode := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
		var key_text := OS.get_keycode_string(keycode) + " Key"
		if key_text.is_empty():
			continue

		var parts := PackedStringArray()
		if key_event.ctrl_pressed:
			parts.append("Ctrl")
		if key_event.alt_pressed:
			parts.append("Alt")
		if key_event.shift_pressed and keycode != KEY_SHIFT:
			parts.append("Shift")
		if key_event.meta_pressed:
			parts.append("Meta")
		parts.append(key_text)
		return "(%s)" % "+".join(parts)

	return "-"


func _refresh_rpc_probe_rows(is_in_room: bool, is_master: bool) -> void:
	_set_row_visible(_rpc_probe_send_row, is_in_room and is_master)
	_set_row_visible(_rpc_probe_receive_row, not is_in_room or not is_master)
	if not _network_size_reset:
		_network_size_reset = true
		_reset_network_size.call_deferred()


func _set_row_visible(row: Array, should_show: bool) -> void:
	for item in row:
		var canvas_item := item as CanvasItem
		if canvas_item != null:
			canvas_item.visible = should_show


func _reset_network_size() -> void:
	_network_panel.size = Vector2.ZERO
	_network_margin.size = Vector2.ZERO
	_network_margin.reset_size()


func _reset_toggle_size() -> void:
	_toggle_panel.size = Vector2.ZERO
	_toggle_margin.anchor_left = 1.0
	_toggle_margin.anchor_top = 0.0
	_toggle_margin.anchor_right = 1.0
	_toggle_margin.anchor_bottom = 0.0
	_toggle_margin.offset_left = -ACTION_PANEL_MARGIN
	_toggle_margin.offset_top = ACTION_PANEL_MARGIN
	_toggle_margin.offset_right = -ACTION_PANEL_MARGIN
	_toggle_margin.offset_bottom = ACTION_PANEL_MARGIN
	_toggle_margin.size = Vector2.ZERO
	_toggle_margin.reset_size()

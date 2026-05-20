class_name UI extends CanvasLayer

const PLAYER_GROUP := "players"
const SAMPLE_INTERVAL := 1.0
const PLAYER_SCAN_INTERVAL := 0.25
const RPC_PROBE_TARGET_HZ := 60.0
const RPC_PROBE_INTERVAL := 1.0 / RPC_PROBE_TARGET_HZ
const SIMULATION_MODE_SETTING := "fusion/simulation/mode"
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
	&"simulation_mode": %SimulationModeValue,
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
}
@onready var _network_margin: MarginContainer = %NetworkMargin
@onready var _network_panel: PanelContainer = %NetworkPanel
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
var _network_size_reset := false


func _ready() -> void:
	set_process_unhandled_input(true)
	Fusion.register_broadcast_receiver(self)
	_scan_players()
	_refresh_stats()


func _exit_tree() -> void:
	Fusion.unregister_broadcast_receiver(self)


func _process(delta: float) -> void:
	_scan_elapsed += delta
	_sample_elapsed += delta
	_send_rpc_probe(delta)

	if _scan_elapsed >= PLAYER_SCAN_INTERVAL:
		_scan_elapsed = 0.0
		_scan_players()

	if _sample_elapsed >= SAMPLE_INTERVAL:
		_player_sync_up_hz = _player_sync_up_samples / _sample_elapsed
		_player_sync_down_hz = _player_sync_down_samples / _sample_elapsed
		_rpc_probe_send_hz = _rpc_probe_send_samples / _sample_elapsed
		_rpc_probe_receive_hz = _rpc_probe_receive_samples / _sample_elapsed
		_player_sync_up_samples = 0
		_player_sync_down_samples = 0
		_rpc_probe_send_samples = 0
		_rpc_probe_receive_samples = 0
		_sample_elapsed = 0.0
		_refresh_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_select"):
		_toggle_player_interest_areas()


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
	_set_label(&"simulation_mode", _simulation_mode_text())
	_set_label(&"interest_area", _interest_area_text())


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

	var replicator := player.get_node("%FusionSharedReplicator") as FusionReplicator

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
	while _rpc_probe_send_elapsed >= RPC_PROBE_INTERVAL:
		_rpc_probe_send_elapsed -= RPC_PROBE_INTERVAL
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


func _toggle_player_interest_areas() -> void:
	var player_parent := Game.instance.world if Game.instance != null else null
	if player_parent == null:
		return

	var found_player := false
	var next_enabled := false
	for node in player_parent.get_children():
		var player := node as Player
		if player == null:
			continue
		if not found_player:
			next_enabled = not player.interest_area_enabled
			found_player = true
		player.interest_area_enabled = next_enabled

	if found_player:
		_refresh_stats()


func _interest_area_text() -> String:
	var player_parent := Game.instance.world if Game.instance != null else null
	if player_parent == null:
		return "-"

	var found_player := false
	for node in player_parent.get_children():
		var player := node as Player
		if player == null:
			continue
		found_player = true
		if player.interest_area_enabled:
			return "On"

	return "Off" if found_player else "-"


func _simulation_mode_text() -> String:
	if ProjectSettings.has_setting(SIMULATION_MODE_SETTING):
		return _format_simulation_mode(ProjectSettings.get_setting(SIMULATION_MODE_SETTING))

	return _format_simulation_mode(_safe_fusion_call(&"get_simulation_mode"))


func _format_simulation_mode(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).capitalize()

	match int(value):
		FusionClient.SIMULATION_SHARED:
			return "Shared"
		FusionClient.SIMULATION_CLIENT_SERVER:
			return "Client Server"
		_:
			return str(value)


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

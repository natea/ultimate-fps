extends Node

const PORT := 7777
const MAX_PLAYERS := 4

# Player info: { peer_id: { "name": String } }
var players := {}
var local_player_name := "Player"

# Match settings (set in lobby, read by match_manager)
var match_kill_limit := 20
var match_time_limit := 600.0  # seconds
var match_map_path := "res://levels/arena.tscn"

signal player_connected(peer_id: int, info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal connection_failed
signal all_players_loaded

var _players_loaded := 0
var _expected_players := 0

func host_game(player_name: String) -> Error:
	local_player_name = player_name
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Add host to player list
	_register_player(1, {"name": player_name})
	return OK

func join_game(ip: String, player_name: String) -> Error:
	local_player_name = player_name
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	return OK

func disconnect_from_game():
	multiplayer.multiplayer_peer = null
	players.clear()
	_players_loaded = 0

func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func get_player_name(peer_id: int) -> String:
	if players.has(peer_id):
		return players[peer_id]["name"]
	return "Unknown"

func start_match():
	# Only host can start
	if not is_host():
		return
	_players_loaded = 0
	_expected_players = players.size()
	_load_match_scene.rpc(match_map_path)

@rpc("authority", "call_local", "reliable")
func _load_match_scene(scene_path: String):
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	var level = get_tree().current_scene
	var dm = load("res://multiplayer/deathmatch_level.gd").new()
	dm.name = "DeathmatchController"
	level.add_child(dm)
	_notify_loaded.rpc_id(1)

@rpc("any_peer", "reliable")
func _notify_loaded():
	if not is_host():
		return
	_players_loaded += 1
	if _players_loaded >= _expected_players:
		all_players_loaded.emit()

func return_to_lobby():
	get_tree().change_scene_to_file("res://multiplayer/lobby.tscn")

func _on_peer_connected(id: int):
	# Send our name to the new peer
	_register_player_rpc.rpc_id(id, multiplayer.get_unique_id(), {"name": local_player_name})
	# Send our name to ourselves if we're a new client getting the host's list
	if not multiplayer.is_server():
		_register_player_rpc.rpc_id(1, multiplayer.get_unique_id(), {"name": local_player_name})

func _on_peer_disconnected(id: int):
	players.erase(id)
	player_disconnected.emit(id)
	# Clean up player node if in a match
	var level = get_tree().current_scene
	if level:
		var dm = level.get_node_or_null("DeathmatchController")
		if dm and dm.has_method("remove_player"):
			dm.remove_player(id)

func _on_server_disconnected():
	players.clear()
	server_disconnected.emit()

func _on_connection_failed():
	connection_failed.emit()

@rpc("any_peer", "reliable")
func _register_player_rpc(id: int, info: Dictionary):
	_register_player(id, info)
	# If server, broadcast to all other peers
	if multiplayer.is_server():
		for peer_id in players:
			if peer_id != multiplayer.get_remote_sender_id():
				_register_player_rpc.rpc_id(multiplayer.get_remote_sender_id(), peer_id, players[peer_id])

func _register_player(id: int, info: Dictionary):
	players[id] = info
	player_connected.emit(id, info)

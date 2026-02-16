extends Node3D

var spawn_points: Array[Node3D] = []
var player_scene := preload("res://player/player.tscn")
var player_nodes := {}  # peer_id -> player node

func _ready():
	# Collect spawn points
	for child in get_children():
		if child is SpawnPoint:
			spawn_points.append(child)

	if spawn_points.is_empty():
		push_warning("No SpawnPoints found! Adding default positions.")
		for i in 4:
			var sp = Node3D.new()
			sp.position = Vector3(i * 5 - 7.5, 2, 0)
			spawn_points.append(sp)

	# Generate collision from map meshes (same as single-player levels)
	_generate_map_collision()

	# Wait for all players to load, then spawn everyone
	if NetworkManager.is_host():
		# If all already loaded (small player count), spawn immediately
		await get_tree().create_timer(0.5).timeout
		spawn_all_players()

func spawn_all_players():
	var peer_ids = NetworkManager.players.keys()
	peer_ids.sort()
	for i in peer_ids.size():
		var peer_id = peer_ids[i]
		var sp_index = i % spawn_points.size()
		_spawn_player.rpc(peer_id, spawn_points[sp_index].global_position)

@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int, pos: Vector3):
	if player_nodes.has(peer_id):
		return  # Already spawned
	var player = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
	add_child(player)
	player.global_position = pos
	player_nodes[peer_id] = player

	# Configure local vs remote
	var is_local = peer_id == multiplayer.get_unique_id()
	player.set_meta("peer_id", peer_id)
	player.set_meta("is_local", is_local)

	if not is_local:
		# Disable input, camera, audio for remote players
		player.set_process_input(false)
		player.set_process_unhandled_input(false)
		var cam = player.get_node_or_null("Head/Camera")
		if cam:
			cam.current = false
		var tp_cam = player.get_node_or_null("Head/SpringArm3D/ThirdPersonCamera")
		if tp_cam:
			tp_cam.current = false
	else:
		# Local player gets camera
		var cam = player.get_node_or_null("Head/Camera")
		if cam:
			cam.make_current()

func get_random_spawn_position(exclude_positions: Array[Vector3] = []) -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 2, 0)
	# Pick spawn point farthest from all exclude positions
	if exclude_positions.is_empty():
		return spawn_points[randi() % spawn_points.size()].global_position
	var best_sp = spawn_points[0]
	var best_min_dist := 0.0
	for sp in spawn_points:
		var min_dist := INF
		for pos in exclude_positions:
			var d = sp.global_position.distance_to(pos)
			if d < min_dist:
				min_dist = d
		if min_dist > best_min_dist:
			best_min_dist = min_dist
			best_sp = sp
	return best_sp.global_position

func respawn_player(peer_id: int):
	if not player_nodes.has(peer_id):
		return
	# Gather other player positions to avoid spawning on top of them
	var other_positions: Array[Vector3] = []
	for pid in player_nodes:
		if pid != peer_id and is_instance_valid(player_nodes[pid]):
			other_positions.append(player_nodes[pid].global_position)
	var new_pos = get_random_spawn_position(other_positions)
	_do_respawn.rpc(peer_id, new_pos)

@rpc("authority", "call_local", "reliable")
func _do_respawn(peer_id: int, pos: Vector3):
	if not player_nodes.has(peer_id):
		return
	var player = player_nodes[peer_id]
	if not is_instance_valid(player):
		return
	player.global_position = pos
	player.health = player.max_health
	player.health_updated.emit(player.health, player.max_health)

func _generate_map_collision():
	var map = get_node_or_null("Map")
	if map == null:
		return
	var meshes: Array[MeshInstance3D] = []
	var stack: Array[Node] = [map]
	while stack.size() > 0:
		var node = stack.pop_back()
		if node is Node3D and not node.visible:
			continue
		if node is MeshInstance3D and node.mesh:
			meshes.append(node)
		for child in node.get_children():
			stack.push_back(child)
	for m in meshes:
		var body = StaticBody3D.new()
		m.add_child(body)
		var col = CollisionShape3D.new()
		col.shape = m.mesh.create_trimesh_shape()
		body.add_child(col)

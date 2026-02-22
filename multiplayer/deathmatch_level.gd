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

	# Remove single-player player and HUD (we spawn our own)
	var sp_player = get_parent().get_node_or_null("Player")
	if sp_player:
		sp_player.queue_free()
	var sp_hud = get_parent().get_node_or_null("HUD")
	if sp_hud:
		sp_hud.queue_free()
	var sp_scope = get_parent().get_node_or_null("ScopeOverlay")
	if sp_scope:
		sp_scope.queue_free()
	# Remove single-player enemies
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.queue_free()

	# Also look for spawn points in parent scene
	for child in get_parent().get_children():
		if child is SpawnPoint:
			spawn_points.append(child)

	# Generate collision from map meshes (same as single-player levels)
	_generate_map_collision()

	# Add match manager
	var match_mgr = MatchManager.new()
	match_mgr.name = "MatchManager"
	add_child(match_mgr)

	# Add multiplayer HUD
	var mp_hud = preload("res://multiplayer/mp_hud.tscn").instantiate()
	add_child(mp_hud)

	# Add weapon spawner
	var spawner = load("res://multiplayer/weapon_spawner.gd").new()
	spawner.name = "WeaponSpawner"
	add_child(spawner)

	# Handle server disconnect
	NetworkManager.server_disconnected.connect(func():
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	)

	# Wait for all players to load, then spawn everyone
	if NetworkManager.is_host():
		if NetworkManager._players_loaded >= NetworkManager._expected_players:
			# All players already reported loaded
			spawn_all_players()
		else:
			# Wait for all players to load (with timeout fallback)
			var loaded = false
			NetworkManager.all_players_loaded.connect(func():
				loaded = true
			, CONNECT_ONE_SHOT)
			for i in 10:
				await get_tree().create_timer(1.0).timeout
				if loaded:
					break
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
		# Add floating name tag
		var label_3d = Label3D.new()
		label_3d.text = NetworkManager.get_player_name(peer_id)
		label_3d.font_size = 48
		label_3d.position = Vector3(0, 2.2, 0)
		label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_3d.no_depth_test = true
		label_3d.outline_size = 8
		player.add_child(label_3d)
	else:
		# Local player gets camera
		var cam = player.get_node_or_null("Head/Camera")
		if cam:
			cam.make_current()

func remove_player(peer_id: int):
	if player_nodes.has(peer_id):
		var node = player_nodes[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		player_nodes.erase(peer_id)

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

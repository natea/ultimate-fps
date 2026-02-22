# Multiplayer FFA Deathmatch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Free-For-All PvP deathmatch (2-4 players, listen server, direct IP connect) to the existing single-player FPS game.

**Architecture:** ENetMultiplayerPeer listen server. NetworkManager autoload singleton persists across scene changes. Server-authoritative damage with client-side prediction for responsiveness. MultiplayerSynchronizer for player state replication.

**Tech Stack:** Godot 4.5, GDScript, ENet high-level multiplayer API

---

### Task 1: Create NetworkManager Autoload

**Files:**
- Create: `multiplayer/network_manager.gd`
- Modify: `project.godot:18-20` (add autoload)

**Step 1: Create the NetworkManager script**

Create `multiplayer/network_manager.gd`:

```gdscript
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
	# After scene loads, notify server
	await get_tree().process_frame
	await get_tree().process_frame
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
```

**Step 2: Register as autoload in project.godot**

Add to `project.godot` under `[autoload]` section, after the existing `GDAIMCPRuntime` line:

```
NetworkManager="*res://multiplayer/network_manager.gd"
```

**Step 3: Add scoreboard input binding**

Add to `project.godot` under `[input]` section:

```
scoreboard={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194306,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

**Step 4: Verify the autoload loads**

Run: Open Godot editor, check Project > Project Settings > Autoload tab shows `NetworkManager`.

**Step 5: Commit**

```bash
git add multiplayer/network_manager.gd project.godot
git commit -m "feat: add NetworkManager autoload for multiplayer"
```

---

### Task 2: Create Multiplayer Menu UI

**Files:**
- Create: `multiplayer/multiplayer_menu.gd`
- Create: `multiplayer/multiplayer_menu.tscn`
- Modify: `ui/main_menu.gd:19-28` (add Multiplayer button)

**Step 1: Create the multiplayer menu script**

Create `multiplayer/multiplayer_menu.gd`:

```gdscript
extends Control

var name_input: LineEdit
var ip_input: LineEdit
var status_label: Label
var host_btn: Button
var join_btn: Button
var back_btn: Button

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _process(_delta):
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var container = VBoxContainer.new()
	container.set_anchors_preset(PRESET_CENTER)
	container.offset_left = -200.0
	container.offset_top = -200.0
	container.offset_right = 200.0
	container.offset_bottom = 200.0
	container.add_theme_constant_override("separation", 16)
	add_child(container)

	# Title
	var title = Label.new()
	title.text = "MULTIPLAYER"
	var title_settings = LabelSettings.new()
	title_settings.font_size = 48
	title_settings.font_color = Color(1, 1, 1)
	title_settings.outline_size = 4
	title_settings.outline_color = Color(0, 0, 0)
	title.label_settings = title_settings
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	# Name input
	var name_label = Label.new()
	name_label.text = "Your Name:"
	name_label.add_theme_font_size_override("font_size", 18)
	container.add_child(name_label)

	name_input = LineEdit.new()
	name_input.text = "Player"
	name_input.max_length = 16
	name_input.add_theme_font_size_override("font_size", 20)
	container.add_child(name_input)

	# IP input
	var ip_label = Label.new()
	ip_label.text = "Server IP (for joining):"
	ip_label.add_theme_font_size_override("font_size", 18)
	container.add_child(ip_label)

	ip_input = LineEdit.new()
	ip_input.text = "127.0.0.1"
	ip_input.add_theme_font_size_override("font_size", 20)
	container.add_child(ip_input)

	# Buttons
	var btn_container = HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 12)
	container.add_child(btn_container)

	host_btn = Button.new()
	host_btn.text = "Host Game"
	host_btn.add_theme_font_size_override("font_size", 22)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host_pressed)
	btn_container.add_child(host_btn)

	join_btn = Button.new()
	join_btn.text = "Join Game"
	join_btn.add_theme_font_size_override("font_size", 22)
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join_pressed)
	btn_container.add_child(join_btn)

	# Status label
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(status_label)

	# Back button
	back_btn = Button.new()
	back_btn.text = "Back to Menu"
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.pressed.connect(_on_back_pressed)
	container.add_child(back_btn)

func _on_host_pressed():
	var pname = name_input.text.strip_edges()
	if pname == "":
		pname = "Host"
	status_label.text = "Starting server..."
	var err = NetworkManager.host_game(pname)
	if err != OK:
		status_label.text = "Failed to create server (error %d)" % err
		return
	get_tree().change_scene_to_file("res://multiplayer/lobby.tscn")

func _on_join_pressed():
	var pname = name_input.text.strip_edges()
	if pname == "":
		pname = "Player"
	var ip = ip_input.text.strip_edges()
	if ip == "":
		status_label.text = "Enter a server IP address"
		return
	status_label.text = "Connecting to %s..." % ip
	host_btn.disabled = true
	join_btn.disabled = true
	var err = NetworkManager.join_game(ip, pname)
	if err != OK:
		status_label.text = "Failed to connect (error %d)" % err
		host_btn.disabled = false
		join_btn.disabled = false
		return
	# Wait briefly for connection, then go to lobby
	await get_tree().create_timer(1.0).timeout
	if NetworkManager.multiplayer.multiplayer_peer != null:
		get_tree().change_scene_to_file("res://multiplayer/lobby.tscn")
	else:
		status_label.text = "Connection failed"
		host_btn.disabled = false
		join_btn.disabled = false

func _on_connection_failed():
	status_label.text = "Connection failed"
	host_btn.disabled = false
	join_btn.disabled = false

func _on_back_pressed():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
```

**Step 2: Create the multiplayer menu scene**

Create `multiplayer/multiplayer_menu.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://multiplayer/multiplayer_menu.gd" id="1"]

[node name="MultiplayerMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
```

**Step 3: Add Multiplayer button to main menu**

In `ui/main_menu.gd`, add a "Multiplayer" button in `_ready()`. After line 28 (`$MenuContainer/QuitButton.mouse_entered.connect(...)`), add:

```gdscript
	# Add multiplayer button (insert before Quit)
	var mp_button = Button.new()
	mp_button.text = "Multiplayer"
	mp_button.add_theme_font_size_override("font_size", 24)
	mp_button.pressed.connect(_on_multiplayer_pressed)
	mp_button.mouse_entered.connect(_on_button_hover.bind(mp_button))
	$MenuContainer.add_child(mp_button)
	$MenuContainer.move_child(mp_button, 2)  # After Play and Events
```

Add the handler function at the end of `main_menu.gd`:

```gdscript
func _on_multiplayer_pressed():
	get_tree().change_scene_to_file("res://multiplayer/multiplayer_menu.tscn")
```

**Step 4: Verify**

Run the main menu scene. Confirm the "Multiplayer" button appears and navigates to the multiplayer menu. Confirm "Back to Menu" returns to main menu.

**Step 5: Commit**

```bash
git add multiplayer/multiplayer_menu.gd multiplayer/multiplayer_menu.tscn ui/main_menu.gd
git commit -m "feat: add multiplayer menu with host/join UI"
```

---

### Task 3: Create Lobby Screen

**Files:**
- Create: `multiplayer/lobby.gd`
- Create: `multiplayer/lobby.tscn`

**Step 1: Create the lobby script**

Create `multiplayer/lobby.gd`:

```gdscript
extends Control

var player_list: VBoxContainer
var map_selector: OptionButton
var kill_limit_spin: SpinBox
var time_limit_spin: SpinBox
var start_btn: Button
var status_label: Label

var mp_maps := [
	{"name": "Arena", "scene": "res://levels/arena.tscn"},
	{"name": "Ruins", "scene": "res://levels/ruins.tscn"},
]

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_refresh_player_list()
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func _process(_delta):
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_ui():
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var main_container = VBoxContainer.new()
	main_container.set_anchors_preset(PRESET_CENTER)
	main_container.offset_left = -250.0
	main_container.offset_top = -250.0
	main_container.offset_right = 250.0
	main_container.offset_bottom = 250.0
	main_container.add_theme_constant_override("separation", 12)
	add_child(main_container)

	# Title
	var title = Label.new()
	title.text = "LOBBY"
	var title_settings = LabelSettings.new()
	title_settings.font_size = 48
	title_settings.font_color = Color(1, 1, 1)
	title_settings.outline_size = 4
	title_settings.outline_color = Color(0, 0, 0)
	title.label_settings = title_settings
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)

	# Player list header
	var players_header = Label.new()
	players_header.text = "Players:"
	players_header.add_theme_font_size_override("font_size", 22)
	main_container.add_child(players_header)

	# Player list
	player_list = VBoxContainer.new()
	player_list.add_theme_constant_override("separation", 4)
	main_container.add_child(player_list)

	# Settings (host only)
	if NetworkManager.is_host():
		var settings_label = Label.new()
		settings_label.text = "Match Settings:"
		settings_label.add_theme_font_size_override("font_size", 22)
		main_container.add_child(settings_label)

		# Map selector
		var map_row = HBoxContainer.new()
		var map_label = Label.new()
		map_label.text = "Map: "
		map_label.add_theme_font_size_override("font_size", 18)
		map_row.add_child(map_label)
		map_selector = OptionButton.new()
		for map_info in mp_maps:
			map_selector.add_item(map_info.name)
		map_selector.add_theme_font_size_override("font_size", 18)
		map_row.add_child(map_selector)
		main_container.add_child(map_row)

		# Kill limit
		var kill_row = HBoxContainer.new()
		var kill_label = Label.new()
		kill_label.text = "Kill Limit: "
		kill_label.add_theme_font_size_override("font_size", 18)
		kill_row.add_child(kill_label)
		kill_limit_spin = SpinBox.new()
		kill_limit_spin.min_value = 5
		kill_limit_spin.max_value = 50
		kill_limit_spin.value = 20
		kill_limit_spin.step = 5
		kill_row.add_child(kill_limit_spin)
		main_container.add_child(kill_row)

		# Time limit
		var time_row = HBoxContainer.new()
		var time_label = Label.new()
		time_label.text = "Time Limit (min): "
		time_label.add_theme_font_size_override("font_size", 18)
		time_row.add_child(time_label)
		time_limit_spin = SpinBox.new()
		time_limit_spin.min_value = 3
		time_limit_spin.max_value = 30
		time_limit_spin.value = 10
		time_limit_spin.step = 1
		time_row.add_child(time_limit_spin)
		main_container.add_child(time_row)

		# Start button
		start_btn = Button.new()
		start_btn.text = "Start Match"
		start_btn.add_theme_font_size_override("font_size", 24)
		start_btn.pressed.connect(_on_start_pressed)
		main_container.add_child(start_btn)
	else:
		status_label = Label.new()
		status_label.text = "Waiting for host to start..."
		status_label.add_theme_font_size_override("font_size", 20)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_container.add_child(status_label)

	# Leave button
	var leave_btn = Button.new()
	leave_btn.text = "Leave"
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.pressed.connect(_on_leave_pressed)
	main_container.add_child(leave_btn)

func _refresh_player_list():
	for child in player_list.get_children():
		child.queue_free()
	for peer_id in NetworkManager.players:
		var info = NetworkManager.players[peer_id]
		var label = Label.new()
		var host_tag = " (Host)" if peer_id == 1 else ""
		var you_tag = " (You)" if peer_id == multiplayer.get_unique_id() else ""
		label.text = "  %s%s%s" % [info["name"], host_tag, you_tag]
		label.add_theme_font_size_override("font_size", 20)
		player_list.add_child(label)

func _on_player_connected(_peer_id: int, _info: Dictionary):
	_refresh_player_list()

func _on_player_disconnected(_peer_id: int):
	_refresh_player_list()

func _on_server_disconnected():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _on_start_pressed():
	# Apply settings
	var map_idx = map_selector.get_selected_id()
	NetworkManager.match_map_path = mp_maps[map_idx]["scene"]
	NetworkManager.match_kill_limit = int(kill_limit_spin.value)
	NetworkManager.match_time_limit = time_limit_spin.value * 60.0
	NetworkManager.start_match()

func _on_leave_pressed():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
```

**Step 2: Create the lobby scene**

Create `multiplayer/lobby.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://multiplayer/lobby.gd" id="1"]

[node name="Lobby" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
```

**Step 3: Verify**

Launch two instances of the game. Host on one, join on the other via 127.0.0.1. Confirm both names appear in the lobby player list.

**Step 4: Commit**

```bash
git add multiplayer/lobby.gd multiplayer/lobby.tscn
git commit -m "feat: add multiplayer lobby with player list and match settings"
```

---

### Task 4: Create SpawnPoint and Deathmatch Level Loader

**Files:**
- Create: `multiplayer/spawn_point.gd`
- Create: `multiplayer/deathmatch_level.gd`

**Step 1: Create the SpawnPoint script**

Create `multiplayer/spawn_point.gd`:

```gdscript
extends Node3D
class_name SpawnPoint
```

**Step 2: Create the deathmatch level loader script**

This script replaces the single-player level script for multiplayer maps. It spawns all players at spawn points and sets up the multiplayer-aware HUD.

Create `multiplayer/deathmatch_level.gd`:

```gdscript
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
```

**Step 3: Commit**

```bash
git add multiplayer/spawn_point.gd multiplayer/deathmatch_level.gd
git commit -m "feat: add SpawnPoint class and deathmatch level loader"
```

---

### Task 5: Adapt Player Script for Multiplayer

**Files:**
- Modify: `player/player.gd`

This is the largest task. We add multiplayer authority guards so only the local player processes input, and add RPCs for shooting/damage.

**Step 1: Add multiplayer authority guard to `_ready()`**

In `player/player.gd`, modify `_ready()` (line 123) to add authority check after existing code:

After line 142 (`equip_weapon(weapon_index)`), add:

```gdscript
	# Multiplayer: disable input/camera for non-local players
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		set_process_input(false)
		set_process_unhandled_input(false)
		camera.current = false
		third_person_camera.current = false
		# Force third-person model visible for remote players
		call_deferred("_setup_remote_player")
```

Add new function:

```gdscript
func _setup_remote_player():
	if tp_model:
		tp_model.visible = true
	if fps_arms:
		fps_arms.visible = false
	weapon_container.visible = false
```

**Step 2: Guard `_input()` and `_physics_process()`**

At the top of `_input()` (line 407), add:

```gdscript
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
```

At the top of `_physics_process()` (line 279), add:

```gdscript
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		# Remote player: just apply synced position (handled by MultiplayerSynchronizer)
		return
```

**Step 3: Add multiplayer shooting RPCs**

Replace the `shoot()` function's hit detection section. After the existing raycast hit logic (inside the `else` block starting at line 624), wrap the damage call with multiplayer awareness.

Add these new RPC functions at the end of `player.gd`:

```gdscript
# --- Multiplayer RPCs ---

func is_in_multiplayer() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

@rpc("any_peer", "reliable")
func request_shot_server(origin: Vector3, direction: Vector3, weapon_idx: int):
	# Server-side shot validation
	if not multiplayer.is_server():
		return
	var shooter_id = multiplayer.get_remote_sender_id()
	var w = weapons[weapon_idx] if weapon_idx < weapons.size() else null
	if w == null:
		return

	var space_state = get_world_3d().direct_space_state
	for _i in w.shot_count:
		var spread_dir = direction
		spread_dir.x += randf_range(-w.spread, w.spread) * 0.01
		spread_dir.y += randf_range(-w.spread, w.spread) * 0.01
		spread_dir = spread_dir.normalized()

		var query = PhysicsRayQueryParameters3D.create(origin, origin + spread_dir * w.max_distance)
		query.exclude = [get_rid()]
		var result = space_state.intersect_ray(query)
		if result:
			var collider = result.collider
			# Check if we hit another player
			if collider is CharacterBody3D and collider.has_method("take_damage") and collider != self:
				var victim_id = collider.get_meta("peer_id", -1)
				if victim_id > 0:
					collider.take_damage(w.damage)
					_broadcast_hit.rpc(victim_id, w.damage, result.position, result.normal)
					if collider.health <= 0:
						_broadcast_kill.rpc(shooter_id, victim_id)
			else:
				# Hit world geometry
				_broadcast_impact.rpc(result.position, result.normal)

@rpc("authority", "call_local", "reliable")
func _broadcast_hit(victim_id: int, damage: float, hit_pos: Vector3, hit_normal: Vector3):
	spawn_impact(hit_pos, hit_normal)

@rpc("authority", "call_local", "reliable")
func _broadcast_impact(hit_pos: Vector3, hit_normal: Vector3):
	spawn_impact(hit_pos, hit_normal)

@rpc("authority", "call_local", "reliable")
func _broadcast_kill(killer_id: int, victim_id: int):
	# MatchManager will handle scoring
	var match_mgr = get_tree().get_first_node_in_group("match_manager")
	if match_mgr and match_mgr.has_method("on_player_killed"):
		match_mgr.on_player_killed(killer_id, victim_id)
```

**Step 4: Modify `shoot()` to use RPCs in multiplayer**

In the `shoot()` function, after the recoil and weapon kickback code (around line 593), before the rocket launcher check, add a multiplayer branch:

```gdscript
	# Multiplayer: send shot to server for validation
	if is_in_multiplayer():
		var shot_origin = camera.global_position
		var shot_dir = -camera.global_basis.z
		request_shot_server.rpc_id(1, shot_origin, shot_dir, weapon_index)
		return  # Server handles hit detection
```

**Step 5: Modify `die()` for multiplayer**

Replace the `die()` function (line 867):

```gdscript
func die():
	stop_gun_sound()
	if is_in_multiplayer():
		# In multiplayer, death is handled by match_manager
		# Just disable input during death
		return
	get_tree().reload_current_scene()
```

**Step 6: Add player to "player" group in _ready**

At the start of `_ready()`, ensure the player is in the group (it may already be set in the scene, but ensure it programmatically):

```gdscript
	add_to_group("player")
```

**Step 7: Verify**

Open the project in Godot. Run arena level in single-player mode. Confirm nothing is broken — movement, shooting, damage all work as before (since `is_in_multiplayer()` returns false in single-player).

**Step 8: Commit**

```bash
git add player/player.gd
git commit -m "feat: add multiplayer authority guards and shot RPCs to player"
```

---

### Task 6: Create MatchManager

**Files:**
- Create: `multiplayer/match_manager.gd`

**Step 1: Create the match manager script**

This manages scoring, timers, death/respawn, and match flow. It gets added as a node to the deathmatch level.

Create `multiplayer/match_manager.gd`:

```gdscript
extends Node
class_name MatchManager

var scores := {}  # { peer_id: { "kills": int, "deaths": int } }
var match_time_remaining := 600.0
var kill_limit := 20
var match_active := false
var countdown_active := false
var countdown_time := 3.0

# Death tracking
var dead_players := {}  # { peer_id: respawn_timer }
var respawn_delay := 4.0

signal scores_updated(scores: Dictionary)
signal match_started
signal match_ended(winner_id: int, final_scores: Dictionary)
signal player_killed(killer_id: int, victim_id: int)
signal countdown_tick(seconds: int)

func _ready():
	add_to_group("match_manager")
	kill_limit = NetworkManager.match_kill_limit
	match_time_remaining = NetworkManager.match_time_limit

	# Initialize scores for all players
	for peer_id in NetworkManager.players:
		scores[peer_id] = {"kills": 0, "deaths": 0}

	if NetworkManager.is_host():
		# Start countdown
		start_countdown()

func start_countdown():
	countdown_active = true
	countdown_time = 3.0
	_sync_countdown.rpc(3)

func _physics_process(delta):
	if not NetworkManager.is_host():
		return

	if countdown_active:
		countdown_time -= delta
		var sec = ceili(countdown_time)
		if countdown_time <= 0:
			countdown_active = false
			match_active = true
			_sync_match_start.rpc()
		return

	if not match_active:
		return

	# Match timer
	match_time_remaining -= delta
	if fmod(match_time_remaining, 1.0) < delta:
		_sync_time.rpc(match_time_remaining)

	if match_time_remaining <= 0:
		end_match()

	# Process respawn timers
	var to_respawn := []
	for peer_id in dead_players:
		dead_players[peer_id] -= delta
		if dead_players[peer_id] <= 0:
			to_respawn.append(peer_id)
	for peer_id in to_respawn:
		dead_players.erase(peer_id)
		var level = get_parent()
		if level.has_method("respawn_player"):
			level.respawn_player(peer_id)
		_sync_respawn.rpc(peer_id)

func on_player_killed(killer_id: int, victim_id: int):
	if not NetworkManager.is_host():
		return
	if not scores.has(killer_id):
		scores[killer_id] = {"kills": 0, "deaths": 0}
	if not scores.has(victim_id):
		scores[victim_id] = {"kills": 0, "deaths": 0}

	scores[killer_id]["kills"] += 1
	scores[victim_id]["deaths"] += 1

	# Start respawn timer
	dead_players[victim_id] = respawn_delay

	# Broadcast
	var killer_name = NetworkManager.get_player_name(killer_id)
	var victim_name = NetworkManager.get_player_name(victim_id)
	_sync_kill.rpc(killer_id, victim_id, killer_name, victim_name, scores)

	# Check win condition
	if scores[killer_id]["kills"] >= kill_limit:
		end_match()

func end_match():
	if not match_active:
		return
	match_active = false

	# Find winner (most kills)
	var winner_id := -1
	var max_kills := -1
	for peer_id in scores:
		if scores[peer_id]["kills"] > max_kills:
			max_kills = scores[peer_id]["kills"]
			winner_id = peer_id

	_sync_match_end.rpc(winner_id, scores)

# --- RPCs ---

@rpc("authority", "call_local", "reliable")
func _sync_countdown(seconds: int):
	countdown_tick.emit(seconds)

@rpc("authority", "call_local", "reliable")
func _sync_match_start():
	match_active = true
	match_started.emit()

@rpc("authority", "call_local", "reliable")
func _sync_time(time: float):
	match_time_remaining = time

@rpc("authority", "call_local", "reliable")
func _sync_kill(killer_id: int, victim_id: int, killer_name: String, victim_name: String, new_scores: Dictionary):
	scores = new_scores
	player_killed.emit(killer_id, victim_id)
	scores_updated.emit(scores)

@rpc("authority", "call_local", "reliable")
func _sync_respawn(peer_id: int):
	# Re-enable the player
	pass  # deathmatch_level handles the actual teleport

@rpc("authority", "call_local", "reliable")
func _sync_match_end(winner_id: int, final_scores: Dictionary):
	match_active = false
	scores = final_scores
	match_ended.emit(winner_id, final_scores)

	# Return to lobby after 10 seconds
	await get_tree().create_timer(10.0).timeout
	NetworkManager.return_to_lobby()
```

**Step 2: Add MatchManager to deathmatch_level.gd**

In `multiplayer/deathmatch_level.gd`, in `_ready()`, after collecting spawn points and before spawning players, add:

```gdscript
	# Add match manager
	var match_mgr = MatchManager.new()
	match_mgr.name = "MatchManager"
	add_child(match_mgr)
```

**Step 3: Commit**

```bash
git add multiplayer/match_manager.gd multiplayer/deathmatch_level.gd
git commit -m "feat: add MatchManager for scoring, timers, and match flow"
```

---

### Task 7: Create Multiplayer HUD Overlay

**Files:**
- Create: `multiplayer/mp_hud.gd`
- Create: `multiplayer/mp_hud.tscn`

**Step 1: Create the multiplayer HUD script**

This provides the match timer, kill feed, scoreboard overlay, death screen, and match results. It layers on top of the existing single-player HUD.

Create `multiplayer/mp_hud.gd`:

```gdscript
extends CanvasLayer

var timer_label: Label
var kill_feed: VBoxContainer
var scoreboard_panel: PanelContainer
var scoreboard_list: VBoxContainer
var death_overlay: ColorRect
var death_label: Label
var result_panel: PanelContainer
var result_label: Label
var countdown_label: Label

var match_manager: MatchManager

func _ready():
	layer = 10
	_build_ui()
	await get_tree().process_frame
	match_manager = get_tree().get_first_node_in_group("match_manager")
	if match_manager:
		match_manager.scores_updated.connect(_on_scores_updated)
		match_manager.player_killed.connect(_on_player_killed)
		match_manager.match_started.connect(_on_match_started)
		match_manager.match_ended.connect(_on_match_ended)
		match_manager.countdown_tick.connect(_on_countdown_tick)

func _process(_delta):
	# Update timer
	if match_manager and match_manager.match_active:
		var mins = int(match_manager.match_time_remaining) / 60
		var secs = int(match_manager.match_time_remaining) % 60
		timer_label.text = "%d:%02d" % [mins, secs]

	# Toggle scoreboard
	if Input.is_action_pressed("scoreboard"):
		scoreboard_panel.visible = true
		_refresh_scoreboard()
	else:
		scoreboard_panel.visible = false

func _build_ui():
	# Match timer (top center)
	timer_label = Label.new()
	timer_label.text = "10:00"
	var timer_settings = LabelSettings.new()
	timer_settings.font_size = 32
	timer_settings.font_color = Color(1, 1, 1)
	timer_settings.outline_size = 3
	timer_settings.outline_color = Color(0, 0, 0)
	timer_label.label_settings = timer_settings
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.offset_top = 10
	timer_label.offset_left = -40
	timer_label.offset_right = 40
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(timer_label)

	# Kill feed (top right)
	kill_feed = VBoxContainer.new()
	kill_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_feed.offset_left = -300
	kill_feed.offset_top = 10
	kill_feed.offset_right = -10
	kill_feed.offset_bottom = 200
	kill_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(kill_feed)

	# Countdown label (center)
	countdown_label = Label.new()
	countdown_label.text = ""
	var cd_settings = LabelSettings.new()
	cd_settings.font_size = 72
	cd_settings.font_color = Color(1, 0.9, 0.2)
	cd_settings.outline_size = 5
	cd_settings.outline_color = Color(0, 0, 0)
	countdown_label.label_settings = cd_settings
	countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	countdown_label.offset_left = -100
	countdown_label.offset_right = 100
	countdown_label.offset_top = -50
	countdown_label.offset_bottom = 50
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.visible = false
	add_child(countdown_label)

	# Scoreboard (Tab overlay)
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.offset_left = -250
	scoreboard_panel.offset_top = -150
	scoreboard_panel.offset_right = 250
	scoreboard_panel.offset_bottom = 150
	scoreboard_panel.visible = false
	var sb_style = StyleBoxFlat.new()
	sb_style.bg_color = Color(0, 0, 0, 0.8)
	sb_style.corner_radius_top_left = 8
	sb_style.corner_radius_top_right = 8
	sb_style.corner_radius_bottom_left = 8
	sb_style.corner_radius_bottom_right = 8
	sb_style.content_margin_left = 20
	sb_style.content_margin_top = 20
	sb_style.content_margin_right = 20
	sb_style.content_margin_bottom = 20
	scoreboard_panel.add_theme_stylebox_override("panel", sb_style)
	add_child(scoreboard_panel)

	scoreboard_list = VBoxContainer.new()
	scoreboard_list.add_theme_constant_override("separation", 6)
	scoreboard_panel.add_child(scoreboard_list)

	# Death overlay
	death_overlay = ColorRect.new()
	death_overlay.color = Color(0.3, 0, 0, 0.5)
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.visible = false
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(death_overlay)

	death_label = Label.new()
	var dl_settings = LabelSettings.new()
	dl_settings.font_size = 36
	dl_settings.font_color = Color(1, 1, 1)
	dl_settings.outline_size = 4
	dl_settings.outline_color = Color(0, 0, 0)
	death_label.label_settings = dl_settings
	death_label.set_anchors_preset(Control.PRESET_CENTER)
	death_label.offset_left = -200
	death_label.offset_right = 200
	death_label.offset_top = -30
	death_label.offset_bottom = 30
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.visible = false
	add_child(death_label)

	# Result panel
	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.offset_left = -200
	result_panel.offset_top = -100
	result_panel.offset_right = 200
	result_panel.offset_bottom = 100
	result_panel.visible = false
	var rp_style = StyleBoxFlat.new()
	rp_style.bg_color = Color(0, 0, 0, 0.9)
	rp_style.corner_radius_top_left = 8
	rp_style.corner_radius_top_right = 8
	rp_style.corner_radius_bottom_left = 8
	rp_style.corner_radius_bottom_right = 8
	rp_style.content_margin_left = 20
	rp_style.content_margin_top = 20
	rp_style.content_margin_right = 20
	rp_style.content_margin_bottom = 20
	result_panel.add_theme_stylebox_override("panel", rp_style)
	add_child(result_panel)

	result_label = Label.new()
	var rl_settings = LabelSettings.new()
	rl_settings.font_size = 28
	rl_settings.font_color = Color(1, 0.9, 0.2)
	rl_settings.outline_size = 3
	rl_settings.outline_color = Color(0, 0, 0)
	result_label.label_settings = rl_settings
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_panel.add_child(result_label)

func _refresh_scoreboard():
	for child in scoreboard_list.get_children():
		child.queue_free()

	# Header
	var header = Label.new()
	header.text = "Player                 Kills   Deaths"
	header.add_theme_font_size_override("font_size", 18)
	scoreboard_list.add_child(header)

	if match_manager == null:
		return

	# Sort by kills descending
	var sorted_ids = match_manager.scores.keys()
	sorted_ids.sort_custom(func(a, b):
		return match_manager.scores[a]["kills"] > match_manager.scores[b]["kills"]
	)

	for peer_id in sorted_ids:
		var info = match_manager.scores[peer_id]
		var pname = NetworkManager.get_player_name(peer_id)
		var label = Label.new()
		label.text = "%-20s %5d   %5d" % [pname, info["kills"], info["deaths"]]
		label.add_theme_font_size_override("font_size", 16)
		if peer_id == multiplayer.get_unique_id():
			label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		scoreboard_list.add_child(label)

func _add_kill_feed_entry(text: String):
	var label = Label.new()
	label.text = text
	var settings = LabelSettings.new()
	settings.font_size = 16
	settings.font_color = Color(1, 1, 1)
	settings.outline_size = 2
	settings.outline_color = Color(0, 0, 0)
	label.label_settings = settings
	kill_feed.add_child(label)

	# Remove after 5 seconds
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(label):
		label.queue_free()

	# Keep max 5 entries
	while kill_feed.get_child_count() > 5:
		kill_feed.get_child(0).queue_free()

func show_death_screen(killer_name: String):
	death_overlay.visible = true
	death_label.visible = true
	death_label.text = "Killed by %s" % killer_name
	await get_tree().create_timer(4.0).timeout
	death_overlay.visible = false
	death_label.visible = false

func _on_scores_updated(_scores: Dictionary):
	pass  # Scoreboard refreshes on Tab press

func _on_player_killed(killer_id: int, victim_id: int):
	var killer_name = NetworkManager.get_player_name(killer_id)
	var victim_name = NetworkManager.get_player_name(victim_id)
	_add_kill_feed_entry("%s killed %s" % [killer_name, victim_name])

	# Show death screen if we're the victim
	if victim_id == multiplayer.get_unique_id():
		show_death_screen(killer_name)

func _on_match_started():
	countdown_label.visible = false
	timer_label.visible = true

func _on_match_ended(winner_id: int, final_scores: Dictionary):
	var winner_name = NetworkManager.get_player_name(winner_id)
	result_label.text = "%s wins!\n\nReturning to lobby..." % winner_name
	result_panel.visible = true

func _on_countdown_tick(seconds: int):
	countdown_label.visible = true
	countdown_label.text = str(seconds)
	if seconds <= 0:
		countdown_label.text = "GO!"
		await get_tree().create_timer(0.5).timeout
		countdown_label.visible = false
```

**Step 2: Create the multiplayer HUD scene**

Create `multiplayer/mp_hud.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://multiplayer/mp_hud.gd" id="1"]

[node name="MultiplayerHUD" type="CanvasLayer"]
script = ExtResource("1")
```

**Step 3: Add MP HUD to deathmatch_level.gd**

In `multiplayer/deathmatch_level.gd`, in `_ready()`, after adding the MatchManager:

```gdscript
	# Add multiplayer HUD
	var mp_hud = preload("res://multiplayer/mp_hud.tscn").instantiate()
	add_child(mp_hud)
```

**Step 4: Commit**

```bash
git add multiplayer/mp_hud.gd multiplayer/mp_hud.tscn multiplayer/deathmatch_level.gd
git commit -m "feat: add multiplayer HUD with timer, kill feed, scoreboard, death screen"
```

---

### Task 8: Add Spawn Points to Arena Map

**Files:**
- Modify: `levels/arena.tscn`

**Step 1: Add SpawnPoint nodes to arena**

Add 6 SpawnPoint nodes at spread-out positions on the Arena map (40x40 floor). Add these nodes to the end of `levels/arena.tscn`:

```
[ext_resource type="Script" path="res://multiplayer/spawn_point.gd" id="8_spawn"]

[node name="SpawnPoint1" type="Node3D" parent="." groups=["spawn_point"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -15, 2, -15)
script = ExtResource("8_spawn")

[node name="SpawnPoint2" type="Node3D" parent="." groups=["spawn_point"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 15, 2, -15)
script = ExtResource("8_spawn")

[node name="SpawnPoint3" type="Node3D" parent="." groups=["spawn_point"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -15, 2, 15)
script = ExtResource("8_spawn")

[node name="SpawnPoint4" type="Node3D" parent="." groups=["spawn_point"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 15, 2, 15)
script = ExtResource("8_spawn")

[node name="SpawnPoint5" type="Node3D" parent="." groups=["spawn_point"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0)
script = ExtResource("8_spawn")

[node name="SpawnPoint6" type="Node3D" parent="." groups=["spawn_point"]]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -5, 2, 10)
script = ExtResource("8_spawn")
```

Note: The ext_resource ID and load_steps in the scene header will need updating. Increment `load_steps` by 1 and use an unused ID for the spawn_point script.

**Step 2: Commit**

```bash
git add levels/arena.tscn
git commit -m "feat: add spawn points to Arena map for multiplayer"
```

---

### Task 9: Create Deathmatch Arena Scene Variant

**Files:**
- Create: `multiplayer/dm_arena.tscn`

Rather than modifying the single-player arena, create a deathmatch variant that uses `deathmatch_level.gd` instead of `base01.gd`. This scene inherits the Arena's geometry but replaces the player/enemy spawning with multiplayer logic.

**Step 1: Create dm_arena.tscn**

This is a minimal scene that references the Arena's map geometry, adds spawn points, and uses the deathmatch level script. Build this programmatically in `deathmatch_level.gd` by loading the base arena scene and reparenting, OR create a standalone scene.

Simpler approach: Update `deathmatch_level.gd` so the lobby's `start_match()` loads the base arena scene and the deathmatch level script attaches spawn points dynamically by searching for SpawnPoint nodes (already done in Task 4). The arena.tscn from Task 8 already has SpawnPoints.

Update `multiplayer/deathmatch_level.gd` to handle the scene transition better:

In `_ready()`, after collecting spawn points, also remove the single-player `Player` node and `HUD` if they exist (since we spawn our own multiplayer players):

```gdscript
	# Remove single-player player and HUD (we spawn our own)
	var sp_player = get_node_or_null("Player")
	if sp_player:
		sp_player.queue_free()
	var sp_hud = get_node_or_null("HUD")
	if sp_hud:
		sp_hud.queue_free()
	var sp_scope = get_node_or_null("ScopeOverlay")
	if sp_scope:
		sp_scope.queue_free()
	# Remove single-player enemies
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.queue_free()
```

However, this means we need the arena scene to use `deathmatch_level.gd` as its script when loaded for multiplayer. The cleanest way: have `NetworkManager._load_match_scene()` set a flag, and in `_ready()` of `deathmatch_level.gd`, attach itself as a script override.

Actually, the simplest approach: have `NetworkManager` load the arena scene, then programmatically attach the deathmatch logic. Update `_load_match_scene`:

In `multiplayer/network_manager.gd`, modify `_load_match_scene`:

```gdscript
@rpc("authority", "call_local", "reliable")
func _load_match_scene(scene_path: String):
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	# Attach deathmatch logic to the loaded scene
	var level = get_tree().current_scene
	var dm_script = load("res://multiplayer/deathmatch_level.gd")
	level.set_script(dm_script)
	level._ready()  # Re-run ready with new script
	_notify_loaded.rpc_id(1)
```

Wait — this approach is fragile. Better approach: just change the existing level script at runtime or use a wrapper. Let me simplify.

**Best approach:** Make `deathmatch_level.gd` a standalone Node3D that gets added as a child of the loaded scene. It finds spawn points, removes SP-only nodes, and manages multiplayer.

Update the plan: In `_load_match_scene`, after loading the scene, add a DeathmatchLevel node:

```gdscript
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
```

**Step 2: Commit**

```bash
git add multiplayer/deathmatch_level.gd multiplayer/network_manager.gd
git commit -m "feat: integrate deathmatch controller with level loading"
```

---

### Task 10: Add MultiplayerSynchronizer to Player

**Files:**
- Modify: `player/player.tscn`

**Step 1: Add MultiplayerSynchronizer node**

Add a `MultiplayerSynchronizer` to `player.tscn` that replicates position, rotation, and key state. Add to end of `player/player.tscn`:

```
[node name="MultiplayerSynchronizer" type="MultiplayerSynchronizer" parent="."]
replication_config = SubResource("SceneReplicationConfig_1")
```

And add the SubResource for replication config:

```
[sub_resource type="SceneReplicationConfig" id="SceneReplicationConfig_1"]
properties/0/path = NodePath(".:position")
properties/0/spawn = true
properties/0/replication_mode = 1
properties/1/path = NodePath(".:rotation")
properties/1/spawn = true
properties/1/replication_mode = 1
properties/2/path = NodePath("Head:rotation")
properties/2/spawn = true
properties/2/replication_mode = 1
```

Note: Editing .tscn files directly for MultiplayerSynchronizer config is fragile. It's better to configure this in the Godot editor. The implementation step should open `player.tscn` in the editor, add a MultiplayerSynchronizer child node, and configure replication for: `position`, `rotation`, `Head:rotation`.

**Step 2: Commit**

```bash
git add player/player.tscn
git commit -m "feat: add MultiplayerSynchronizer to player scene"
```

---

### Task 11: Multiplayer Weapon Pickups

**Files:**
- Create: `multiplayer/weapon_spawner.gd`

**Step 1: Create weapon spawner script**

This script manages timed weapon spawns at fixed map positions, server-authoritative.

Create `multiplayer/weapon_spawner.gd`:

```gdscript
extends Node

var weapon_paths := [
	"res://weapons/m4a1.tres",
	"res://weapons/ak47.tres",
	"res://weapons/shotgun.tres",
	"res://weapons/sniper_rifle.tres",
	"res://weapons/scar.tres",
	"res://weapons/p90.tres",
	"res://weapons/strela.tres",
]

var spawn_interval := 30.0
var spawn_timer := 30.0
var pickup_scene := preload("res://pickups/weapon_pickup.tscn")

func _ready():
	if not NetworkManager.is_host():
		set_process(false)

func _process(delta):
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_timer = spawn_interval
		_spawn_random_weapon()

func _spawn_random_weapon():
	# Find spawn points to place weapons near
	var spawn_points = get_tree().get_nodes_in_group("spawn_point")
	if spawn_points.is_empty():
		return
	var sp = spawn_points[randi() % spawn_points.size()]
	var pos = sp.global_position + Vector3(randf_range(-2, 2), 0.8, randf_range(-2, 2))
	var weapon_path = weapon_paths[randi() % weapon_paths.size()]
	_do_spawn_weapon.rpc(pos, weapon_path)

@rpc("authority", "call_local", "reliable")
func _do_spawn_weapon(pos: Vector3, weapon_path: String):
	var pickup = pickup_scene.instantiate()
	pickup.weapon_resource_path = weapon_path
	get_tree().current_scene.add_child(pickup)
	pickup.global_position = pos
```

**Step 2: Add to deathmatch_level.gd**

In `deathmatch_level.gd`, in `_ready()`, after adding the match manager and HUD:

```gdscript
	# Add weapon spawner
	var spawner = load("res://multiplayer/weapon_spawner.gd").new()
	spawner.name = "WeaponSpawner"
	add_child(spawner)
```

**Step 3: Commit**

```bash
git add multiplayer/weapon_spawner.gd multiplayer/deathmatch_level.gd
git commit -m "feat: add timed weapon spawner for multiplayer matches"
```

---

### Task 12: Disconnect Handling and Polish

**Files:**
- Modify: `multiplayer/network_manager.gd`
- Modify: `multiplayer/deathmatch_level.gd`

**Step 1: Handle player disconnect during match**

In `network_manager.gd`, update `_on_peer_disconnected`:

```gdscript
func _on_peer_disconnected(id: int):
	players.erase(id)
	player_disconnected.emit(id)
	# Clean up player node if in a match
	var level = get_tree().current_scene
	if level:
		var dm = level.get_node_or_null("DeathmatchController")
		if dm and dm.has_method("remove_player"):
			dm.remove_player(id)
```

In `deathmatch_level.gd`, add:

```gdscript
func remove_player(peer_id: int):
	if player_nodes.has(peer_id):
		var node = player_nodes[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		player_nodes.erase(peer_id)
```

**Step 2: Handle server disconnect (clients return to menu)**

Already handled in `network_manager.gd` via `_on_server_disconnected` signal. The lobby listens to it. For in-match, add to `deathmatch_level.gd._ready()`:

```gdscript
	NetworkManager.server_disconnected.connect(func():
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	)
```

**Step 3: Add name tags above remote players**

In `deathmatch_level.gd`, in `_spawn_player()`, after adding the player, add a name label for remote players:

```gdscript
	if not is_local:
		# Add floating name tag
		var label_3d = Label3D.new()
		label_3d.text = NetworkManager.get_player_name(peer_id)
		label_3d.font_size = 48
		label_3d.position = Vector3(0, 2.2, 0)
		label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_3d.no_depth_test = true
		label_3d.outline_size = 8
		player.add_child(label_3d)
```

**Step 4: Commit**

```bash
git add multiplayer/network_manager.gd multiplayer/deathmatch_level.gd
git commit -m "feat: add disconnect handling and player name tags"
```

---

### Task 13: End-to-End Test

**Step 1: Open Godot editor, run project**

1. Launch the game from main menu
2. Click "Multiplayer" -> "Host Game"
3. Verify lobby appears with your name
4. Open a second instance of the game
5. Click "Multiplayer" -> Enter 127.0.0.1 -> "Join Game"
6. Verify both names appear in lobby
7. Host clicks "Start Match"
8. Verify both players spawn on Arena at different positions
9. Test shooting, damage, kill feed
10. Verify scoreboard on Tab
11. Verify death screen and respawn after 4 seconds
12. Verify match ends at kill limit
13. Verify return to lobby after results

**Step 2: Fix any issues found during testing**

Iterate on bugs discovered during the test. Common issues:
- Player authority not set correctly (check `set_multiplayer_authority`)
- RPC calls failing (check `@rpc` annotations)
- Position not syncing (check MultiplayerSynchronizer config)
- Single-player mode broken (ensure `is_in_multiplayer()` guards work)

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: multiplayer FFA deathmatch - complete initial implementation"
```

extends Node3D

var wave := 0
var kill_count := 0
var zombies_alive := 0
var wave_active := false
var between_waves := false

var kills_for_weapon_drop := 10
var weapon_paths := [
	"res://weapons/m4a1.tres",
	"res://weapons/ak47.tres",
	"res://weapons/shotgun.tres",
	"res://weapons/sniper_rifle.tres",
	"res://weapons/scar.tres",
	"res://weapons/p90.tres",
]

var zombie_scene = preload("res://enemies/zombie.tscn")
var zombie_container: Node3D

func _ready():
	# Load the selected map as a child
	var map_path = "res://levels/arena.tscn"
	if get_tree().has_meta("event_map_path"):
		map_path = get_tree().get_meta("event_map_path")
		get_tree().remove_meta("event_map_path")

	var map = load(map_path).instantiate()
	# Remove the map's own script to prevent enemy spawning conflicts
	map.set_script(null)
	add_child(map)
	move_child(map, 0)

	await get_tree().process_frame

	# Remove existing enemies from the map
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.queue_free()

	# Override atmosphere to dark/foggy
	_setup_dark_atmosphere(map)

	# Add wave HUD labels
	_setup_hud_labels(map)

	# Add zombie container
	zombie_container = Node3D.new()
	zombie_container.name = "ZombieContainer"
	add_child(zombie_container)

	# Start first wave after a delay
	get_tree().create_timer(3.0).timeout.connect(_start_next_wave)

func _setup_dark_atmosphere(map: Node):
	# Find and replace the WorldEnvironment
	var world_env = _find_node_by_type(map, "WorldEnvironment")
	if world_env:
		var sky_mat = ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.02, 0.02, 0.06)
		sky_mat.sky_horizon_color = Color(0.05, 0.04, 0.08)
		sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
		sky_mat.ground_horizon_color = Color(0.05, 0.04, 0.08)

		var sky = Sky.new()
		sky.sky_material = sky_mat

		var env = world_env.environment
		if env == null:
			env = Environment.new()
		env = env.duplicate()
		env.background_mode = 2  # BG_SKY
		env.sky = sky
		env.ambient_light_source = 3  # AMBIENT_LIGHT_SKY
		env.ambient_light_color = Color(0.1, 0.1, 0.15)
		env.ambient_light_energy = 0.3
		env.fog_enabled = true
		env.fog_light_color = Color(0.08, 0.06, 0.1)
		env.fog_density = 0.015
		world_env.environment = env

	# Dim the directional light to moonlight
	var sun = _find_node_by_type(map, "DirectionalLight3D")
	if sun:
		sun.light_color = Color(0.6, 0.65, 0.8)
		sun.light_energy = 0.6

func _setup_hud_labels(map: Node):
	var hud = _find_node_by_name(map, "HUD")
	if hud == null:
		return

	# Wave label — top center
	var wave_label = Label.new()
	wave_label.name = "WaveLabel"
	wave_label.text = "Wave 1"
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wave_settings = LabelSettings.new()
	wave_settings.font_size = 32
	wave_settings.font_color = Color(1, 0.3, 0.3)
	wave_settings.outline_size = 3
	wave_settings.outline_color = Color(0, 0, 0)
	wave_label.label_settings = wave_settings
	wave_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wave_label.offset_left = -150
	wave_label.offset_top = 10
	wave_label.offset_right = 150
	wave_label.offset_bottom = 50
	hud.add_child(wave_label)

	# Remaining label — below wave
	var remaining_label = Label.new()
	remaining_label.name = "RemainingLabel"
	remaining_label.text = "Zombies: 0"
	remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rem_settings = LabelSettings.new()
	rem_settings.font_size = 20
	rem_settings.font_color = Color(0.8, 0.8, 0.8)
	rem_settings.outline_size = 2
	rem_settings.outline_color = Color(0, 0, 0)
	remaining_label.label_settings = rem_settings
	remaining_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	remaining_label.offset_left = -150
	remaining_label.offset_top = 48
	remaining_label.offset_right = 150
	remaining_label.offset_bottom = 78
	hud.add_child(remaining_label)

func _find_node_by_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.get_class() == type_name:
			return child
	# Check deeper
	for child in root.get_children():
		var found = _find_node_by_type(child, type_name)
		if found:
			return found
	return null

func _find_node_by_name(root: Node, node_name: String) -> Node:
	for child in root.get_children():
		if child.name == node_name:
			return child
	for child in root.get_children():
		var found = _find_node_by_name(child, node_name)
		if found:
			return found
	return null

func _start_next_wave():
	wave += 1
	var spawn_count = 3 + wave * 2
	zombies_alive = spawn_count
	wave_active = true
	between_waves = false

	_update_hud()

	for i in spawn_count:
		get_tree().create_timer(i * 0.3).timeout.connect(func():
			if is_inside_tree():
				_spawn_zombie()
		)

func _spawn_zombie():
	if not is_inside_tree():
		return
	var zombie = zombie_scene.instantiate()

	# Scale difficulty per wave
	zombie.move_speed += wave * 0.3
	zombie.health += wave * 8
	zombie.damage += wave * 2

	# Spawn around the player or map center
	var player = get_tree().get_first_node_in_group("player")
	var center = Vector3.ZERO
	if player:
		center = player.global_position
		center.y = 0

	var angle = randf() * TAU
	var dist = randf_range(15.0, 25.0)
	var spawn_pos = center + Vector3(cos(angle) * dist, 2, sin(angle) * dist)

	zombie_container.add_child(zombie)
	zombie.global_position = spawn_pos

	await get_tree().process_frame
	_connect_zombie(zombie)

func _connect_zombie(zombie: Node):
	if zombie.has_signal("enemy_died") and not zombie.enemy_died.is_connected(_on_zombie_killed):
		zombie.enemy_died.connect(_on_zombie_killed)

func _on_zombie_killed():
	kill_count += 1
	zombies_alive -= 1

	_update_hud()

	# Weapon drop
	if kill_count % kills_for_weapon_drop == 0:
		_spawn_weapon_reward()

	# All zombies dead — start next wave
	if zombies_alive <= 0 and wave_active:
		wave_active = false
		between_waves = true
		_update_hud()
		get_tree().create_timer(3.0).timeout.connect(_start_next_wave)

func _spawn_weapon_reward():
	if not is_inside_tree():
		return
	var pickup_scene = preload("res://pickups/weapon_pickup.tscn")
	var pickup = pickup_scene.instantiate()
	var weapon_path = weapon_paths[randi() % weapon_paths.size()]
	pickup.weapon_resource_path = weapon_path
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var offset = Vector3(randf_range(-3, 3), 0.8, randf_range(-3, 3))
		pickup.global_position = player.global_position + offset
	else:
		pickup.global_position = Vector3(0, 1, 0)
	add_child(pickup)
	if player and player.has_signal("notification_show"):
		var weapon_res = load(weapon_path)
		if weapon_res:
			player.notification_show.emit("Weapon drop! " + weapon_res.weapon_name)

func _update_hud():
	# Find HUD anywhere in the tree
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		# Try by name
		for node in get_tree().root.get_children():
			hud = _find_node_by_name(node, "HUD")
			if hud:
				break
	if hud == null:
		return

	var wave_label = hud.get_node_or_null("WaveLabel")
	if wave_label:
		if between_waves:
			wave_label.text = "Wave " + str(wave) + " cleared!"
		else:
			wave_label.text = "Wave " + str(wave)

	var kill_label = hud.get_node_or_null("KillCounter")
	if kill_label:
		kill_label.text = "Kills: " + str(kill_count)

	var remaining_label = hud.get_node_or_null("RemainingLabel")
	if remaining_label:
		if between_waves:
			remaining_label.text = "Next wave incoming..."
		else:
			remaining_label.text = "Zombies: " + str(zombies_alive)

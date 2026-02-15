extends CharacterBody3D

@export var move_speed := 6.0
@export var chase_speed := 7.5
@export var attack_range := 15.0  # Shooting range
@export var detection_range := 25.0
@export var health := 100.0
@export var gun_damage := 8.0
@export var fire_rate := 0.5  # Seconds between shots
@export var accuracy := 0.85  # 0-1, higher = more accurate
@export var is_sniper := false  # Stationary sniper on guard towers
@export var has_shield := false  # Riot shield - takes less damage
@export var is_boss := false  # Boss enemy with shotgun and healthbar
@export var gun_type := ""  # rifle, smg, shotgun, marksman — empty = random

var player: Node3D = null
var gravity := 20.0
var current_state := "idle"
var fire_timer := 0.0
var rotation_speed := 8.0  # How fast enemy turns to face player
var max_health := 100.0

# Boss healthbar
var boss_bar_bg: MeshInstance3D
var boss_bar_fg: MeshInstance3D
var boss_bar_node: Node3D

# Shield visual
var shield_mesh: MeshInstance3D

@onready var raycast: RayCast3D = $RayCast3D
@onready var anim_player: AnimationPlayer = $SoldierModel/AnimationPlayer
@onready var skeleton: Skeleton3D = $SoldierModel/Skeleton3D

var anim_name := ""
var last_state := ""

var _enemy_scene = preload("res://enemies/enemy.tscn")
var _ammo_pickup_scene = preload("res://pickups/ammo_pickup.tscn")

signal enemy_died

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

	# Randomize gun type if not set
	if gun_type == "" and not is_sniper and not is_boss:
		var types = ["rifle", "rifle", "smg", "smg", "shotgun", "marksman"]
		gun_type = types[randi() % types.size()]

	# Apply gun type stats
	match gun_type:
		"smg":
			gun_damage = 5.0
			fire_rate = 0.15
			accuracy = 0.7
			attack_range = 12.0
			chase_speed = 8.5
			move_speed = 7.0
		"shotgun":
			gun_damage = 12.0
			fire_rate = 0.8
			accuracy = 0.6
			attack_range = 10.0
			chase_speed = 7.0
			move_speed = 5.5
		"marksman":
			gun_damage = 18.0
			fire_rate = 1.0
			accuracy = 0.92
			attack_range = 30.0
			detection_range = 40.0
			chase_speed = 5.5
			move_speed = 4.5

	# Apply sniper overrides
	if is_sniper:
		detection_range = 55.0
		attack_range = 50.0
		accuracy = 0.92
		fire_rate = 1.5
		gun_damage = 20.0
		chase_speed = 0.0
		move_speed = 0.0

	# Apply shield overrides
	if has_shield:
		health = 250.0
		move_speed = 2.5
		chase_speed = 3.0
		_create_shield_visual()

	# Apply boss overrides
	if is_boss:
		health = 500.0
		gun_damage = 10.0
		fire_rate = 0.7
		accuracy = 0.75
		detection_range = 45.0
		attack_range = 20.0
		chase_speed = 3.0
		_create_boss_healthbar()

	max_health = health

	# Setup animations
	if anim_player:
		if anim_player.has_animation("mixamo_com"):
			anim_name = "mixamo_com"
			var anim = anim_player.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
			_strip_root_motion(anim)
		elif anim_player.has_animation("Take 001"):
			anim_name = "Take 001"
			var anim = anim_player.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
			_strip_root_motion(anim)

		# Start in idle pose
		if anim_name != "":
			anim_player.play(anim_name)
			anim_player.seek(0, true)
			anim_player.pause()

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# If dead, freeze in place — skip all AI
	if is_dead:
		velocity = Vector3.ZERO
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	
	var distance_to_player = global_position.distance_to(player.global_position)

	# Stealth detection - crouching reduces detection range, shooting gives you away
	var effective_detection = detection_range
	var effective_attack = attack_range
	var player_is_crouching = player.get("is_crouching") == true
	var player_noise = player.get("noise_level")
	if player_noise == null:
		player_noise = 0.0

	if player_noise > 50.0:
		# Shooting - enemies hear from very far away
		effective_detection = 60.0
		effective_attack = attack_range
	elif player_is_crouching:
		# Crouching and quiet - much harder to detect
		effective_detection = detection_range * 0.35
		effective_attack = attack_range * 0.5

	# State machine
	if is_sniper:
		# Snipers never move - they only attack from their position
		if distance_to_player <= effective_attack:
			current_state = "attack"
		else:
			current_state = "idle"
	else:
		if distance_to_player <= effective_attack:
			current_state = "attack"
		elif distance_to_player <= effective_detection:
			current_state = "chase"
		else:
			current_state = "idle"

	# Handle states
	match current_state:
		"idle":
			velocity.x = 0
			velocity.z = 0
		"chase":
			chase_player(delta)
		"attack":
			attack_player(delta)
	
	# Update animation based on state change
	if current_state != last_state:
		last_state = current_state
		update_animation()
	
	move_and_slide()
	
	# Smoothly rotate to face player when chasing or attacking
	if current_state in ["chase", "attack"]:
		var look_pos = player.global_position
		look_pos.y = global_position.y
		var target_direction = (look_pos - global_position).normalized()
		var target_angle = atan2(target_direction.x, target_direction.z) + PI
		rotation.y = lerp_angle(rotation.y, target_angle, delta * rotation_speed)

func update_animation():
	if anim_player == null or anim_name == "":
		return

	match current_state:
		"idle":
			if anim_player.is_playing():
				anim_player.pause()
				anim_player.seek(0, true)
		"attack":
			if is_sniper:
				# Snipers stay in idle pose when shooting (no running)
				if anim_player.is_playing():
					anim_player.pause()
					anim_player.seek(0, true)
			else:
				if not anim_player.is_playing():
					anim_player.play(anim_name)
					anim_player.speed_scale = 1.0
		"chase":
			if not anim_player.is_playing():
				anim_player.play(anim_name)
				anim_player.speed_scale = 1.0

func chase_player(_delta):
	var direction = (player.global_position - global_position).normalized()
	direction.y = 0
	velocity.x = direction.x * chase_speed
	velocity.z = direction.z * chase_speed

func attack_player(delta):
	# Stop moving when shooting
	velocity.x = 0
	velocity.z = 0
	
	fire_timer -= delta
	if fire_timer <= 0:
		fire_timer = fire_rate
		shoot_at_player()

func shoot_at_player():
	if raycast == null or player == null:
		return

	# Boss and shotgun enemies fire multiple pellets
	var pellet_count = 1
	if is_boss:
		pellet_count = 5
	elif gun_type == "shotgun":
		pellet_count = 3

	for _i in pellet_count:
		var target_pos = player.global_position + Vector3(0, 1, 0)
		var direction = (target_pos - raycast.global_position).normalized()

		var miss_amount = (1.0 - accuracy) * 0.5
		if is_boss:
			miss_amount *= 2.0  # Boss shotgun has wider spread
		direction.x += randf_range(-miss_amount, miss_amount)
		direction.y += randf_range(-miss_amount, miss_amount)
		direction.z += randf_range(-miss_amount, miss_amount)

		raycast.target_position = direction * 50
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collider = raycast.get_collider()
			if collider and collider.has_method("take_damage"):
				collider.take_damage(gun_damage)

func take_damage(amount: float):
	if has_shield:
		amount *= 0.4  # Shield blocks 60% of damage
	health -= amount
	if is_boss:
		_update_boss_healthbar()
	if health <= 0:
		die()

var is_dead := false

var death_anims := [
	"res://animations/swat/Death.fbx",
	"res://animations/swat/Death From Front Headshot.fbx",
]

func die():
	if is_dead:
		return
	is_dead = true
	enemy_died.emit()

	# Cache position before freeing
	var death_pos = global_position
	var tree = get_tree()
	if tree == null:
		return

	# Spawn ammo pickup at death location
	spawn_ammo_drop(death_pos)

	# Disable AI
	set_process(false)

	# Play a random death animation
	var death_time = _play_death_animation()

	# Free after death animation finishes
	var free_timer = tree.create_timer(death_time)
	free_timer.timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)

	# Respawn after delay
	var respawn_timer = tree.create_timer(death_time + 2.0)
	respawn_timer.timeout.connect(func():
		if not is_instance_valid(tree) or not tree.root:
			return
		var level = tree.current_scene
		if level and level.has_method("respawn_enemy"):
			level.respawn_enemy(Vector3.ZERO)
		elif is_instance_valid(level):
			var new_enemy = _enemy_scene.instantiate()
			new_enemy.global_position = Vector3(
				randf_range(-30, 30),
				1,
				randf_range(-30, 30)
			)
			tree.root.add_child(new_enemy)
	)

func _play_death_animation() -> float:
	if anim_player == null:
		return 0.5

	# Pick a random death FBX and extract its animation
	var death_path = death_anims[randi() % death_anims.size()]
	var death_scene = load(death_path)
	if death_scene == null:
		return 0.5

	var temp = death_scene.instantiate()
	var temp_ap = temp.get_node_or_null("AnimationPlayer")
	if temp_ap == null:
		temp.free()
		return 0.5

	# Get the mixamo_com animation from the death FBX
	var src_anim_name = "mixamo_com"
	if not temp_ap.has_animation(src_anim_name):
		# Fallback to first available
		var list = temp_ap.get_animation_list()
		if list.size() == 0:
			temp.free()
			return 0.5
		src_anim_name = list[0]

	var death_anim = temp_ap.get_animation(src_anim_name).duplicate()
	temp.free()

	# Don't loop the death animation
	death_anim.loop_mode = Animation.LOOP_NONE

	# Remove Hips position tracks entirely — only rotations play
	# This keeps the model in place (like the run anim) while bones animate the death pose
	var tracks_to_remove := []
	for i in death_anim.get_track_count():
		var path = str(death_anim.track_get_path(i))
		if "Hips" in path and death_anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			tracks_to_remove.append(i)
	# Remove in reverse order so indices don't shift
	tracks_to_remove.reverse()
	for idx in tracks_to_remove:
		death_anim.remove_track(idx)

	# Add and play the death animation
	var lib = anim_player.get_animation_library("")
	if lib:
		lib.add_animation("death", death_anim)
	else:
		var new_lib = AnimationLibrary.new()
		new_lib.add_animation("death", death_anim)
		anim_player.add_animation_library("", new_lib)

	anim_player.stop()
	anim_player.play("death")
	anim_player.speed_scale = 1.0

	return death_anim.length

func spawn_ammo_drop(pos: Vector3):
	var tree = get_tree()
	if tree == null or tree.root == null:
		return
	var pickup = _ammo_pickup_scene.instantiate()
	pickup.global_position = pos + Vector3(0, 1, 0)
	pickup.ammo_amount = 20
	tree.root.add_child(pickup)

func _create_shield_visual():
	shield_mesh = MeshInstance3D.new()
	shield_mesh.name = "ShieldVisual"
	var box = BoxMesh.new()
	box.size = Vector3(0.8, 1.0, 0.08)
	shield_mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.25, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.8
	mat.roughness = 0.3
	shield_mesh.material_override = mat
	shield_mesh.position = Vector3(-0.35, 1.0, 0.35)
	add_child(shield_mesh)

func _create_boss_healthbar():
	boss_bar_node = Node3D.new()
	boss_bar_node.name = "BossHealthbar"
	boss_bar_node.position = Vector3(0, 2.5, 0)
	add_child(boss_bar_node)

	# Background bar (dark)
	boss_bar_bg = MeshInstance3D.new()
	var bg_mesh = BoxMesh.new()
	bg_mesh.size = Vector3(1.8, 0.18, 0.04)
	boss_bar_bg.mesh = bg_mesh
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.0, 0.0)
	boss_bar_bg.material_override = bg_mat
	boss_bar_node.add_child(boss_bar_bg)

	# Foreground bar (red)
	boss_bar_fg = MeshInstance3D.new()
	var fg_mesh = BoxMesh.new()
	fg_mesh.size = Vector3(1.8, 0.18, 0.05)
	boss_bar_fg.mesh = fg_mesh
	var fg_mat = StandardMaterial3D.new()
	fg_mat.albedo_color = Color(0.9, 0.1, 0.05)
	boss_bar_fg.material_override = fg_mat
	boss_bar_node.add_child(boss_bar_fg)

func _update_boss_healthbar():
	if boss_bar_fg == null:
		return
	var ratio = clamp(health / max_health, 0.0, 1.0)
	boss_bar_fg.scale.x = ratio
	boss_bar_fg.position.x = -(1.0 - ratio) * 0.9

func _process(_delta):
	# Make boss healthbar face camera
	if boss_bar_node and player:
		var cam = player.get_node_or_null("Head/Camera")
		if cam:
			boss_bar_node.look_at(cam.global_position, Vector3.UP)
	# Rotate shield to face player
	if shield_mesh and player:
		var dir = (player.global_position - global_position).normalized()
		shield_mesh.position.z = 0.35
		shield_mesh.position.x = -dir.x * 0.35

func _strip_root_motion(anim: Animation):
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(i):
				var pos = anim.track_get_key_value(i, k)
				# Keep Y (height) but zero X and Z (horizontal drift)
				anim.track_set_key_value(i, k, Vector3(0, pos.y, 0))

func _strip_root_motion_full(anim: Animation):
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var first_pos = anim.track_get_key_value(i, 0)
			for k in anim.track_get_key_count(i):
				# Lock to first frame position — no movement at all
				anim.track_set_key_value(i, k, first_pos)

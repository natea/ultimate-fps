extends CharacterBody3D

@export_subgroup("Properties")
@export var movement_speed = 5.0
@export var sprint_speed = 8.0
@export var jump_strength = 8.0
@export var max_jumps = 2  # Double jump!

@export_subgroup("Weapons")
@export var weapons: Array[Weapon] = []

var weapon: Weapon
var weapon_index := 0
var current_ammo: int = 0
var reserve_ammo: int = 0
var is_reloading := false

var mouse_sensitivity = 700.0
var gamepad_sensitivity := 0.075

var mouse_captured := true

var movement_velocity: Vector3
var rotation_target: Vector3

var input_mouse: Vector2

var gravity := 0.0
var jumps_remaining := 2

var previously_floored := false

var weapon_container_offset := Vector3(0.3, -0.15, -0.4)

var is_aiming := false
var default_fov := 75.0
var ads_speed := 10.0

# Weapon inspect
var is_inspecting := false
var inspect_time := 0.0
var inspect_duration := 2.0

# Gun flip (pistol only)
var is_flipping := false
var flip_time := 0.0
var flip_duration := 0.6

# Reload animation
var reload_anim_time := 0.0

# Crouch
var is_crouching := false
var crouch_speed := 2.5
var stand_head_y := 1.6
var crouch_head_y := 0.9
var stand_collision_height := 1.8
var crouch_collision_height := 1.0

# Stealth / noise
var noise_level := 0.0  # 0 = silent, decays over time
var noise_decay_rate := 30.0  # How fast noise fades per second

# Grenades
var grenades: int = 3
var max_grenades: int = 3
var grenade_cooldown: float = 0.0
var grenade_throw_force := 20.0

var fall_death_y: float = -10.0  # Y threshold for void death, set very low to disable

var health: float = 100.0
var max_health: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0
var stamina_drain_run: float = 15.0  # Per second while sprinting
var stamina_drain_jump: float = 20.0  # Per double jump
var stamina_regen: float = 25.0  # Per second when not using

signal ammo_updated(current: int, reserve: int)
signal weapon_changed(weapon_name: String)
signal health_updated(current: float, max_val: float)
signal stamina_updated(current: float, max_val: float)
signal grenades_updated(current: int, max_val: int)
signal kill_registered(killer_name: String, victim_name: String, weapon_name: String)
signal notification_show(message: String)

@onready var head = $Head
@onready var camera = $Head/Camera
@onready var raycast = $Head/Camera/RayCast3D
@onready var collision_shape = $CollisionShape3D
@onready var weapon_container = $Head/Camera/WeaponContainer
@onready var shoot_cooldown = $ShootCooldown
@onready var reload_timer = $ReloadTimer
@onready var muzzle_flash = $Head/Camera/WeaponContainer/MuzzleFlash
@onready var gun_sound: AudioStreamPlayer = $GunSoundPlayer
@onready var shot_sound: AudioStreamPlayer = $ShotSoundPlayer
@onready var reload_sound: AudioStreamPlayer = $ReloadSoundPlayer
@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer
@onready var shotgun_cock_sound: AudioStreamPlayer = $ShotgunCockPlayer
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var third_person_camera: Camera3D = $Head/SpringArm3D/ThirdPersonCamera
var is_third_person := false
var is_firing_sound := false
var footstep_timer := 0.0
var fps_arms: Node3D
var fps_arms_skeleton: Skeleton3D
var fps_arms_anim: AnimationPlayer
var fps_reload_anim_name := ""
var fps_idle_anim_name := ""

# Third person model
var tp_model: Node3D
var tp_anim_player: AnimationPlayer
var tp_anim_name := ""
var tp_jump_anim_name := ""
var tp_crouch_anim_name := ""
var tp_reload_anim_name := ""
var tp_current_anim := ""

var scope_overlay: CanvasLayer = null

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Find scope overlay in scene
	scope_overlay = get_tree().get_first_node_in_group("scope_overlay")
	
	# Setup FPS arms - hide legs and lower body
	call_deferred("_setup_fps_arms")

	# Setup third-person model (hidden by default)
	call_deferred("_setup_tp_model")

	# Initialize health/stamina/grenades
	health_updated.emit(health, max_health)
	stamina_updated.emit(stamina, max_stamina)
	grenades_updated.emit(grenades, max_grenades)
	
	if weapons.size() > 0:
		weapon = weapons[weapon_index]
		equip_weapon(weapon_index)

func _setup_fps_arms():
	# Instantiate the SWAT model from script
	var arms_scene = load("res://animations/Gunplay.fbx")
	fps_arms = arms_scene.instantiate()
	fps_arms.name = "FPSArms"

	# Position: scaled up to life-size, rotated 180 to face camera, pushed down
	fps_arms.scale = Vector3(100, 100, 100)
	fps_arms.rotation_degrees = Vector3(0, 180, 0)
	fps_arms.position = Vector3(0.1, -1.5, 0.3)

	camera.add_child(fps_arms)

	# Find skeleton - FBX structure may vary
	fps_arms_skeleton = _find_skeleton(fps_arms)
	if fps_arms_skeleton == null:
		print("ERROR: Could not find Skeleton3D in FPS arms")
		return

	print("FPS Arms skeleton found: ", fps_arms_skeleton.get_path())

	# Apply texture to body mesh
	var tex = load("res://animations/Gunplay_0.png")
	if tex == null:
		tex = load("res://animations/Run Forward_0.png")
	if tex:
		var mat = StandardMaterial3D.new()
		mat.albedo_texture = tex
		for child in fps_arms_skeleton.get_children():
			if child is MeshInstance3D:
				print("FPS mesh: ", child.name, " surfaces: ", child.get_surface_override_material_count())
				child.set_surface_override_material(0, mat)
				if child.name.contains("head") or child.name.contains("Head"):
					child.visible = false

	# Hide leg bones by scaling them to near-zero
	for bone_name in ["mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]:
		var idx = fps_arms_skeleton.find_bone(bone_name)
		if idx != -1:
			fps_arms_skeleton.set_bone_pose_scale(idx, Vector3(0.001, 0.001, 0.001))

	# Play the gunplay animation (idle gun hold)
	for child in fps_arms.get_children():
		if child is AnimationPlayer:
			fps_arms_anim = child
			break
	if fps_arms_anim == null:
		fps_arms_anim = _find_node_of_type(fps_arms, "AnimationPlayer") as AnimationPlayer

	if fps_arms_anim:
		for anim_name in fps_arms_anim.get_animation_list():
			print("FPS anim available: ", anim_name)
			var anim = fps_arms_anim.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
			fps_idle_anim_name = anim_name
		if fps_arms_anim.has_animation("mixamo_com"):
			fps_idle_anim_name = "mixamo_com"
			fps_arms_anim.play("mixamo_com")
		elif fps_arms_anim.get_animation_list().size() > 0:
			fps_arms_anim.play(fps_arms_anim.get_animation_list()[0])

		# Load reload animation from FBX
		fps_reload_anim_name = _load_fps_anim("res://animations/Reloading.fbx", "reload", false)

	print("FPS Arms setup complete")

func _setup_tp_model():
	var model_scene = load("res://animations/swat/Run Forward.fbx")
	if model_scene == null:
		print("ERROR: Could not load swat model")
		return

	tp_model = model_scene.instantiate()
	tp_model.name = "ThirdPersonModel"
	tp_model.scale = Vector3(1, 1, 1)
	tp_model.rotation_degrees = Vector3(0, 180, 0)
	tp_model.position = Vector3(0, 0, 0)
	tp_model.visible = false
	add_child(tp_model)

	# Find and setup animation
	tp_anim_player = _find_node_of_type(tp_model, "AnimationPlayer") as AnimationPlayer
	if tp_anim_player:
		for anim_n in tp_anim_player.get_animation_list():
			print("TP anim: ", anim_n)
			var anim = tp_anim_player.get_animation(anim_n)
			anim.loop_mode = Animation.LOOP_LINEAR
			tp_anim_name = anim_n

		# Start in idle pose (pause at frame 0)
		if tp_anim_name != "":
			tp_anim_player.play(tp_anim_name)
			tp_anim_player.seek(0, true)
			tp_anim_player.pause()

	# Strip root motion from animation to prevent jitter
	if tp_anim_player and tp_anim_name != "":
		var anim = tp_anim_player.get_animation(tp_anim_name)
		if anim:
			_strip_root_motion(anim)

	# Load crouch animation
	if tp_anim_player:
		tp_crouch_anim_name = _load_tp_anim("res://animations/Crouch Walking.fbx", "tp_crouch", true)
		tp_reload_anim_name = _load_tp_anim("res://animations/Reloading.fbx", "tp_reload", false)

	print("Third-person model setup complete")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result = _find_node_of_type(child, type_name)
		if result:
			return result
	return null

func _exit_tree():
	# Always restore mouse when scene exits (prevents stuck cursor)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what):
	# Restore mouse when game loses focus (alt-tab, crash, etc.)
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	handle_controls(delta)
	handle_gravity(delta)
	
	# Movement
	var applied_velocity: Vector3
	
	movement_velocity = transform.basis * movement_velocity
	
	applied_velocity = velocity.lerp(movement_velocity, delta * 10)
	applied_velocity.y = -gravity
	
	velocity = applied_velocity

	# Step-up: if on floor and moving, try to climb small ledges
	var was_on_floor = is_on_floor()
	var step_height = 0.35
	if was_on_floor and Vector2(velocity.x, velocity.z).length() > 0.5:
		var pre_pos = global_position
		# Move up
		velocity.y = 0
		global_position.y += step_height
		move_and_slide()
		# Snap back down to floor
		var test_motion = PhysicsTestMotionParameters3D.new()
		test_motion.from = global_transform
		test_motion.motion = Vector3(0, -step_height * 2, 0)
		var result = PhysicsTestMotionResult3D.new()
		if PhysicsServer3D.body_test_motion(get_rid(), test_motion, result):
			global_position.y += result.get_travel().y
		else:
			# No floor found — revert
			global_position = pre_pos
			velocity = applied_velocity
			move_and_slide()
	else:
		move_and_slide()
	
	# Weapon sway and ADS
	if weapon_container:
		var target_pos: Vector3
		if is_aiming and weapon:
			target_pos = weapon.ads_position
		else:
			target_pos = weapon_container_offset - (basis.inverse() * velocity / 40)
		weapon_container.position = lerp(weapon_container.position, target_pos, delta * ads_speed)
	
	# Camera FOV for ADS
	if weapon:
		var target_fov = weapon.ads_fov if is_aiming else default_fov
		camera.fov = lerp(camera.fov, target_fov, delta * ads_speed)
		
		# Scope overlay for sniper
		if weapon.has_scope and is_aiming and not is_third_person:
			if scope_overlay:
				scope_overlay.show_scope()
			weapon_container.visible = false
		elif not is_third_person:
			if scope_overlay:
				scope_overlay.hide_scope()
			weapon_container.visible = true
	
	# Reload animation
	if is_reloading:
		update_reload_anim(delta)

	# Crouch - smoothly lerp head height and collision
	var target_head_y = crouch_head_y if is_crouching else stand_head_y
	head.position.y = lerp(head.position.y, target_head_y, delta * 10.0)
	var target_col_height = crouch_collision_height if is_crouching else stand_collision_height
	var capsule = collision_shape.shape as CapsuleShape3D
	if capsule:
		capsule.height = lerp(capsule.height, target_col_height, delta * 10.0)
		collision_shape.position.y = capsule.height / 2.0

	# Footstep sounds
	if is_on_floor() and velocity.length() > 1.0:
		var step_interval = 0.55 if is_crouching else (0.35 if Input.is_action_pressed("sprint") else 0.45)
		footstep_timer -= delta
		if footstep_timer <= 0.0:
			if footstep_player:
				footstep_player.pitch_scale = randf_range(0.85, 1.15)
				footstep_player.play(0.0)
			footstep_timer = step_interval
	else:
		footstep_timer = 0.0

	# Third-person model animation (skip if reload is playing)
	if is_third_person and tp_model and tp_anim_player and tp_anim_name != "" and tp_current_anim != tp_reload_anim_name:
		var is_moving = velocity.length() > 1.0
		var target_anim := ""

		if is_crouching and is_moving and tp_crouch_anim_name != "":
			target_anim = tp_crouch_anim_name
		elif is_crouching and not is_moving:
			# Crouch idle — pause crouch anim at frame 0
			if tp_crouch_anim_name != "" and tp_current_anim != "crouch_idle":
				tp_anim_player.play(tp_crouch_anim_name)
				tp_anim_player.seek(0, true)
				tp_anim_player.pause()
				tp_current_anim = "crouch_idle"
			target_anim = ""
		elif is_moving and is_on_floor():
			target_anim = tp_anim_name
		else:
			# Standing idle
			if tp_current_anim != "idle":
				tp_anim_player.pause()
				tp_anim_player.seek(0, true)
				tp_current_anim = "idle"
			target_anim = ""

		if target_anim != "" and tp_current_anim != target_anim:
			tp_anim_player.play(target_anim)
			tp_anim_player.speed_scale = 1.0
			tp_current_anim = target_anim

	# Noise decay
	noise_level = max(0.0, noise_level - noise_decay_rate * delta)

	# Landing after jump or falling
	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)

	if is_on_floor() and gravity > 1 and !previously_floored:
		camera.position.y = -0.1

	previously_floored = is_on_floor()

	# Falling/respawning
	if position.y < fall_death_y:
		get_tree().reload_current_scene()

func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		input_mouse = event.relative / mouse_sensitivity
		handle_rotation(event.relative.x, event.relative.y, false)

func handle_controls(delta):
	# Mouse capture
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true
	
	if Input.is_action_just_pressed("mouse_capture_exit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false
		input_mouse = Vector2.ZERO
	
	# Crouch
	if Input.is_action_pressed("crouch"):
		is_crouching = true
	else:
		is_crouching = false

	# Movement
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var is_sprinting = Input.is_action_pressed("sprint") and stamina > 0 and not is_crouching
	var current_speed: float
	if is_crouching:
		current_speed = crouch_speed
	elif is_sprinting:
		current_speed = sprint_speed
	else:
		current_speed = movement_speed
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * current_speed
	
	# Stamina system
	var is_moving = input.length() > 0.1
	if is_sprinting and is_moving:
		stamina -= stamina_drain_run * delta
		stamina = max(0, stamina)
		stamina_updated.emit(stamina, max_stamina)
	elif not is_sprinting:
		stamina += stamina_regen * delta
		stamina = min(max_stamina, stamina)
		stamina_updated.emit(stamina, max_stamina)
	
	# Aim down sights
	is_aiming = Input.is_action_pressed("aim")
	
	# Handle Controller Rotation
	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	if rotation_input:
		handle_rotation(rotation_input.x, rotation_input.y, true, delta)
	
	# Shooting
	if weapon:
		if weapon.automatic:
			if Input.is_action_pressed("shoot"):
				shoot()
				# Start looping gun sound for automatic weapons
				if not is_firing_sound and gun_sound and current_ammo > 0 and not is_reloading:
					gun_sound.play(0.0)
					is_firing_sound = true
			else:
				# Stop sound immediately when fire button released
				stop_gun_sound()
		else:
			if Input.is_action_just_pressed("shoot"):
				shoot()
				if shot_sound and current_ammo >= 0:
					shot_sound.play(0.0)

	# Reset flag if sound finished naturally
	if is_firing_sound and gun_sound and not gun_sound.playing:
		is_firing_sound = false
	
	# Reloading
	if Input.is_action_just_pressed("reload"):
		reload()
	
	# Weapon switching
	if Input.is_action_just_pressed("weapon_next"):
		switch_weapon(1)
	if Input.is_action_just_pressed("weapon_prev"):
		switch_weapon(-1)
	
	# Jumping (double jump!)
	if Input.is_action_just_pressed("jump"):
		if jumps_remaining > 0:
			action_jump()
	
	# Weapon inspect (J key)
	if Input.is_action_just_pressed("inspect") and not is_inspecting and not is_flipping and not is_aiming:
		start_inspect()

	# Gun flip (X key, pistol only)
	if Input.is_action_just_pressed("gun_flip") and not is_flipping and not is_inspecting and not is_aiming:
		if weapon and weapon.weapon_name == "Pistol":
			start_gun_flip()

	# Camera mode toggle (arrow keys)
	if Input.is_action_just_pressed("camera_third_person") and not is_third_person:
		set_third_person(true)
	if Input.is_action_just_pressed("camera_first_person") and is_third_person:
		set_third_person(false)

	# Grenade throw (G key)
	if Input.is_action_just_pressed("grenade") and grenades > 0 and grenade_cooldown <= 0:
		throw_grenade()

	# Update grenade cooldown
	if grenade_cooldown > 0:
		grenade_cooldown -= delta

	# Update inspect animation
	if is_inspecting:
		update_inspect(delta)
	if is_flipping:
		update_gun_flip(delta)

func handle_rotation(xRot: float, yRot: float, isController: bool, delta: float = 0.0):
	if isController:
		rotation_target -= Vector3(-yRot, -xRot, 0).limit_length(1.0) * gamepad_sensitivity
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		head.rotation.x = lerp_angle(head.rotation.x, rotation_target.x, delta * 25)
		rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)
	else:
		rotation_target += (Vector3(-yRot, -xRot, 0) / mouse_sensitivity)
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		head.rotation.x = rotation_target.x
		rotation.y = rotation_target.y

func handle_gravity(delta):
	gravity += 20 * delta
	
	if gravity > 0 and is_on_floor():
		jumps_remaining = max_jumps
		gravity = 0

func action_jump():
	# Double jump costs stamina
	if jumps_remaining < max_jumps:
		if stamina < stamina_drain_jump:
			return  # Not enough stamina for double jump
		stamina -= stamina_drain_jump
		stamina_updated.emit(stamina, max_stamina)
	
	gravity = -jump_strength
	jumps_remaining -= 1

func shoot():
	if is_reloading:
		return
	if !shoot_cooldown.is_stopped():
		return
	if current_ammo <= 0:
		# Stop gun sound when out of ammo
		stop_gun_sound()
		# Auto reload when empty
		reload()
		return
	
	current_ammo -= 1
	ammo_updated.emit(current_ammo, reserve_ammo)
	
	shoot_cooldown.start(weapon.cooldown)

	# Shooting makes noise - alerts nearby enemies
	noise_level = 100.0

	# Muzzle flash
	if muzzle_flash:
		muzzle_flash.visible = true
		muzzle_flash.rotation.z = randf_range(0, TAU)
		await get_tree().create_timer(0.05).timeout
		muzzle_flash.visible = false
	
	# Apply recoil
	var recoil_v = randf_range(weapon.recoil_vertical.x, weapon.recoil_vertical.y)
	var recoil_h = randf_range(weapon.recoil_horizontal.x, weapon.recoil_horizontal.y)
	rotation_target.x -= recoil_v
	rotation_target.y += recoil_h
	
	# Weapon kickback visual
	if weapon_container:
		weapon_container.position.z += 0.05
	
	# Rocket launcher fires a projectile instead of raycast
	if weapon.weapon_name == "Strela-P":
		fire_rocket()
		return

	# Raycast for hit detection
	for i in weapon.shot_count:
		if is_third_person:
			# In third person, cast from screen center through the active camera
			var viewport = get_viewport()
			var screen_center = viewport.get_visible_rect().size / 2
			var ray_origin = third_person_camera.project_ray_origin(screen_center)
			var ray_dir = third_person_camera.project_ray_normal(screen_center)

			# Add spread
			ray_dir.x += randf_range(-weapon.spread, weapon.spread) * 0.01
			ray_dir.y += randf_range(-weapon.spread, weapon.spread) * 0.01
			ray_dir = ray_dir.normalized()

			# Physics raycast from camera through crosshair
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * weapon.max_distance)
			query.exclude = [get_rid()]
			var result = space_state.intersect_ray(query)

			if result:
				spawn_impact(result.position, result.normal)
				var collider = result.collider
				if collider and collider.has_method("take_damage"):
					collider.take_damage(weapon.damage)
		else:
			raycast.target_position.x = randf_range(-weapon.spread, weapon.spread) * 0.01
			raycast.target_position.y = randf_range(-weapon.spread, weapon.spread) * 0.01
			raycast.force_raycast_update()

			if raycast.is_colliding():
				var collider = raycast.get_collider()
				var hit_point = raycast.get_collision_point()
				var hit_normal = raycast.get_collision_normal()

				# Spawn impact effect
				spawn_impact(hit_point, hit_normal)

				# Damage if enemy
				if collider.has_method("take_damage"):
					collider.take_damage(weapon.damage)

func set_third_person(enabled: bool):
	is_third_person = enabled
	if enabled:
		third_person_camera.make_current()
		weapon_container.visible = false
		if fps_arms:
			fps_arms.visible = false
		if tp_model:
			tp_model.visible = true
	else:
		camera.make_current()
		weapon_container.visible = true
		if fps_arms:
			fps_arms.visible = true
		if tp_model:
			tp_model.visible = false

func stop_gun_sound():
	if is_firing_sound and gun_sound:
		gun_sound.stop()
		is_firing_sound = false

func reload():
	if is_reloading:
		return
	if current_ammo >= weapon.magazine_size:
		return
	if reserve_ammo <= 0:
		return

	stop_gun_sound()
	is_reloading = true
	reload_anim_time = 0.0
	reload_timer.start(weapon.reload_time)

	# Play reload sound — shotgun cock for shotgun/sniper, normal reload for others
	var is_shotgun_type = weapon and (weapon.weapon_name == "Shotgun" or weapon.weapon_name == "Sniper Rifle")
	if is_shotgun_type and shotgun_cock_sound:
		shotgun_cock_sound.play(0.0)
	elif reload_sound:
		reload_sound.play(0.0)

	# Play reload animation on correct model
	if is_third_person:
		# Third person: play reload on TP model
		if tp_anim_player and tp_reload_anim_name != "":
			tp_anim_player.play(tp_reload_anim_name)
			tp_anim_player.speed_scale = tp_anim_player.get_animation(tp_reload_anim_name).length / weapon.reload_time
			tp_current_anim = tp_reload_anim_name
	else:
		# First person: play reload on FPS arms
		if fps_arms_anim and fps_reload_anim_name != "":
			fps_arms_anim.play(fps_reload_anim_name)
			fps_arms_anim.speed_scale = fps_arms_anim.get_animation(fps_reload_anim_name).length / weapon.reload_time

func update_reload_anim(delta: float):
	if not is_reloading or not weapon:
		return

	reload_anim_time += delta
	var duration = weapon.reload_time
	var progress = clamp(reload_anim_time / duration, 0.0, 1.0)

	# Pistol: simple tilt back (slide pull)
	# Non-pistol: mag swap - dip down, tilt, snap back
	var y_offset := 0.0
	var x_rot := 0.0
	var z_rot := 0.0

	if weapon.weapon_name == "Pistol":
		# Quick slide pull: tilt back then forward
		x_rot = sin(progress * PI) * -15.0
	else:
		# Phase 1 (0-0.3): dip gun down and tilt right (removing mag)
		# Phase 2 (0.3-0.7): hold low (inserting new mag)
		# Phase 3 (0.7-1.0): snap back up and slap bolt
		if progress < 0.3:
			var p = progress / 0.3
			y_offset = -0.12 * p
			z_rot = 25.0 * p
			x_rot = -10.0 * p
		elif progress < 0.7:
			var p = (progress - 0.3) / 0.4
			y_offset = -0.12
			z_rot = 25.0 - 15.0 * sin(p * PI)
			x_rot = -10.0
		else:
			var p = (progress - 0.7) / 0.3
			y_offset = -0.12 * (1.0 - p)
			z_rot = 10.0 * (1.0 - p)
			x_rot = -10.0 * (1.0 - p)
			# Bolt slap snap at the end
			if p > 0.7:
				var snap = (p - 0.7) / 0.3
				x_rot += sin(snap * PI) * 8.0

	for child in weapon_container.get_children():
		if child.name != "MuzzleFlash":
			child.position.y = y_offset
			child.rotation_degrees.x = weapon.rotation.x + x_rot
			child.rotation_degrees.z = weapon.rotation.z + z_rot

func _on_reload_timer_timeout():
	is_reloading = false
	reload_anim_time = 0.0
	# Reset weapon position
	for child in weapon_container.get_children():
		if child.name != "MuzzleFlash":
			child.position.y = 0.0
			child.rotation_degrees = weapon.rotation
	# Return animations to idle
	if fps_arms_anim and fps_idle_anim_name != "":
		fps_arms_anim.play(fps_idle_anim_name)
		fps_arms_anim.speed_scale = 1.0
	if tp_anim_player and tp_current_anim == tp_reload_anim_name:
		tp_anim_player.pause()
		tp_anim_player.seek(0, true)
		tp_anim_player.speed_scale = 1.0
		tp_current_anim = "idle"
	var ammo_needed = weapon.magazine_size - current_ammo
	var ammo_to_load = min(ammo_needed, reserve_ammo)
	current_ammo += ammo_to_load
	reserve_ammo -= ammo_to_load
	ammo_updated.emit(current_ammo, reserve_ammo)

func switch_weapon(direction: int):
	if weapons.size() <= 1:
		return

	stop_gun_sound()
	weapon_index = wrapi(weapon_index + direction, 0, weapons.size())
	equip_weapon(weapon_index)

func equip_weapon(index: int):
	weapon = weapons[index]
	weapon_container_offset = weapon.position
	
	# Clear old weapon model
	for child in weapon_container.get_children():
		if child.name != "MuzzleFlash":
			child.queue_free()
	
	# Spawn new weapon model
	if weapon.model:
		var model_instance = weapon.model.instantiate()
		weapon_container.add_child(model_instance)
		model_instance.rotation_degrees = weapon.rotation
		model_instance.scale = Vector3.ONE * weapon.scale
	
	# Set ammo
	current_ammo = weapon.magazine_size
	reserve_ammo = weapon.max_ammo
	
	# Update raycast distance
	raycast.target_position.z = -weapon.max_distance
	
	ammo_updated.emit(current_ammo, reserve_ammo)
	weapon_changed.emit(weapon.weapon_name)

func spawn_impact(pos: Vector3, normal: Vector3):
	var impact = preload("res://effects/impact.tscn").instantiate()
	get_tree().root.add_child(impact)
	impact.global_position = pos + (normal * 0.01)
	
	# Avoid colinear look_at issue when normal points straight up/down
	var up_vector = Vector3.UP
	if abs(normal.dot(Vector3.UP)) > 0.99:
		up_vector = Vector3.FORWARD
	
	if normal.length() > 0.01:
		impact.look_at(pos + normal, up_vector)

func fire_rocket():
	var rocket = preload("res://weapons/rocket.tscn").instantiate()
	get_tree().root.add_child(rocket)
	rocket.global_position = camera.global_position + (-camera.global_basis.z * 1.5)
	var shoot_dir = -camera.global_basis.z
	rocket.launch(shoot_dir)
	# Play single shot sound
	if shot_sound:
		shot_sound.play(0.0)

func rocket_jump(strength: float):
	# Cap the boost so you don't fly to the moon
	var boost = clamp(strength, 0.0, 12.0)
	gravity = -boost

func pickup_weapon(weapon_path: String):
	var new_weapon = load(weapon_path) as Weapon
	if new_weapon == null:
		return
	
	# Check if we already have this weapon
	for w in weapons:
		if w.weapon_name == new_weapon.weapon_name:
			# Just add ammo instead
			reserve_ammo += new_weapon.magazine_size * 2
			ammo_updated.emit(current_ammo, reserve_ammo)
			notification_show.emit("+" + str(new_weapon.magazine_size * 2) + " " + new_weapon.weapon_name + " ammo")
			return
	
	# Add new weapon to inventory
	weapons.append(new_weapon)
	notification_show.emit("Picked up " + new_weapon.weapon_name + "!")
	
	# Auto-equip if it's better or we only had pistol
	if weapons.size() <= 2:
		weapon_index = weapons.size() - 1
		equip_weapon(weapon_index)

func add_ammo(amount: int):
	reserve_ammo += amount
	ammo_updated.emit(current_ammo, reserve_ammo)

func heal(amount: float):
	health = min(health + amount, max_health)
	health_updated.emit(health, max_health)

func take_damage(amount: float):
	health -= amount
	health = max(0, health)
	health_updated.emit(health, max_health)
	
	if health <= 0:
		die()

func die():
	stop_gun_sound()
	get_tree().reload_current_scene()

# Weapon inspect functions
func start_inspect():
	is_inspecting = true
	inspect_time = 0.0

func update_inspect(delta: float):
	inspect_time += delta

	if inspect_time >= inspect_duration:
		stop_inspect()
		return

	var progress = inspect_time / inspect_duration

	# Smooth animation that starts and ends at the same position
	# Tilt right and show the side, then roll back through center and end at start
	var y_rot = sin(progress * PI) * 40.0
	var z_rot = sin(progress * TAU) * 20.0
	var x_rot = sin(progress * PI) * -10.0

	if weapon_container.get_child_count() > 0:
		for child in weapon_container.get_children():
			if child.name != "MuzzleFlash":
				child.rotation_degrees.y = weapon.rotation.y + y_rot
				child.rotation_degrees.z = weapon.rotation.z + z_rot
				child.rotation_degrees.x = weapon.rotation.x + x_rot

func stop_inspect():
	is_inspecting = false
	# Reset weapon rotation back to default
	if weapon_container.get_child_count() > 0:
		for child in weapon_container.get_children():
			if child.name != "MuzzleFlash":
				child.rotation_degrees = weapon.rotation

# Gun flip functions (pistol only)
func start_gun_flip():
	is_flipping = true
	flip_time = 0.0

func update_gun_flip(delta: float):
	flip_time += delta

	if flip_time >= flip_duration:
		stop_gun_flip()
		return

	var progress = flip_time / flip_duration

	# Toss up arc: rises then falls back down
	var toss_height = sin(progress * PI) * 0.15

	# Full 360 spin around the X axis
	var spin = progress * 360.0

	if weapon_container.get_child_count() > 0:
		for child in weapon_container.get_children():
			if child.name != "MuzzleFlash":
				child.position.y = toss_height
				child.rotation_degrees.x = weapon.rotation.x + spin
				child.rotation_degrees.y = weapon.rotation.y
				child.rotation_degrees.z = weapon.rotation.z

func stop_gun_flip():
	is_flipping = false
	if weapon_container.get_child_count() > 0:
		for child in weapon_container.get_children():
			if child.name != "MuzzleFlash":
				child.position.y = 0.0
				child.rotation_degrees = weapon.rotation

# Grenade functions
func throw_grenade():
	grenades -= 1
	grenade_cooldown = 1.0
	grenades_updated.emit(grenades, max_grenades)
	
	# Create grenade projectile
	var grenade = preload("res://weapons/grenade.tscn").instantiate()
	get_tree().root.add_child(grenade)
	grenade.global_position = camera.global_position + (-camera.global_basis.z * 1.0)
	
	# Apply throw force
	var throw_direction = -camera.global_basis.z + Vector3.UP * 0.3
	grenade.apply_impulse(throw_direction.normalized() * grenade_throw_force)

func add_grenade(amount: int = 1):
	grenades = min(grenades + amount, max_grenades)
	grenades_updated.emit(grenades, max_grenades)
	notification_show.emit("+" + str(amount) + " Grenade")

func _load_fps_anim(fbx_path: String, anim_id: String, should_loop: bool) -> String:
	if fps_arms_anim == null:
		return ""
	var fbx = load(fbx_path)
	if fbx == null:
		return ""
	var temp = fbx.instantiate()
	var temp_ap = temp.get_node_or_null("AnimationPlayer")
	if temp_ap == null:
		temp.free()
		return ""

	var src_name = "mixamo_com"
	if not temp_ap.has_animation(src_name):
		var list = temp_ap.get_animation_list()
		if list.size() == 0:
			temp.free()
			return ""
		src_name = list[0]

	var anim = temp_ap.get_animation(src_name).duplicate()
	temp.free()

	anim.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE
	_strip_root_motion(anim)

	var lib = fps_arms_anim.get_animation_library("")
	if lib:
		lib.add_animation(anim_id, anim)
	else:
		var new_lib = AnimationLibrary.new()
		new_lib.add_animation(anim_id, anim)
		fps_arms_anim.add_animation_library("", new_lib)

	print("FPS anim loaded: ", anim_id, " (", anim.length, "s)")
	return anim_id

func _load_tp_anim(fbx_path: String, anim_id: String, should_loop: bool) -> String:
	var fbx = load(fbx_path)
	if fbx == null:
		return ""
	var temp = fbx.instantiate()
	var temp_ap = temp.get_node_or_null("AnimationPlayer")
	if temp_ap == null:
		temp.free()
		return ""

	var src_name = "mixamo_com"
	if not temp_ap.has_animation(src_name):
		var list = temp_ap.get_animation_list()
		if list.size() == 0:
			temp.free()
			return ""
		src_name = list[0]

	var anim = temp_ap.get_animation(src_name).duplicate()
	temp.free()

	anim.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE
	_strip_root_motion(anim)

	var lib = tp_anim_player.get_animation_library("")
	if lib:
		lib.add_animation(anim_id, anim)
	else:
		var new_lib = AnimationLibrary.new()
		new_lib.add_animation(anim_id, anim)
		tp_anim_player.add_animation_library("", new_lib)

	return anim_id

func _strip_root_motion(anim: Animation):
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(i):
				var pos = anim.track_get_key_value(i, k)
				# Keep Y (height) but zero X and Z (horizontal drift)
				anim.track_set_key_value(i, k, Vector3(0, pos.y, 0))

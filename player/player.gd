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

# Grenades
var grenades: int = 3
var max_grenades: int = 3
var grenade_cooldown: float = 0.0
var grenade_throw_force := 20.0

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

@onready var camera = $Head/Camera
@onready var raycast = $Head/Camera/RayCast3D
@onready var weapon_container = $Head/Camera/WeaponContainer
@onready var shoot_cooldown = $ShootCooldown
@onready var reload_timer = $ReloadTimer
@onready var muzzle_flash = $Head/Camera/WeaponContainer/MuzzleFlash

var scope_overlay: CanvasLayer = null

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Find scope overlay in scene
	scope_overlay = get_tree().get_first_node_in_group("scope_overlay")
	
	# Initialize health/stamina/grenades
	health_updated.emit(health, max_health)
	stamina_updated.emit(stamina, max_stamina)
	grenades_updated.emit(grenades, max_grenades)
	
	if weapons.size() > 0:
		weapon = weapons[weapon_index]
		equip_weapon(weapon_index)

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
		if weapon.has_scope and is_aiming:
			if scope_overlay:
				scope_overlay.show_scope()
			# Hide weapon when looking through scope
			weapon_container.visible = false
		else:
			if scope_overlay:
				scope_overlay.hide_scope()
			weapon_container.visible = true
	
	# Landing after jump or falling
	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	
	if is_on_floor() and gravity > 1 and !previously_floored:
		camera.position.y = -0.1
	
	previously_floored = is_on_floor()
	
	# Falling/respawning
	if position.y < -10:
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
	
	# Movement
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	var is_sprinting = Input.is_action_pressed("sprint") and stamina > 0
	var current_speed = sprint_speed if is_sprinting else movement_speed
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
		else:
			if Input.is_action_just_pressed("shoot"):
				shoot()
	
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
	if Input.is_action_just_pressed("inspect") and not is_inspecting and not is_aiming:
		start_inspect()
	
	# Grenade throw (G key)
	if Input.is_action_just_pressed("grenade") and grenades > 0 and grenade_cooldown <= 0:
		throw_grenade()
	
	# Update grenade cooldown
	if grenade_cooldown > 0:
		grenade_cooldown -= delta
	
	# Update inspect animation
	if is_inspecting:
		update_inspect(delta)

func handle_rotation(xRot: float, yRot: float, isController: bool, delta: float = 0.0):
	if isController:
		rotation_target -= Vector3(-yRot, -xRot, 0).limit_length(1.0) * gamepad_sensitivity
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
		rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)
	else:
		rotation_target += (Vector3(-yRot, -xRot, 0) / mouse_sensitivity)
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = rotation_target.x
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
		# Auto reload when empty
		reload()
		return
	
	current_ammo -= 1
	ammo_updated.emit(current_ammo, reserve_ammo)
	
	shoot_cooldown.start(weapon.cooldown)
	
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
	
	# Raycast for hit detection
	for i in weapon.shot_count:
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

func reload():
	if is_reloading:
		return
	if current_ammo >= weapon.magazine_size:
		return
	if reserve_ammo <= 0:
		return
	
	is_reloading = true
	reload_timer.start(weapon.reload_time)

func _on_reload_timer_timeout():
	is_reloading = false
	var ammo_needed = weapon.magazine_size - current_ammo
	var ammo_to_load = min(ammo_needed, reserve_ammo)
	current_ammo += ammo_to_load
	reserve_ammo -= ammo_to_load
	ammo_updated.emit(current_ammo, reserve_ammo)

func switch_weapon(direction: int):
	if weapons.size() <= 1:
		return
	
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

func spawn_impact(position: Vector3, normal: Vector3):
	var impact = preload("res://effects/impact.tscn").instantiate()
	get_tree().root.add_child(impact)
	impact.global_position = position + (normal * 0.01)
	impact.look_at(position + normal)

func add_ammo(amount: int):
	reserve_ammo += amount
	ammo_updated.emit(current_ammo, reserve_ammo)

func take_damage(amount: float):
	health -= amount
	health = max(0, health)
	health_updated.emit(health, max_health)
	
	if health <= 0:
		die()

func die():
	get_tree().reload_current_scene()

# Weapon inspect functions
func start_inspect():
	is_inspecting = true
	inspect_time = 0.0

func update_inspect(delta: float):
	inspect_time += delta
	
	if inspect_time >= inspect_duration:
		is_inspecting = false
		return
	
	# Rotate weapon for inspection effect
	var progress = inspect_time / inspect_duration
	var rotation_amount: float
	
	if progress < 0.5:
		# First half: rotate right and tilt
		rotation_amount = sin(progress * PI) * 45
	else:
		# Second half: return to normal
		rotation_amount = sin(progress * PI) * 45
	
	if weapon_container.get_child_count() > 0:
		for child in weapon_container.get_children():
			if child.name != "MuzzleFlash":
				child.rotation_degrees.y = rotation_amount
				child.rotation_degrees.z = sin(progress * PI * 2) * 15

func stop_inspect():
	is_inspecting = false
	# Reset weapon rotation
	if weapon_container.get_child_count() > 0:
		for child in weapon_container.get_children():
			if child.name != "MuzzleFlash":
				child.rotation_degrees.y = weapon.rotation.y
				child.rotation_degrees.z = weapon.rotation.z

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

extends CharacterBody3D

@export var move_speed := 4.0
@export var health := 60.0
@export var damage := 15.0
@export var attack_range := 2.5
@export var detection_range := 30.0
@export var attack_cooldown := 1.0

var player: Node3D = null
var gravity := 20.0
var current_state := "idle"
var attack_timer := 0.0
var rotation_speed := 6.0
var max_health := 60.0
var is_dead := false

@onready var anim_player: AnimationPlayer = $ZombieModel/AnimationPlayer

var idle_anim := ""
var run_anim := ""
var attack_anim := ""
var last_state := ""

var _ammo_pickup_scene = preload("res://pickups/ammo_pickup.tscn")

signal enemy_died

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	max_health = health

	# Setup base animation from the model's FBX
	if anim_player:
		for anim_name in anim_player.get_animation_list():
			var anim = anim_player.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR
			_strip_root_motion(anim)
			idle_anim = anim_name

		# Start paused in idle
		if idle_anim != "":
			anim_player.play(idle_anim)
			anim_player.seek(0, true)
			anim_player.pause()

		# Load run animation
		run_anim = _load_anim("res://animations/zombie/Zombie Running.fbx", "zombie_run", true)
		if run_anim == "":
			run_anim = _load_anim("res://animations/zombie/Zombie Running (1).fbx", "zombie_run", true)

		# Load attack animation
		attack_anim = _load_anim("res://animations/zombie/Zombie Attack.fbx", "zombie_attack", false)
		if attack_anim == "":
			attack_anim = _load_anim("res://animations/zombie/Zombie Attack (1).fbx", "zombie_attack", false)

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	if is_dead:
		velocity = Vector3.ZERO
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return

	var distance = global_position.distance_to(player.global_position)

	# State machine — zombies always chase if in range
	if distance <= attack_range:
		current_state = "attack"
	elif distance <= detection_range:
		current_state = "chase"
	else:
		current_state = "idle"

	match current_state:
		"idle":
			velocity.x = 0
			velocity.z = 0
		"chase":
			var direction = (player.global_position - global_position).normalized()
			direction.y = 0
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
		"attack":
			velocity.x = 0
			velocity.z = 0
			attack_timer -= delta
			if attack_timer <= 0:
				attack_timer = attack_cooldown
				_deal_damage()

	# Animation
	if current_state != last_state:
		last_state = current_state
		_update_animation()

	move_and_slide()

	# Face player
	if current_state in ["chase", "attack"]:
		var look_pos = player.global_position
		look_pos.y = global_position.y
		var target_dir = (look_pos - global_position).normalized()
		var target_angle = atan2(target_dir.x, target_dir.z) + PI
		rotation.y = lerp_angle(rotation.y, target_angle, delta * rotation_speed)

func _update_animation():
	if anim_player == null:
		return
	match current_state:
		"idle":
			if idle_anim != "":
				anim_player.play(idle_anim)
				anim_player.speed_scale = 1.0
			else:
				anim_player.pause()
		"chase":
			if run_anim != "":
				anim_player.play(run_anim)
				anim_player.speed_scale = 1.0
			elif idle_anim != "":
				anim_player.play(idle_anim)
				anim_player.speed_scale = 2.0
		"attack":
			if attack_anim != "":
				anim_player.play(attack_anim)
				anim_player.speed_scale = 1.0 / attack_cooldown

func _deal_damage():
	if player and player.has_method("take_damage"):
		var dist = global_position.distance_to(player.global_position)
		if dist <= attack_range + 0.5:
			player.take_damage(damage)

func take_damage(amount: float):
	health -= amount
	if health <= 0:
		die()

func die():
	if is_dead:
		return
	is_dead = true
	enemy_died.emit()

	var death_pos = global_position
	var tree = get_tree()
	if tree == null:
		return

	# Spawn ammo
	_spawn_ammo(death_pos)

	# Disable processing
	set_process(false)

	# Fall over — tilt forward
	var tween = create_tween()
	tween.tween_property(self, "rotation_degrees:x", 90.0, 0.4).set_ease(Tween.EASE_IN)

	# Free after delay
	tree.create_timer(2.0).timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)

func _spawn_ammo(pos: Vector3):
	var tree = get_tree()
	if tree == null or tree.root == null:
		return
	var pickup = _ammo_pickup_scene.instantiate()
	pickup.global_position = pos + Vector3(0, 1, 0)
	pickup.ammo_amount = 10
	tree.root.add_child(pickup)

func _load_anim(fbx_path: String, anim_id: String, should_loop: bool) -> String:
	if anim_player == null:
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

	var lib = anim_player.get_animation_library("")
	if lib:
		lib.add_animation(anim_id, anim)
	else:
		var new_lib = AnimationLibrary.new()
		new_lib.add_animation(anim_id, anim)
		anim_player.add_animation_library("", new_lib)

	return anim_id

func _strip_root_motion(anim: Animation):
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			for k in anim.track_get_key_count(i):
				var pos = anim.track_get_key_value(i, k)
				anim.track_set_key_value(i, k, Vector3(0, pos.y, 0))

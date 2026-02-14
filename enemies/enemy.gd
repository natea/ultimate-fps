extends CharacterBody3D

@export var move_speed := 3.5
@export var chase_speed := 4.0
@export var attack_range := 15.0  # Shooting range
@export var detection_range := 25.0
@export var health := 100.0
@export var gun_damage := 8.0
@export var fire_rate := 0.5  # Seconds between shots
@export var accuracy := 0.85  # 0-1, higher = more accurate

var player: Node3D = null
var gravity := 20.0
var current_state := "idle"
var fire_timer := 0.0
var rotation_speed := 8.0  # How fast enemy turns to face player

@onready var raycast: RayCast3D = $RayCast3D
@onready var anim_player: AnimationPlayer = $SoldierModel/AnimationPlayer

signal enemy_died

func _ready():
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	# Start playing run animation in a loop
	if anim_player:
		if anim_player.has_animation("mixamo_com"):
			var anim = anim_player.get_animation("mixamo_com")
			anim.loop_mode = Animation.LOOP_LINEAR
			anim_player.play("mixamo_com")
		elif anim_player.has_animation("Take 001"):
			var anim = anim_player.get_animation("Take 001")
			anim.loop_mode = Animation.LOOP_LINEAR
			anim_player.play("Take 001")

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	
	var distance_to_player = global_position.distance_to(player.global_position)
	
	# State machine
	if distance_to_player <= attack_range:
		current_state = "attack"
	elif distance_to_player <= detection_range:
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
	
	move_and_slide()
	
	# Smoothly rotate to face player when chasing or attacking
	if current_state in ["chase", "attack"]:
		var look_pos = player.global_position
		look_pos.y = global_position.y
		var target_direction = (look_pos - global_position).normalized()
		var target_angle = atan2(target_direction.x, target_direction.z) + PI
		rotation.y = lerp_angle(rotation.y, target_angle, delta * rotation_speed)

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
	
	# Aim at player with some inaccuracy
	var target_pos = player.global_position + Vector3(0, 1, 0)  # Aim at chest
	var direction = (target_pos - raycast.global_position).normalized()
	
	# Add inaccuracy
	var miss_amount = (1.0 - accuracy) * 0.5
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
	health -= amount
	if health <= 0:
		die()

func die():
	enemy_died.emit()
	queue_free()

extends CharacterBody3D

@export var chase_speed := 6.5
@export var attack_range := 15.0
@export var detection_range := 25.0
@export var health := 100.0
@export var gun_damage := 8.0
@export var fire_rate := 0.5

var player: Node3D = null
var gravity := 20.0
var fire_timer := 0.0

@onready var raycast: RayCast3D = $RayCast3D

var _simple_enemy_scene = preload("res://enemies/simple_enemy.tscn")

signal enemy_died

func _ready():
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			move_and_slide()
			return
	
	var distance = global_position.distance_to(player.global_position)
	
	if distance <= attack_range:
		# Attack - stop and shoot
		velocity.x = 0
		velocity.z = 0
		fire_timer -= delta
		if fire_timer <= 0:
			fire_timer = fire_rate
			shoot()
	elif distance <= detection_range:
		# Chase
		var dir = (player.global_position - global_position).normalized()
		dir.y = 0
		velocity.x = dir.x * chase_speed
		velocity.z = dir.z * chase_speed
	else:
		velocity.x = 0
		velocity.z = 0
	
	move_and_slide()
	
	# Face player
	if distance <= detection_range:
		var look_pos = player.global_position
		look_pos.y = global_position.y
		look_at(look_pos)

func shoot():
	if raycast == null or player == null:
		return
	var target = player.global_position + Vector3(0, 1, 0)
	var dir = (target - raycast.global_position).normalized()
	raycast.target_position = dir * 50
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var col = raycast.get_collider()
		if col and col.has_method("take_damage"):
			col.take_damage(gun_damage)

func take_damage(amount: float):
	health -= amount
	if health <= 0:
		die()

func die():
	enemy_died.emit()
	# Respawn
	var tree = get_tree()
	if tree == null:
		queue_free()
		return
	var pos = Vector3(randf_range(-20, 20), 1, randf_range(-20, 20))
	queue_free()
	tree.create_timer(3.0).timeout.connect(func():
		if not is_instance_valid(tree) or not tree.root:
			return
		var e = _simple_enemy_scene.instantiate()
		tree.root.add_child(e)
		e.global_position = pos
	)

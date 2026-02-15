extends Node3D

var kill_count := 0
var kills_for_weapon_drop := 10
var weapon_paths := [
	"res://weapons/m4a1.tres",
	"res://weapons/ak47.tres",
	"res://weapons/shotgun.tres",
	"res://weapons/sniper_rifle.tres",
	"res://weapons/scar.tres",
	"res://weapons/p90.tres",
	"res://weapons/strela.tres",
]

func _ready():
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_connect_enemy(enemy)

func _connect_enemy(enemy: Node):
	if enemy.has_signal("enemy_died") and not enemy.enemy_died.is_connected(_on_enemy_killed):
		enemy.enemy_died.connect(_on_enemy_killed)

func _on_enemy_killed():
	kill_count += 1
	var hud = get_node_or_null("HUD")
	if hud:
		var counter = hud.get_node_or_null("KillCounter")
		if counter:
			counter.text = "Kills: " + str(kill_count)

	if kill_count % kills_for_weapon_drop == 0:
		spawn_weapon_reward()

	# Spawn bonus enemies — the more you kill, the more spawn
	var bonus = int(kill_count / 5)
	for _i in bonus:
		get_tree().create_timer(randf_range(1.0, 3.0)).timeout.connect(func():
			if is_inside_tree():
				respawn_enemy(Vector3.ZERO)
		)

func spawn_weapon_reward():
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
		pickup.global_position = Vector3(-24, 1, -18)
	add_child(pickup)
	if player and player.has_signal("notification_show"):
		var weapon_res = load(weapon_path)
		if weapon_res:
			player.notification_show.emit("Weapon drop! " + weapon_res.weapon_name)

func respawn_enemy(_pos_hint: Vector3 = Vector3.ZERO):
	if not is_inside_tree():
		return
	var enemy_scene = preload("res://enemies/enemy.tscn")
	var new_enemy = enemy_scene.instantiate()
	new_enemy.global_position = Vector3(
		randf_range(-100, 0),
		1,
		randf_range(-80, 20)
	)
	var enemies_node = get_node_or_null("Enemies")
	if enemies_node:
		enemies_node.add_child(new_enemy)
	else:
		add_child(new_enemy)
	await get_tree().process_frame
	_connect_enemy(new_enemy)

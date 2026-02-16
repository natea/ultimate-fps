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

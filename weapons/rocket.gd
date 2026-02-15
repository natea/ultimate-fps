extends RigidBody3D

@export var explosion_damage := 500.0
@export var explosion_radius := 6.0
@export var rocket_speed := 40.0
@export var rocket_jump_force := 12.0

var direction := Vector3.FORWARD
var has_exploded := false

func _ready():
	gravity_scale = 0.0
	linear_damp = 0.0
	contact_monitor = true
	max_contacts_reported = 1
	body_entered.connect(_on_body_entered)

func launch(dir: Vector3):
	direction = dir.normalized()
	linear_velocity = direction * rocket_speed

func _on_body_entered(_body):
	if not has_exploded:
		explode()

func explode():
	has_exploded = true

	# Damage enemies
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var distance = global_position.distance_to(enemy.global_position)
		if distance <= explosion_radius:
			var damage_mult = 1.0 - (distance / explosion_radius)
			if enemy.has_method("take_damage"):
				enemy.take_damage(explosion_damage * damage_mult)

	# Rocket jump - push player upward if they're close
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player == null or not is_instance_valid(player):
			continue
		var distance = global_position.distance_to(player.global_position)
		if distance <= explosion_radius:
			var push_strength = (1.0 - distance / explosion_radius) * rocket_jump_force
			if player.has_method("rocket_jump"):
				player.rocket_jump(push_strength)
			if player.has_method("take_damage"):
				var self_damage = explosion_damage * 0.25 * (1.0 - distance / explosion_radius)
				player.take_damage(self_damage)

	_spawn_explosion()
	queue_free()

func _spawn_explosion():
	var flash = OmniLight3D.new()
	flash.light_color = Color(1, 0.5, 0.1)
	flash.light_energy = 8.0
	flash.omni_range = explosion_radius
	get_tree().root.add_child(flash)
	flash.global_position = global_position

	var sphere = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	sphere.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.6, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.4, 0.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material_override = mat
	get_tree().root.add_child(sphere)
	sphere.global_position = global_position

	var tween = flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "light_energy", 0.0, 0.4)
	tween.tween_property(sphere, "scale", Vector3(3, 3, 3), 0.3)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.set_parallel(false)
	tween.tween_callback(flash.queue_free)
	tween.tween_callback(sphere.queue_free)

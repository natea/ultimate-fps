extends Area3D

@export var weapon_resource_path: String = "res://weapons/m4a1.tres"

@onready var model_container: Node3D = $Model

var spin_speed := 2.0

func _ready():
	body_entered.connect(_on_body_entered)
	_load_weapon_model()

func _load_weapon_model():
	var weapon_res = load(weapon_resource_path)
	if weapon_res == null or weapon_res.model == null:
		return
	
	var model_instance = weapon_res.model.instantiate()
	model_container.add_child(model_instance)
	
	# Use weapon's own scale * 3 for ground visibility
	var s = weapon_res.scale * 3.0
	model_container.scale = Vector3(s, s, s)
	
	# Apply weapon rotation
	if weapon_res.rotation != Vector3.ZERO:
		model_container.rotation_degrees = weapon_res.rotation

func _process(delta):
	if model_container:
		model_container.rotate_y(spin_speed * delta)

func _on_body_entered(body):
	if body.is_in_group("player") and body.has_method("pickup_weapon"):
		body.pickup_weapon(weapon_resource_path)
		queue_free()

extends Node3D

# This script applies textures to the Mixamo soldier model

@onready var body_texture = preload("res://animations/Run Forward_0.png")
@onready var clothes_texture = preload("res://animations/Run Forward_1.png")

func _ready():
	# Wait a frame for the model to fully load
	await get_tree().process_frame
	apply_soldier_materials(self)

func apply_soldier_materials(node: Node):
	if node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		
		# Try to use the body texture for skin
		if body_texture:
			mat.albedo_texture = body_texture
		else:
			mat.albedo_color = Color(0.3, 0.5, 0.3)  # Fallback green
		
		mat.roughness = 0.6
		node.material_override = mat
		node.visible = true
	
	for child in node.get_children():
		apply_soldier_materials(child)

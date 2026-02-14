extends Node

func _ready():
	var scene = load("res://animations/Run Forward.fbx")
	if scene:
		var instance = scene.instantiate()
		print("=== FBX Structure ===")
		print_tree(instance, 0)
		instance.queue_free()
	else:
		print("Failed to load FBX")

func print_tree(node: Node, indent: int):
	var spaces = ""
	for i in range(indent):
		spaces += "  "
	print(spaces + node.name + " [" + node.get_class() + "]")
	if node is MeshInstance3D:
		print(spaces + "  -> Has mesh: " + str(node.mesh != null))
		if node.mesh:
			print(spaces + "  -> Mesh type: " + node.mesh.get_class())
	for child in node.get_children():
		print_tree(child, indent + 1)

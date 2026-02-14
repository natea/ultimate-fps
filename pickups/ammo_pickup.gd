extends Area3D

@export var ammo_amount: int = 30

func _ready():
	body_entered.connect(_on_body_entered)
	
	# Slow rotation for visibility
	var tween = create_tween().set_loops()
	tween.tween_property(self, "rotation:y", rotation.y + TAU, 3.0)

func _on_body_entered(body):
	if body.is_in_group("player"):
		if body.has_method("add_ammo"):
			body.add_ammo(ammo_amount)
		queue_free()

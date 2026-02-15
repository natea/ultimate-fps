extends Area3D

@export var heal_amount: float = 40.0

@onready var model = $Model

func _ready():
	body_entered.connect(_on_body_entered)

func _process(delta):
	if model:
		model.rotate_y(2.0 * delta)

func _on_body_entered(body):
	if body.is_in_group("player"):
		if body.has_method("heal"):
			body.heal(heal_amount)
			if body.has_signal("notification_show"):
				body.notification_show.emit("+" + str(int(heal_amount)) + " Health")
		queue_free()

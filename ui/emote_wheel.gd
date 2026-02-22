extends CanvasLayer

signal emote_selected(emote_id: String)

@onready var panel = $Panel
@onready var container = $Panel/VBoxContainer

var emotes := {
	"hip_hop": "Hip Hop",
	"hip_hop_2": "Hip Hop 2",
	"macarena": "Macarena",
	"breakdance": "Breakdance"
}

func _ready():
	add_to_group("emote_wheel")
	layer = 5
	visible = false
	_build_buttons()

func _build_buttons():
	for child in container.get_children():
		child.queue_free()

	for emote_id in emotes:
		var btn = Button.new()
		btn.text = emotes[emote_id]
		btn.custom_minimum_size = Vector2(250, 60)
		btn.add_theme_font_size_override("font_size", 22)
		btn.pressed.connect(_on_emote_pressed.bind(emote_id))
		container.add_child(btn)

	# Cancel button
	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(250, 50)
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(hide_wheel)
	container.add_child(cancel)

func show_wheel():
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_wheel():
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_emote_pressed(emote_id: String):
	hide_wheel()
	emote_selected.emit(emote_id)

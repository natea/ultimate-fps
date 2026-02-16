extends Control

var map_select_container: VBoxContainer
var event_map_select_container: VBoxContainer
var event_select_container: VBoxContainer
var selected_event_map := ""

var maps := [
	{"name": "Base 01", "scene": "res://levels/base01.tscn"},
	{"name": "Military Base", "scene": "res://levels/military_base.tscn"},
	{"name": "Desert Town", "scene": "res://levels/deserttown.tscn"},
	{"name": "Western", "scene": "res://levels/western.tscn"},
]

var events := [
	{"name": "Zombie Apocalypse", "scene": "res://events/zombie_apocalypse.tscn"},
]

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().grab_focus()
	_setup_gun_image()
	_setup_map_select()
	_setup_event_map_select()
	_setup_event_select()
	$MenuContainer/PlayButton.mouse_entered.connect(_on_button_hover.bind($MenuContainer/PlayButton))
	$MenuContainer/EventsButton.mouse_entered.connect(_on_button_hover.bind($MenuContainer/EventsButton))
	$MenuContainer/QuitButton.mouse_entered.connect(_on_button_hover.bind($MenuContainer/QuitButton))
	# Add multiplayer button (insert before Quit)
	var mp_button = Button.new()
	mp_button.text = "Multiplayer"
	mp_button.add_theme_font_size_override("font_size", 24)
	mp_button.pressed.connect(_on_multiplayer_pressed)
	mp_button.mouse_entered.connect(_on_button_hover.bind(mp_button))
	$MenuContainer.add_child(mp_button)
	$MenuContainer.move_child(mp_button, 2)  # After Play and Events

func _process(_delta):
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _setup_gun_image():
	var tex = load("res://textures/ak47_menu.jpg")
	if tex == null:
		return

	var gun_rect = TextureRect.new()
	gun_rect.name = "GunImage"
	gun_rect.texture = tex
	gun_rect.set_anchors_preset(PRESET_CENTER)
	gun_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gun_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gun_rect.offset_left = -650
	gun_rect.offset_right = 650
	gun_rect.offset_top = -360
	gun_rect.offset_bottom = 360
	gun_rect.mouse_filter = MOUSE_FILTER_IGNORE

	var shader = Shader.new()
	shader.code = """shader_type canvas_item;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float brightness = (tex.r + tex.g + tex.b) / 3.0;
	COLOR = vec4(1.0, 1.0, 1.0, (1.0 - brightness) * 0.25);
}
"""
	var mat = ShaderMaterial.new()
	mat.shader = shader
	gun_rect.material = mat

	add_child(gun_rect)
	move_child(gun_rect, 1)

func _setup_map_select():
	map_select_container = VBoxContainer.new()
	map_select_container.name = "MapSelectContainer"
	map_select_container.set_anchors_preset(PRESET_CENTER)
	map_select_container.offset_left = -180.0
	map_select_container.offset_top = -160.0
	map_select_container.offset_right = 180.0
	map_select_container.offset_bottom = 160.0
	map_select_container.add_theme_constant_override("separation", 20)
	map_select_container.visible = false
	add_child(map_select_container)

	# Title
	var title = Label.new()
	title.text = "PICK YOUR MAP"
	var title_settings = LabelSettings.new()
	title_settings.font_size = 42
	title_settings.font_color = Color(1, 1, 1)
	title_settings.outline_size = 4
	title_settings.outline_color = Color(0, 0, 0)
	title.label_settings = title_settings
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_select_container.add_child(title)

	# Map buttons
	for map_info in maps:
		var btn = Button.new()
		btn.text = map_info.name
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_theme_stylebox_override("normal", _make_map_btn_style(Color(0.12, 0.2, 0.3)))
		btn.add_theme_stylebox_override("hover", _make_map_btn_style(Color(0.2, 0.35, 0.5)))
		btn.add_theme_stylebox_override("pressed", _make_map_btn_style(Color(0.08, 0.15, 0.22)))
		btn.pressed.connect(_on_map_selected.bind(map_info.scene))
		btn.mouse_entered.connect(_on_button_hover.bind(btn))
		map_select_container.add_child(btn)

	# Back button
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.add_theme_stylebox_override("normal", _make_map_btn_style(Color(0.25, 0.12, 0.12)))
	back_btn.add_theme_stylebox_override("hover", _make_map_btn_style(Color(0.4, 0.2, 0.2)))
	back_btn.add_theme_stylebox_override("pressed", _make_map_btn_style(Color(0.18, 0.08, 0.08)))
	back_btn.pressed.connect(_on_back_pressed)
	map_select_container.add_child(back_btn)

func _setup_event_map_select():
	event_map_select_container = VBoxContainer.new()
	event_map_select_container.name = "EventMapSelectContainer"
	event_map_select_container.set_anchors_preset(PRESET_CENTER)
	event_map_select_container.offset_left = -180.0
	event_map_select_container.offset_top = -160.0
	event_map_select_container.offset_right = 180.0
	event_map_select_container.offset_bottom = 160.0
	event_map_select_container.add_theme_constant_override("separation", 20)
	event_map_select_container.visible = false
	add_child(event_map_select_container)

	# Title
	var title = Label.new()
	title.text = "PICK YOUR MAP"
	var title_settings = LabelSettings.new()
	title_settings.font_size = 42
	title_settings.font_color = Color(1, 0.3, 0.3)
	title_settings.outline_size = 4
	title_settings.outline_color = Color(0, 0, 0)
	title.label_settings = title_settings
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_map_select_container.add_child(title)

	# Map buttons (same maps, but routes to event select next)
	for map_info in maps:
		var btn = Button.new()
		btn.text = map_info.name
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_theme_stylebox_override("normal", _make_map_btn_style(Color(0.25, 0.1, 0.1)))
		btn.add_theme_stylebox_override("hover", _make_map_btn_style(Color(0.45, 0.15, 0.15)))
		btn.add_theme_stylebox_override("pressed", _make_map_btn_style(Color(0.18, 0.06, 0.06)))
		btn.pressed.connect(_on_event_map_selected.bind(map_info.scene))
		btn.mouse_entered.connect(_on_button_hover.bind(btn))
		event_map_select_container.add_child(btn)

	# Back button
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.add_theme_stylebox_override("normal", _make_map_btn_style(Color(0.25, 0.12, 0.12)))
	back_btn.add_theme_stylebox_override("hover", _make_map_btn_style(Color(0.4, 0.2, 0.2)))
	back_btn.add_theme_stylebox_override("pressed", _make_map_btn_style(Color(0.18, 0.08, 0.08)))
	back_btn.pressed.connect(_on_event_map_back_pressed)
	event_map_select_container.add_child(back_btn)

func _setup_event_select():
	event_select_container = VBoxContainer.new()
	event_select_container.name = "EventSelectContainer"
	event_select_container.set_anchors_preset(PRESET_CENTER)
	event_select_container.offset_left = -180.0
	event_select_container.offset_top = -160.0
	event_select_container.offset_right = 180.0
	event_select_container.offset_bottom = 160.0
	event_select_container.add_theme_constant_override("separation", 20)
	event_select_container.visible = false
	add_child(event_select_container)

	# Title
	var title = Label.new()
	title.text = "PICK EVENT"
	var title_settings = LabelSettings.new()
	title_settings.font_size = 42
	title_settings.font_color = Color(1, 0.3, 0.3)
	title_settings.outline_size = 4
	title_settings.outline_color = Color(0, 0, 0)
	title.label_settings = title_settings
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_select_container.add_child(title)

	# Event buttons
	for event_info in events:
		var btn = Button.new()
		btn.text = event_info.name
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_theme_stylebox_override("normal", _make_map_btn_style(Color(0.25, 0.1, 0.1)))
		btn.add_theme_stylebox_override("hover", _make_map_btn_style(Color(0.45, 0.15, 0.15)))
		btn.add_theme_stylebox_override("pressed", _make_map_btn_style(Color(0.18, 0.06, 0.06)))
		btn.pressed.connect(_on_event_selected.bind(event_info.scene))
		btn.mouse_entered.connect(_on_button_hover.bind(btn))
		event_select_container.add_child(btn)

	# Back button
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.add_theme_stylebox_override("normal", _make_map_btn_style(Color(0.25, 0.12, 0.12)))
	back_btn.add_theme_stylebox_override("hover", _make_map_btn_style(Color(0.4, 0.2, 0.2)))
	back_btn.add_theme_stylebox_override("pressed", _make_map_btn_style(Color(0.18, 0.08, 0.08)))
	back_btn.pressed.connect(_on_event_select_back_pressed)
	event_select_container.add_child(back_btn)

func _make_map_btn_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 20.0
	style.content_margin_top = 10.0
	style.content_margin_right = 20.0
	style.content_margin_bottom = 10.0
	return style

func _on_button_hover(button: Button):
	var splatter = _create_splatter(button.size)
	splatter.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(splatter)

func _create_splatter(button_size: Vector2) -> Control:
	var node = Control.new()
	node.mouse_filter = MOUSE_FILTER_IGNORE

	var blobs := []
	var center = Vector2(randf_range(10, button_size.x - 10), randf_range(5, button_size.y - 5))
	var num = randi_range(5, 9)
	for i in num:
		blobs.append({
			"pos": center + Vector2(randf_range(-25, 25), randf_range(-20, 20)),
			"radius": randf_range(4.0, 14.0),
			"color": Color(randf_range(0.5, 0.8), 0.0, 0.0, randf_range(0.5, 0.85))
		})

	node.draw.connect(func():
		for b in blobs:
			node.draw_circle(b.pos, b.radius, b.color)
	)
	node.ready.connect(func(): node.queue_redraw())
	return node

func _on_play_pressed():
	$MenuContainer.visible = false
	map_select_container.visible = true

func _on_events_pressed():
	$MenuContainer.visible = false
	event_map_select_container.visible = true

func _on_back_pressed():
	map_select_container.visible = false
	$MenuContainer.visible = true

func _on_event_map_back_pressed():
	event_map_select_container.visible = false
	$MenuContainer.visible = true

func _on_event_map_selected(map_path: String):
	selected_event_map = map_path
	event_map_select_container.visible = false
	event_select_container.visible = true

func _on_event_select_back_pressed():
	event_select_container.visible = false
	event_map_select_container.visible = true

func _on_event_selected(event_scene_path: String):
	get_tree().set_meta("event_map_path", selected_event_map)
	get_tree().change_scene_to_file(event_scene_path)

func _on_map_selected(scene_path: String):
	get_tree().change_scene_to_file(scene_path)

func _on_multiplayer_pressed():
	get_tree().change_scene_to_file("res://multiplayer/multiplayer_menu.tscn")

func _on_quit_pressed():
	get_tree().quit()

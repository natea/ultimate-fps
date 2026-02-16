extends Control

var name_input: LineEdit
var ip_input: LineEdit
var status_label: Label
var host_btn: Button
var join_btn: Button
var back_btn: Button

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _process(_delta):
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_ui():
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var container = VBoxContainer.new()
	container.set_anchors_preset(PRESET_CENTER)
	container.offset_left = -200.0
	container.offset_top = -200.0
	container.offset_right = 200.0
	container.offset_bottom = 200.0
	container.add_theme_constant_override("separation", 16)
	add_child(container)

	# Title
	var title = Label.new()
	title.text = "MULTIPLAYER"
	var title_settings = LabelSettings.new()
	title_settings.font_size = 48
	title_settings.font_color = Color(1, 1, 1)
	title_settings.outline_size = 4
	title_settings.outline_color = Color(0, 0, 0)
	title.label_settings = title_settings
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	# Name input
	var name_label = Label.new()
	name_label.text = "Your Name:"
	name_label.add_theme_font_size_override("font_size", 18)
	container.add_child(name_label)

	name_input = LineEdit.new()
	name_input.text = "Player"
	name_input.max_length = 16
	name_input.add_theme_font_size_override("font_size", 20)
	container.add_child(name_input)

	# IP input
	var ip_label = Label.new()
	ip_label.text = "Server IP (for joining):"
	ip_label.add_theme_font_size_override("font_size", 18)
	container.add_child(ip_label)

	ip_input = LineEdit.new()
	ip_input.text = "127.0.0.1"
	ip_input.add_theme_font_size_override("font_size", 20)
	container.add_child(ip_input)

	# Buttons
	var btn_container = HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 12)
	container.add_child(btn_container)

	host_btn = Button.new()
	host_btn.text = "Host Game"
	host_btn.add_theme_font_size_override("font_size", 22)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host_pressed)
	btn_container.add_child(host_btn)

	join_btn = Button.new()
	join_btn.text = "Join Game"
	join_btn.add_theme_font_size_override("font_size", 22)
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join_pressed)
	btn_container.add_child(join_btn)

	# Status label
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(status_label)

	# Back button
	back_btn = Button.new()
	back_btn.text = "Back to Menu"
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.pressed.connect(_on_back_pressed)
	container.add_child(back_btn)

func _on_host_pressed():
	var pname = name_input.text.strip_edges()
	if pname == "":
		pname = "Host"
	status_label.text = "Starting server..."
	var err = NetworkManager.host_game(pname)
	if err != OK:
		status_label.text = "Failed to create server (error %d)" % err
		return
	get_tree().change_scene_to_file("res://multiplayer/lobby.tscn")

func _on_join_pressed():
	var pname = name_input.text.strip_edges()
	if pname == "":
		pname = "Player"
	var ip = ip_input.text.strip_edges()
	if ip == "":
		status_label.text = "Enter a server IP address"
		return
	status_label.text = "Connecting to %s..." % ip
	host_btn.disabled = true
	join_btn.disabled = true
	var err = NetworkManager.join_game(ip, pname)
	if err != OK:
		status_label.text = "Failed to connect (error %d)" % err
		host_btn.disabled = false
		join_btn.disabled = false
		return
	# Wait briefly for connection, then go to lobby
	await get_tree().create_timer(1.0).timeout
	if NetworkManager.multiplayer.multiplayer_peer != null:
		get_tree().change_scene_to_file("res://multiplayer/lobby.tscn")
	else:
		status_label.text = "Connection failed"
		host_btn.disabled = false
		join_btn.disabled = false

func _on_connection_failed():
	status_label.text = "Connection failed"
	host_btn.disabled = false
	join_btn.disabled = false

func _on_back_pressed():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

extends Control

var player_list: VBoxContainer
var map_selector: OptionButton
var kill_limit_spin: SpinBox
var time_limit_spin: SpinBox
var start_btn: Button
var status_label: Label

var mp_maps := [
	{"name": "Arena", "scene": "res://levels/arena.tscn"},
	{"name": "Ruins", "scene": "res://levels/ruins.tscn"},
]

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_refresh_player_list()
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

func _process(_delta):
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_ui():
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var main_container = VBoxContainer.new()
	main_container.set_anchors_preset(PRESET_CENTER)
	main_container.offset_left = -250.0
	main_container.offset_top = -250.0
	main_container.offset_right = 250.0
	main_container.offset_bottom = 250.0
	main_container.add_theme_constant_override("separation", 12)
	add_child(main_container)

	# Title
	var title = Label.new()
	title.text = "LOBBY"
	var title_settings = LabelSettings.new()
	title_settings.font_size = 48
	title_settings.font_color = Color(1, 1, 1)
	title_settings.outline_size = 4
	title_settings.outline_color = Color(0, 0, 0)
	title.label_settings = title_settings
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)

	# Player list header
	var players_header = Label.new()
	players_header.text = "Players:"
	players_header.add_theme_font_size_override("font_size", 22)
	main_container.add_child(players_header)

	# Player list
	player_list = VBoxContainer.new()
	player_list.add_theme_constant_override("separation", 4)
	main_container.add_child(player_list)

	# Settings (host only)
	if NetworkManager.is_host():
		var settings_label = Label.new()
		settings_label.text = "Match Settings:"
		settings_label.add_theme_font_size_override("font_size", 22)
		main_container.add_child(settings_label)

		# Map selector
		var map_row = HBoxContainer.new()
		var map_label = Label.new()
		map_label.text = "Map: "
		map_label.add_theme_font_size_override("font_size", 18)
		map_row.add_child(map_label)
		map_selector = OptionButton.new()
		for map_info in mp_maps:
			map_selector.add_item(map_info.name)
		map_selector.add_theme_font_size_override("font_size", 18)
		map_row.add_child(map_selector)
		main_container.add_child(map_row)

		# Kill limit
		var kill_row = HBoxContainer.new()
		var kill_label = Label.new()
		kill_label.text = "Kill Limit: "
		kill_label.add_theme_font_size_override("font_size", 18)
		kill_row.add_child(kill_label)
		kill_limit_spin = SpinBox.new()
		kill_limit_spin.min_value = 5
		kill_limit_spin.max_value = 50
		kill_limit_spin.value = 20
		kill_limit_spin.step = 5
		kill_row.add_child(kill_limit_spin)
		main_container.add_child(kill_row)

		# Time limit
		var time_row = HBoxContainer.new()
		var time_label = Label.new()
		time_label.text = "Time Limit (min): "
		time_label.add_theme_font_size_override("font_size", 18)
		time_row.add_child(time_label)
		time_limit_spin = SpinBox.new()
		time_limit_spin.min_value = 3
		time_limit_spin.max_value = 30
		time_limit_spin.value = 10
		time_limit_spin.step = 1
		time_row.add_child(time_limit_spin)
		main_container.add_child(time_row)

		# Start button
		start_btn = Button.new()
		start_btn.text = "Start Match"
		start_btn.add_theme_font_size_override("font_size", 24)
		start_btn.pressed.connect(_on_start_pressed)
		main_container.add_child(start_btn)
	else:
		status_label = Label.new()
		status_label.text = "Waiting for host to start..."
		status_label.add_theme_font_size_override("font_size", 20)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_container.add_child(status_label)

	# Leave button
	var leave_btn = Button.new()
	leave_btn.text = "Leave"
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.pressed.connect(_on_leave_pressed)
	main_container.add_child(leave_btn)

func _refresh_player_list():
	for child in player_list.get_children():
		child.queue_free()
	for peer_id in NetworkManager.players:
		var info = NetworkManager.players[peer_id]
		var label = Label.new()
		var host_tag = " (Host)" if peer_id == 1 else ""
		var you_tag = " (You)" if peer_id == multiplayer.get_unique_id() else ""
		label.text = "  %s%s%s" % [info["name"], host_tag, you_tag]
		label.add_theme_font_size_override("font_size", 20)
		player_list.add_child(label)

func _on_player_connected(_peer_id: int, _info: Dictionary):
	_refresh_player_list()

func _on_player_disconnected(_peer_id: int):
	_refresh_player_list()

func _on_server_disconnected():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _on_start_pressed():
	# Apply settings
	var map_idx = map_selector.get_selected_id()
	NetworkManager.match_map_path = mp_maps[map_idx]["scene"]
	NetworkManager.match_kill_limit = int(kill_limit_spin.value)
	NetworkManager.match_time_limit = time_limit_spin.value * 60.0
	NetworkManager.start_match()

func _on_leave_pressed():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

extends Control

var player_list: VBoxContainer
var map_selector: OptionButton
var kill_limit_spin: SpinBox
var time_limit_spin: SpinBox
var start_btn: Button
var status_label: Label
var notification_label: Label

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
		# Show host IPs so others can connect
		var ips = _get_local_ips()
		var ip_label = Label.new()
		if ips.size() == 1:
			ip_label.text = "Your IP: %s" % ips[0]
		elif ips.size() > 1:
			ip_label.text = "Your IPs: %s" % ", ".join(ips)
		else:
			ip_label.text = "Your IP: unknown"
		ip_label.add_theme_font_size_override("font_size", 18)
		ip_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		ip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		main_container.add_child(ip_label)

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
		_apply_button_style(map_selector)
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
		_style_spinbox(kill_limit_spin)
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
		_style_spinbox(time_limit_spin)
		time_row.add_child(time_limit_spin)
		main_container.add_child(time_row)

		# Start button
		start_btn = Button.new()
		start_btn.text = "Start Match"
		start_btn.add_theme_font_size_override("font_size", 24)
		_apply_button_style(start_btn)
		start_btn.pressed.connect(_on_start_pressed)
		main_container.add_child(start_btn)
	else:
		status_label = Label.new()
		status_label.text = "Waiting for host to start..."
		status_label.add_theme_font_size_override("font_size", 20)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_container.add_child(status_label)

	# Notification label (player join/leave)
	notification_label = Label.new()
	notification_label.text = ""
	notification_label.add_theme_font_size_override("font_size", 16)
	notification_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(notification_label)

	# Leave button
	var leave_btn = Button.new()
	leave_btn.text = "Leave"
	leave_btn.add_theme_font_size_override("font_size", 18)
	_apply_button_style(leave_btn)
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
	_show_notification("%s joined" % _info.get("name", "Player"))

func _on_player_disconnected(_peer_id: int):
	_refresh_player_list()
	_show_notification("A player left")

func _show_notification(text: String):
	if notification_label:
		notification_label.text = text
		# Clear after 3 seconds
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(notification_label) and notification_label.text == text:
				notification_label.text = ""
		)

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

func _get_local_ips() -> Array[String]:
	var ips: Array[String] = []
	# Known VM/VPN/virtual interface subnets to deprioritize
	var vm_prefixes = ["100.", "192.168.64.", "192.168.99.", "10.211.55.", "10.37.129.", "172.16.", "198.18."]
	var vm_ips: Array[String] = []
	for addr in IP.get_local_addresses():
		if addr.begins_with("127.") or ":" in addr:
			continue
		var is_vm = false
		for prefix in vm_prefixes:
			if addr.begins_with(prefix):
				is_vm = true
				break
		if is_vm:
			vm_ips.append(addr)
		else:
			ips.append(addr)
	# Show real IPs first, then VM IPs as fallback
	ips.append_array(vm_ips)
	return ips

func _apply_button_style(btn: Control):
	btn.add_theme_stylebox_override("normal", _make_style(Color(0.18, 0.18, 0.25, 1)))
	btn.add_theme_stylebox_override("hover", _make_style(Color(0.3, 0.3, 0.45, 1)))
	btn.add_theme_stylebox_override("pressed", _make_style(Color(0.15, 0.15, 0.2, 1)))

func _style_spinbox(spin: SpinBox):
	var line_edit = spin.get_line_edit()
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.18, 0.18, 0.25, 1)
	input_style.border_color = Color(0.35, 0.35, 0.45, 1)
	input_style.border_width_bottom = 2
	input_style.border_width_top = 2
	input_style.border_width_left = 2
	input_style.border_width_right = 2
	input_style.corner_radius_top_left = 4
	input_style.corner_radius_top_right = 4
	input_style.corner_radius_bottom_right = 4
	input_style.corner_radius_bottom_left = 4
	input_style.content_margin_left = 10.0
	input_style.content_margin_top = 6.0
	input_style.content_margin_right = 10.0
	input_style.content_margin_bottom = 6.0
	line_edit.add_theme_stylebox_override("normal", input_style)

func _make_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 20.0
	style.content_margin_top = 12.0
	style.content_margin_right = 20.0
	style.content_margin_bottom = 12.0
	return style

func _on_leave_pressed():
	NetworkManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

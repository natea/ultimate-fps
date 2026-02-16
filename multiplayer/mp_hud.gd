extends CanvasLayer

var timer_label: Label
var kill_feed: VBoxContainer
var scoreboard_panel: PanelContainer
var scoreboard_list: VBoxContainer
var death_overlay: ColorRect
var death_label: Label
var result_panel: PanelContainer
var result_label: Label
var countdown_label: Label

var match_manager: MatchManager

func _ready():
	layer = 10
	_build_ui()
	await get_tree().process_frame
	match_manager = get_tree().get_first_node_in_group("match_manager")
	if match_manager:
		match_manager.scores_updated.connect(_on_scores_updated)
		match_manager.player_killed.connect(_on_player_killed)
		match_manager.match_started.connect(_on_match_started)
		match_manager.match_ended.connect(_on_match_ended)
		match_manager.countdown_tick.connect(_on_countdown_tick)

func _process(_delta):
	# Update timer
	if match_manager and match_manager.match_active:
		var mins = int(match_manager.match_time_remaining) / 60
		var secs = int(match_manager.match_time_remaining) % 60
		timer_label.text = "%d:%02d" % [mins, secs]

	# Toggle scoreboard
	if Input.is_action_pressed("scoreboard"):
		scoreboard_panel.visible = true
		_refresh_scoreboard()
	else:
		scoreboard_panel.visible = false

func _build_ui():
	# Match timer (top center)
	timer_label = Label.new()
	timer_label.text = "10:00"
	var timer_settings = LabelSettings.new()
	timer_settings.font_size = 32
	timer_settings.font_color = Color(1, 1, 1)
	timer_settings.outline_size = 3
	timer_settings.outline_color = Color(0, 0, 0)
	timer_label.label_settings = timer_settings
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.offset_top = 10
	timer_label.offset_left = -40
	timer_label.offset_right = 40
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(timer_label)

	# Kill feed (top right)
	kill_feed = VBoxContainer.new()
	kill_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_feed.offset_left = -300
	kill_feed.offset_top = 10
	kill_feed.offset_right = -10
	kill_feed.offset_bottom = 200
	kill_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(kill_feed)

	# Countdown label (center)
	countdown_label = Label.new()
	countdown_label.text = ""
	var cd_settings = LabelSettings.new()
	cd_settings.font_size = 72
	cd_settings.font_color = Color(1, 0.9, 0.2)
	cd_settings.outline_size = 5
	cd_settings.outline_color = Color(0, 0, 0)
	countdown_label.label_settings = cd_settings
	countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	countdown_label.offset_left = -100
	countdown_label.offset_right = 100
	countdown_label.offset_top = -50
	countdown_label.offset_bottom = 50
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.visible = false
	add_child(countdown_label)

	# Scoreboard (Tab overlay)
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.offset_left = -250
	scoreboard_panel.offset_top = -150
	scoreboard_panel.offset_right = 250
	scoreboard_panel.offset_bottom = 150
	scoreboard_panel.visible = false
	var sb_style = StyleBoxFlat.new()
	sb_style.bg_color = Color(0, 0, 0, 0.8)
	sb_style.corner_radius_top_left = 8
	sb_style.corner_radius_top_right = 8
	sb_style.corner_radius_bottom_left = 8
	sb_style.corner_radius_bottom_right = 8
	sb_style.content_margin_left = 20
	sb_style.content_margin_top = 20
	sb_style.content_margin_right = 20
	sb_style.content_margin_bottom = 20
	scoreboard_panel.add_theme_stylebox_override("panel", sb_style)
	add_child(scoreboard_panel)

	scoreboard_list = VBoxContainer.new()
	scoreboard_list.add_theme_constant_override("separation", 6)
	scoreboard_panel.add_child(scoreboard_list)

	# Death overlay
	death_overlay = ColorRect.new()
	death_overlay.color = Color(0.3, 0, 0, 0.5)
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.visible = false
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(death_overlay)

	death_label = Label.new()
	var dl_settings = LabelSettings.new()
	dl_settings.font_size = 36
	dl_settings.font_color = Color(1, 1, 1)
	dl_settings.outline_size = 4
	dl_settings.outline_color = Color(0, 0, 0)
	death_label.label_settings = dl_settings
	death_label.set_anchors_preset(Control.PRESET_CENTER)
	death_label.offset_left = -200
	death_label.offset_right = 200
	death_label.offset_top = -30
	death_label.offset_bottom = 30
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.visible = false
	add_child(death_label)

	# Result panel
	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.offset_left = -200
	result_panel.offset_top = -100
	result_panel.offset_right = 200
	result_panel.offset_bottom = 100
	result_panel.visible = false
	var rp_style = StyleBoxFlat.new()
	rp_style.bg_color = Color(0, 0, 0, 0.9)
	rp_style.corner_radius_top_left = 8
	rp_style.corner_radius_top_right = 8
	rp_style.corner_radius_bottom_left = 8
	rp_style.corner_radius_bottom_right = 8
	rp_style.content_margin_left = 20
	rp_style.content_margin_top = 20
	rp_style.content_margin_right = 20
	rp_style.content_margin_bottom = 20
	result_panel.add_theme_stylebox_override("panel", rp_style)
	add_child(result_panel)

	result_label = Label.new()
	var rl_settings = LabelSettings.new()
	rl_settings.font_size = 28
	rl_settings.font_color = Color(1, 0.9, 0.2)
	rl_settings.outline_size = 3
	rl_settings.outline_color = Color(0, 0, 0)
	result_label.label_settings = rl_settings
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_panel.add_child(result_label)

func _refresh_scoreboard():
	for child in scoreboard_list.get_children():
		child.queue_free()

	# Header
	var header = Label.new()
	header.text = "Player                 Kills   Deaths"
	header.add_theme_font_size_override("font_size", 18)
	scoreboard_list.add_child(header)

	if match_manager == null:
		return

	# Sort by kills descending
	var sorted_ids = match_manager.scores.keys()
	sorted_ids.sort_custom(func(a, b):
		return match_manager.scores[a]["kills"] > match_manager.scores[b]["kills"]
	)

	for peer_id in sorted_ids:
		var info = match_manager.scores[peer_id]
		var pname = NetworkManager.get_player_name(peer_id)
		var label = Label.new()
		label.text = "%-20s %5d   %5d" % [pname, info["kills"], info["deaths"]]
		label.add_theme_font_size_override("font_size", 16)
		if peer_id == multiplayer.get_unique_id():
			label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		scoreboard_list.add_child(label)

func _add_kill_feed_entry(text: String):
	var label = Label.new()
	label.text = text
	var settings = LabelSettings.new()
	settings.font_size = 16
	settings.font_color = Color(1, 1, 1)
	settings.outline_size = 2
	settings.outline_color = Color(0, 0, 0)
	label.label_settings = settings
	kill_feed.add_child(label)

	# Remove after 5 seconds
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(label):
		label.queue_free()

	# Keep max 5 entries
	while kill_feed.get_child_count() > 5:
		kill_feed.get_child(0).queue_free()

func show_death_screen(killer_name: String):
	death_overlay.visible = true
	death_label.visible = true
	death_label.text = "Killed by %s" % killer_name
	await get_tree().create_timer(4.0).timeout
	death_overlay.visible = false
	death_label.visible = false

func _on_scores_updated(_scores: Dictionary):
	pass  # Scoreboard refreshes on Tab press

func _on_player_killed(killer_id: int, victim_id: int):
	var killer_name = NetworkManager.get_player_name(killer_id)
	var victim_name = NetworkManager.get_player_name(victim_id)
	_add_kill_feed_entry("%s killed %s" % [killer_name, victim_name])

	# Show death screen if we're the victim
	if victim_id == multiplayer.get_unique_id():
		show_death_screen(killer_name)

func _on_match_started():
	countdown_label.visible = false
	timer_label.visible = true

func _on_match_ended(winner_id: int, final_scores: Dictionary):
	var winner_name = NetworkManager.get_player_name(winner_id)
	result_label.text = "%s wins!\n\nReturning to lobby..." % winner_name
	result_panel.visible = true

func _on_countdown_tick(seconds: int):
	countdown_label.visible = true
	countdown_label.text = str(seconds)
	if seconds <= 0:
		countdown_label.text = "GO!"
		await get_tree().create_timer(0.5).timeout
		countdown_label.visible = false

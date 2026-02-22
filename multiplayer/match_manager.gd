extends Node
class_name MatchManager

var scores := {}  # { peer_id: { "kills": int, "deaths": int } }
var match_time_remaining := 600.0
var kill_limit := 20
var match_active := false
var countdown_active := false
var countdown_time := 3.0

# Death tracking
var dead_players := {}  # { peer_id: respawn_timer }
var respawn_delay := 4.0

signal scores_updated(scores: Dictionary)
signal match_started
signal match_ended(winner_id: int, final_scores: Dictionary)
signal player_killed(killer_id: int, victim_id: int)
signal countdown_tick(seconds: int)

func _ready():
	add_to_group("match_manager")
	kill_limit = NetworkManager.match_kill_limit
	match_time_remaining = NetworkManager.match_time_limit

	# Initialize scores for all players
	for peer_id in NetworkManager.players:
		scores[peer_id] = {"kills": 0, "deaths": 0}

	if NetworkManager.is_host():
		# Start countdown
		start_countdown()

func start_countdown():
	countdown_active = true
	countdown_time = 3.0
	_sync_countdown.rpc(3)

func _physics_process(delta):
	if not NetworkManager.is_host():
		return

	if countdown_active:
		countdown_time -= delta
		var sec = ceili(countdown_time)
		if countdown_time <= 0:
			countdown_active = false
			match_active = true
			_sync_match_start.rpc()
		return

	if not match_active:
		return

	# Match timer
	match_time_remaining -= delta
	if fmod(match_time_remaining, 1.0) < delta:
		_sync_time.rpc(match_time_remaining)

	if match_time_remaining <= 0:
		end_match()

	# Process respawn timers
	var to_respawn := []
	for peer_id in dead_players:
		dead_players[peer_id] -= delta
		if dead_players[peer_id] <= 0:
			to_respawn.append(peer_id)
	for peer_id in to_respawn:
		dead_players.erase(peer_id)
		var level = get_parent()
		if level.has_method("respawn_player"):
			level.respawn_player(peer_id)
		_sync_respawn.rpc(peer_id)

func on_player_killed(killer_id: int, victim_id: int):
	if not NetworkManager.is_host():
		return
	if not scores.has(killer_id):
		scores[killer_id] = {"kills": 0, "deaths": 0}
	if not scores.has(victim_id):
		scores[victim_id] = {"kills": 0, "deaths": 0}

	scores[killer_id]["kills"] += 1
	scores[victim_id]["deaths"] += 1

	# Start respawn timer
	dead_players[victim_id] = respawn_delay

	# Broadcast
	var killer_name = NetworkManager.get_player_name(killer_id)
	var victim_name = NetworkManager.get_player_name(victim_id)
	_sync_kill.rpc(killer_id, victim_id, killer_name, victim_name, scores)

	# Check win condition
	if scores[killer_id]["kills"] >= kill_limit:
		end_match()

func end_match():
	if not match_active:
		return
	match_active = false

	# Find winner (most kills)
	var winner_id := -1
	var max_kills := -1
	for peer_id in scores:
		if scores[peer_id]["kills"] > max_kills:
			max_kills = scores[peer_id]["kills"]
			winner_id = peer_id

	_sync_match_end.rpc(winner_id, scores)

# --- RPCs ---

@rpc("authority", "call_local", "reliable")
func _sync_countdown(seconds: int):
	countdown_tick.emit(seconds)

@rpc("authority", "call_local", "reliable")
func _sync_match_start():
	match_active = true
	match_started.emit()

@rpc("authority", "call_local", "reliable")
func _sync_time(time: float):
	match_time_remaining = time

@rpc("authority", "call_local", "reliable")
func _sync_kill(killer_id: int, victim_id: int, killer_name: String, victim_name: String, new_scores: Dictionary):
	scores = new_scores
	player_killed.emit(killer_id, victim_id)
	scores_updated.emit(scores)

@rpc("authority", "call_local", "reliable")
func _sync_respawn(peer_id: int):
	# Re-enable the player
	pass  # deathmatch_level handles the actual teleport

@rpc("authority", "call_local", "reliable")
func _sync_match_end(winner_id: int, final_scores: Dictionary):
	match_active = false
	scores = final_scores
	match_ended.emit(winner_id, final_scores)

	# Return to lobby after 10 seconds
	await get_tree().create_timer(10.0).timeout
	NetworkManager.return_to_lobby()

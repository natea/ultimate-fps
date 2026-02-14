extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var skeleton: Skeleton3D = $Armature/Skeleton3D

var current_state := "idle"

func _ready():
	# Start with idle/gunplay animation
	if animation_player.has_animation("Gunplay"):
		animation_player.play("Gunplay")

func play_animation(anim_name: String):
	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		current_state = anim_name

func set_walking(is_walking: bool, is_running: bool):
	if is_running and animation_player.has_animation("Run Forward"):
		if current_state != "run":
			animation_player.play("Run Forward")
			current_state = "run"
	elif is_walking and animation_player.has_animation("Walking"):
		if current_state != "walk":
			animation_player.play("Walking")
			current_state = "walk"
	else:
		if current_state != "idle" and animation_player.has_animation("Gunplay"):
			animation_player.play("Gunplay")
			current_state = "idle"

func get_hand_bone_transform() -> Transform3D:
	if skeleton:
		var hand_idx = skeleton.find_bone("RightHand")
		if hand_idx == -1:
			hand_idx = skeleton.find_bone("mixamorig:RightHand")
		if hand_idx != -1:
			return skeleton.get_bone_global_pose(hand_idx)
	return Transform3D.IDENTITY

extends Resource
class_name Weapon

@export_subgroup("Model")
@export var model: PackedScene
@export var position: Vector3 = Vector3(0.3, -0.2, -0.5)
@export var rotation: Vector3 = Vector3(0, 180, 0)
@export var scale: float = 1.0
@export var muzzle_position: Vector3 = Vector3(0, 0, 0.5)

@export_subgroup("Properties")
@export var weapon_name: String = "Weapon"
@export_range(0.05, 2.0) var cooldown: float = 0.1
@export_range(1, 100) var max_distance: int = 50
@export_range(1, 100) var damage: float = 25
@export_range(0, 5) var spread: float = 0
@export_range(1, 10) var shot_count: int = 1
@export var automatic: bool = false

@export_subgroup("Ammo")
@export var magazine_size: int = 12
@export var max_ammo: int = 120
@export var reload_time: float = 1.5

@export_subgroup("Recoil")
@export var recoil_vertical: Vector2 = Vector2(0.01, 0.02)
@export var recoil_horizontal: Vector2 = Vector2(-0.01, 0.01)
@export var knockback: float = 0.5

@export_subgroup("Sounds")
@export var sound_shoot: String = ""
@export var sound_reload: String = ""
@export var sound_empty: String = ""

@export_subgroup("Aim Down Sights")
@export var ads_fov: float = 50.0  # FOV when aiming (lower = more zoom)
@export var ads_position: Vector3 = Vector3(0, -0.1, -0.3)  # Centered position when aiming
@export var has_scope: bool = false  # Shows scope overlay when aiming

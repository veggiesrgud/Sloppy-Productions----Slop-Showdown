extends Resource
class_name Weapon
@export_subgroup("Model")
@export var model: PackedScene
@export var position: Vector3
@export var rotation: Vector3
@export var scale: Vector3 = Vector3.ONE
@export var muzzle_position: Vector3
@export_subgroup("Properties")
@export_range(0.1, 1) var cooldown: float = 0.1
@export_range(1, 20) var max_distance: int = 10
@export_range(0, 100) var damage: float = 25
@export_range(0, 5) var spread: float = 0
@export_range(1, 5) var shot_count: int = 1
@export_range(0, 50) var knockback: int = 20
@export var min_knockback: Vector2 = Vector2(0.001, 0.001)
@export var max_knockback: Vector2 = Vector2(0.0025, 0.002)
@export_subgroup("Projectile")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 25.0
@export_subgroup("Sounds")
@export var sound_shoot: String
@export_subgroup("Crosshair")
@export var crosshair: Texture2D

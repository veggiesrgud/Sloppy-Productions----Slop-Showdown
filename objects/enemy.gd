extends Node3D

@export var player: Node3D

@onready var raycast = $RayCast
@onready var muzzle_a = $MuzzleA
@onready var muzzle_b = $MuzzleB
@onready var water_gun_left = get_node_or_null("WaterGunLeft")
@onready var water_gun_right = get_node_or_null("WaterGunRight")

@export var detection_range: float = 28.0
@export var shoot_range: float = 26.0
@export_range(0, 180) var detection_fov: float = 70.0
@export var turn_speed: float = 3.0

# Water gun projectile - same as player water_blaster
var droplet_scene: PackedScene = preload("res://objects/droplet.tscn")
@export var water_speed: float = 22.0
@export var water_damage: float = 8.0
@export var water_spread: float = 0.15

var health := 100
var time := 0.0
var target_position: Vector3
var destroyed := false
var player_in_sight: bool = false

# When ready, save the initial position

func _ready():
	add_to_group("enemy")
	target_position = position
	# Hide original blasters from enemy-flying.glb and show water guns
	var model = get_node_or_null("enemy-flying")
	if model:
		_hide_original_blasters(model)
	if water_gun_left:
		water_gun_left.visible = true
	if water_gun_right:
		water_gun_right.visible = true

func _hide_original_blasters(node: Node):
	if node is MeshInstance3D:
		var n = node.name.to_lower()
		if "blaster" in n:
			node.visible = false
	for c in node.get_children():
		_hide_original_blasters(c)


func _process(delta):
	# Always check distance for following, FOV only for shooting
	var to_player = player.global_position + Vector3(0, 0.5, 0) - global_position
	var dist = to_player.length()
	
	# Always turn to face player if within detection_range (even if outside FOV, so they can acquire)
	if dist < detection_range:
		var target = player.position + Vector3(0, 0.5, 0)
		var dir = (target - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			var target_basis = Basis.looking_at(-dir.normalized(), Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(target_basis, delta * turn_speed)
		# Follow player slowly when close (chase)
		if dist < 20 and dist > 3:
			var follow_dir = to_player.normalized()
			follow_dir.y = 0
			target_position += follow_dir * delta * 2.0  # slowly drift toward player
	
	# Update sight for shooting (FOV + LOS)
	player_in_sight = is_player_in_sight()
	
	target_position.y += (cos(time * 5) * 1) * delta  # Sine movement (up and down)

	time += delta

	position = target_position

# Take damage from player

func damage(amount):
	Audio.play("sounds/enemy_hurt.ogg")

	health -= amount

	if health <= 0 and !destroyed:
		destroy()

# Destroy the enemy when out of health

func destroy():
	Audio.play("sounds/enemy_destroy.ogg")

	destroyed = true
	queue_free()

func is_player_in_sight() -> bool:
	if not is_instance_valid(player):
		return false
	var player_pos = player.global_position + Vector3(0, 0.5, 0)
	var to_player_world = player_pos - raycast.global_position
	var dist = to_player_world.length()
	if dist > detection_range:
		return false
	# FOV check - forward is -Z
	var forward = -global_transform.basis.z.normalized()
	var dir_norm = to_player_world.normalized()
	var angle = rad_to_deg(acos(clamp(forward.dot(dir_norm), -1.0, 1.0)))
	if angle > detection_fov * 0.5:
		return false
	# Line of sight raycast to player - convert to local
	var local_target = raycast.global_transform.affine_inverse() * player_pos
	raycast.target_position = local_target
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var col = raycast.get_collider()
		# Only shoot if ray hits player (not wall) - also accept parent of collider if player is CharacterBody
		if col and col.has_method("damage"):
			# Check if collider is player or child of player
			if col == player or col.get_parent() == player or col.is_in_group("player"):
				return dist <= shoot_range
		return false
	# No hit means clear line but player is far - still consider in sight if within range
	return dist <= shoot_range

# Shoot when timer hits 0 - now shoots water droplets like player water gun

func _on_timer_timeout():
	if not player_in_sight:
		return
	# Re-validate LOS at shoot moment - allow hitting player or close
	raycast.force_raycast_update()
	var can_shoot = false
	if raycast.is_colliding():
		var col = raycast.get_collider()
		if col and col.has_method("damage") and (col == player or col.get_parent() == player or col.is_in_group("player")):
			can_shoot = true
	else:
		# No wall hit means clear line
		can_shoot = true
	if not can_shoot:
		return

	# Play muzzle flash animation(s)
	muzzle_a.frame = 0
	muzzle_a.play("default")
	muzzle_a.rotation_degrees.z = randf_range(-45, 45)

	muzzle_b.frame = 0
	muzzle_b.play("default")
	muzzle_b.rotation_degrees.z = randf_range(-45, 45)

	Audio.play("sounds/enemy_attack.ogg")

	# Spawn water droplets toward player (dual water guns)
	_spawn_water_projectile(muzzle_a.global_position)
	_spawn_water_projectile(muzzle_b.global_position)
	if water_gun_left:
		water_gun_left.visible = true
	if water_gun_right:
		water_gun_right.visible = true

func _spawn_water_projectile(spawn_pos: Vector3):
	var droplet = droplet_scene.instantiate()
	var base_dir = (player.global_position + Vector3(0, 0.3, 0) - spawn_pos).normalized()
	# Apply spread like water blaster
	var spread_x = randf_range(-water_spread, water_spread) * 0.5
	var spread_y = randf_range(-water_spread, water_spread) * 0.5
	var dir = (base_dir + global_transform.basis.x * spread_x + global_transform.basis.y * spread_y).normalized()
	if droplet.has_method("setup_enemy"):
		droplet.setup_enemy(dir, water_speed, water_damage)
	elif droplet.has_method("setup"):
		# fallback tag as enemy shot
		droplet.set("is_enemy_shot", true)
		droplet.setup(dir, water_speed, water_damage)
	else:
		droplet.velocity = dir * water_speed
		droplet.set("is_enemy_shot", true)
	# Add to main scene
	var world = get_tree().current_scene
	if world:
		world.add_child(droplet)
	else:
		get_tree().root.add_child(droplet)
	droplet.global_position = spawn_pos + dir * 0.2
	droplet.look_at(droplet.global_position + dir, Vector3.UP)

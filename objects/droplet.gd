# water droplet projectile - handles shooting, bouncing, and hitting players
extends Area3D

# how fast the droplet falls and how long it lasts before disappearing
@export var droplet_gravity: float = 0.5
@export var lifetime: float = 3.0

# movement and damage values
var speed: float = 25.0
var damage: float = 15.0
var velocity: Vector3
var time_alive: float = 0.0

# who shot this and if its from an enemy
var is_enemy_shot: bool = false
var shooter_id: int = 0
var bounces: int = 0
var exploded: bool = false

# bazooka-specific settings for splash damage
@export var is_bazooka := false
@export var splash_damage := 35.0
@export var splash_radius := 8.0
@export var knockback_force := 25.0

# how many times it can bounce before vanishing
const MAX_BOUNCES: int = 2
const BOUNCE_KEEP: float = 0.65

# called when the droplet is created
func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	await get_tree().create_timer(lifetime).timeout
	if is_inside_tree():
		queue_free()
# set up the droplet direction, speed, and damage
func setup(direction: Vector3, p_speed: float, p_damage: float, p_shooter_id: int = 0):
	speed = p_speed
	damage = p_damage
	shooter_id = p_shooter_id
	velocity = direction * speed
# set up enemy version of the droplet
func setup_enemy(direction: Vector3, p_speed: float, p_damage: float):
	is_enemy_shot = true
	speed = p_speed
	damage = p_damage
	velocity = direction * speed
# move the droplet every frame and check for wall hits
func _physics_process(delta):
	time_alive += delta
	velocity.y -= droplet_gravity * delta
	var target: Vector3 = global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, target)
	query.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = target
	elif is_bazooka:
		# bazooka rockets explode on first contact instead of ricocheting
		_explode_bazooka(hit["position"])
		return
	else:
		_bounce(hit["normal"], hit["position"])
	if velocity.length() > 0.1:
		look_at(global_position + velocity.normalized(), Vector3.UP)


# handle bouncing off walls
func _bounce(normal: Vector3, at: Vector3) -> void:
	bounces += 1
	if bounces > MAX_BOUNCES:
		spawn_impact()
		queue_free()
		return
	global_position = at + normal * 0.08
	velocity = velocity.bounce(normal) * BOUNCE_KEEP
	if velocity.length() < 3.0 and velocity.length() > 0.01:
		velocity = velocity.normalized() * 3.0
	spawn_impact()
# when something touches the droplet, deal damage or explode
func _on_body_entered(body):
	if is_bazooka:
		_explode_bazooka(global_position, body)
		return
	if is_enemy_shot:
		if body.is_in_group("player") or body.name == "Player":
			if multiplayer.has_multiplayer_peer() and not body.is_multiplayer_authority():
				return
			if body.has_method("damage"):
				body.damage(damage)
			spawn_impact()
			queue_free()
			return
		if body.is_in_group("enemy"):
			return
		if body.has_method("damage"):
			return
		if body is StaticBody3D or body is CSGShape3D or body is CollisionObject3D:
			spawn_impact()
			queue_free()
		else:
			spawn_impact()
			queue_free()
		return
	else:
		if body.is_in_group("player") or body.name == "Player":
			if shooter_id != 0 and body.get_multiplayer_authority() == shooter_id:
				return
			if body.has_method("take_pvp_hit"):
				body.take_pvp_hit.rpc(damage, shooter_id)
			spawn_impact()
			queue_free()
			return
		if body.has_method("damage"):
			body.damage(damage)
		spawn_impact()
		queue_free()

# bazooka explosion - deals full damage to the thing it hit and splash to nearby targets
func _explode_bazooka(impact_pos: Vector3, hit_body: Node = null) -> void:
	if exploded:
		return
	exploded = true
	var my_id := shooter_id

	# direct hit - full damage, no ricochet
	if hit_body is Node3D:
		if hit_body.is_in_group("player") or hit_body.name == "Player":
			if not (multiplayer.has_multiplayer_peer() and hit_body.get_multiplayer_authority() == my_id):
				if hit_body.has_method("take_pvp_hit"):
					var body_3d := hit_body as Node3D
					var dir := (body_3d.global_position - impact_pos).normalized()
					body_3d.take_pvp_hit.rpc(damage, my_id, dir, knockback_force)
		elif hit_body.has_method("damage"):
			hit_body.damage(damage)

	# splash damage to nearby players
	for player in get_tree().get_nodes_in_group("player"):
		if player == hit_body:
			continue
		if not (player is Node3D):
			continue
		var player_3d := player as Node3D
		var dist := impact_pos.distance_to(player_3d.global_position)
		if dist > splash_radius:
			continue
		if multiplayer.has_multiplayer_peer() and player.get_multiplayer_authority() == my_id:
			continue
		if player.has_method("take_pvp_hit"):
			var dir := (player_3d.global_position - impact_pos).normalized()
			player_3d.take_pvp_hit.rpc(splash_damage, my_id, dir, knockback_force)

	# splash damage to nearby enemies too
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == hit_body:
			continue
		if not (enemy is Node3D):
			continue
		var enemy_3d := enemy as Node3D
		if impact_pos.distance_to(enemy_3d.global_position) <= splash_radius and enemy.has_method("damage"):
			enemy.damage(splash_damage)

	_spawn_mini_explosion(impact_pos)
	queue_free()

# small expanding fireball + light flash for bazooka hits
func _spawn_mini_explosion(at: Vector3) -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	var explosion := Node3D.new()
	root.add_child(explosion)
	explosion.global_position = at

	var fireball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	fireball.mesh = sphere
	fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.albedo_color = Color(1.0, 0.55, 0.12, 0.9)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.45, 0.05)
	fire_mat.emission_energy_multiplier = 3.0
	fireball.material_override = fire_mat
	explosion.add_child(fireball)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.2)
	flash.light_energy = 5.0
	flash.omni_range = 5.0
	explosion.add_child(flash)

	var tween := explosion.create_tween()
	tween.set_parallel(true)
	tween.tween_property(fireball, "scale", Vector3.ONE * 3.5, 0.25)
	tween.tween_property(fire_mat, "albedo_color:a", 0.0, 0.25)
	tween.tween_property(flash, "light_energy", 0.0, 0.25)
	tween.chain().tween_callback(explosion.queue_free)

	var audio = get_node_or_null("/root/Audio")
	if audio and audio.has_method("play"):
		audio.play("sounds/land.ogg")

func _on_area_entered(area):
	if area == self:
		return
	if is_bazooka:
		_explode_bazooka(global_position, area)
		return
	if is_enemy_shot:
		if area.has_method("damage") and area.is_in_group("player"):
			area.damage(damage)
			spawn_impact()
			queue_free()
			return
		if area.is_in_group("enemy"):
			return
	else:
		if area.has_method("damage"):
			area.damage(damage)
			spawn_impact()
			queue_free()
			return
func _on_area_shape_entered(_area_rid, _area, _area_shape_index, _local_shape_index):
	pass
func spawn_impact():
	var impact = preload("res://objects/impact.tscn").instantiate()
	impact.play("shot")
	get_tree().root.add_child(impact)
	impact.global_position = global_position + Vector3(0, 0.1, 0)
	var audio = get_node_or_null("/root/Audio")
	if audio and audio.has_method("play"):
		audio.play("sounds/land.ogg")

extends Area3D
@export var droplet_gravity: float = 0.5
@export var lifetime: float = 3.0
var speed: float = 25.0
var damage: float = 15.0
var velocity: Vector3
var time_alive: float = 0.0
var is_enemy_shot: bool = false
var shooter_id: int = 0
var bounces: int = 0
const MAX_BOUNCES: int = 2
const BOUNCE_KEEP: float = 0.65
func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	await get_tree().create_timer(lifetime).timeout
	if is_inside_tree():
		queue_free()
func setup(direction: Vector3, p_speed: float, p_damage: float, p_shooter_id: int = 0):
	speed = p_speed
	damage = p_damage
	shooter_id = p_shooter_id
	velocity = direction * speed
func setup_enemy(direction: Vector3, p_speed: float, p_damage: float):
	is_enemy_shot = true
	speed = p_speed
	damage = p_damage
	velocity = direction * speed
func _physics_process(delta):
	time_alive += delta
	velocity.y -= droplet_gravity * delta
	var target: Vector3 = global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, target)
	query.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = target
	else:
		_bounce(hit["normal"], hit["position"])
	if velocity.length() > 0.1:
		look_at(global_position + velocity.normalized(), Vector3.UP)


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
func _on_body_entered(body):
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
func _on_area_entered(area):
	if area == self:
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

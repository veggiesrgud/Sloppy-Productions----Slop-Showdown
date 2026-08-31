extends Area3D

@export var droplet_gravity: float = 3.0
@export var lifetime: float = 3.0

var speed: float = 25.0
var damage: float = 15.0
var velocity: Vector3
var time_alive: float = 0.0
var is_enemy_shot: bool = false

func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	# Safety despawn
	await get_tree().create_timer(lifetime).timeout
	if is_inside_tree():
		queue_free()

func setup(direction: Vector3, p_speed: float, p_damage: float):
	speed = p_speed
	damage = p_damage
	velocity = direction * speed

func setup_enemy(direction: Vector3, p_speed: float, p_damage: float):
	is_enemy_shot = true
	speed = p_speed
	damage = p_damage
	velocity = direction * speed

func _physics_process(delta):
	time_alive += delta
	velocity.y -= droplet_gravity * delta
	global_position += velocity * delta
	if velocity.length() > 0.1:
		look_at(global_position + velocity.normalized(), Vector3.UP)

func _on_body_entered(body):
	if is_enemy_shot:
		# Enemy projectile - only damage player, ignore other enemies/world
		if body.is_in_group("player") or body.name == "Player":
			if body.has_method("damage"):
				body.damage(damage)
			spawn_impact()
			queue_free()
			return
		if body.is_in_group("enemy"):
			return
		if body.has_method("damage"):
			# ignore other damageables that are enemies
			return
		# hit world
		if body is StaticBody3D or body is CSGShape3D or body is CollisionObject3D:
			spawn_impact()
			queue_free()
		else:
			# generic world hit
			spawn_impact()
			queue_free()
		return
	else:
		# Player projectile - ignore player, damage enemies
		if body.is_in_group("player") or body.name == "Player":
			return
		if body.has_method("damage"):
			body.damage(damage)
		spawn_impact()
		queue_free()

func _on_area_entered(area):
	if area == self:
		return
	if is_enemy_shot:
		# Enemy projectile should hit player Area if player were Area (but player is CharacterBody), so ignore enemy Areas
		if area.has_method("damage") and area.is_in_group("player"):
			area.damage(damage)
			spawn_impact()
			queue_free()
			return
		if area.is_in_group("enemy"):
			return
	else:
		# Player projectile - Enemy is Area3D with damage method
		if area.has_method("damage"):
			area.damage(damage)
			spawn_impact()
			queue_free()
			return
	# Hit something else (wall/platform) - if area is not player, also impact
	# For world static, body_entered handles; for Area enemies, handled above

func _on_area_shape_entered(_area_rid, _area, _area_shape_index, _local_shape_index):
	pass

func spawn_impact():
	var impact = preload("res://objects/impact.tscn").instantiate()
	# Use hit animation but could use custom water splash
	impact.play("shot")
	get_tree().root.add_child(impact)
	impact.global_position = global_position + Vector3(0, 0.1, 0)
	# Optional: spawn smaller droplet splash
	var audio = get_node_or_null("/root/Audio")
	if audio and audio.has_method("play"):
		audio.play("sounds/land.ogg")

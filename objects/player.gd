extends CharacterBody3D
@export_subgroup("Movement")
@export var movement_speed = 5
@export var sprint_speed = 8.0
@export var crouch_speed = 2.5
@export var crouch_transition_speed = 8.0
@export var slide_speed = 10.0
@export var slide_duration = 0.8
@export_range(0, 100) var number_of_jumps: int = 2
@export var jump_strength = 8
@export_subgroup("Weapons")
@export var weapons: Array[Weapon] = []
var weapon: Weapon
var weapon_index := 0
var mouse_sensitivity = 700
var gamepad_sensitivity := 0.075
var mouse_captured := true
var movement_velocity: Vector3
var rotation_target: Vector3
var input_mouse: Vector2
var health: int = 100
var gravity := 0.0
var previously_floored := false
var jumps_remaining: int
var container_offset = Vector3(1.2, -1.1, -2.75)
var container_offset_crouch = Vector3(1.2, -0.9, -2.75)
var tween: Tween
var is_crouching := false
var is_sprinting := false
var is_sliding := false
var slide_timer := 0.0
var standing_head_height := 1.0
var crouching_head_height := 0.5
var standing_collider_height := 1.0
var crouching_collider_height := 0.5
var standing_collider_y := 0.55
var crouching_collider_y := 0.3
signal health_updated
@onready var head = $Head
@onready var camera = $Head/Camera
@onready var raycast = $Head/Camera/RayCast
@onready var muzzle = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Muzzle
@onready var container = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Container
@onready var sound_footsteps = $SoundFootsteps
@onready var blaster_cooldown = $Cooldown
@onready var collider = $Collider
@onready var ceiling_check: RayCast3D = null
@export var crosshair: TextureRect
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	_ensure_input_actions()
	standing_head_height = head.position.y
	crouching_head_height = standing_head_height - 0.5
	if collider and collider.shape is CapsuleShape3D:
		standing_collider_height = collider.shape.height
		standing_collider_y = collider.position.y
		crouching_collider_height = max(0.3, standing_collider_height - 0.5)
		crouching_collider_y = standing_collider_y - 0.25
	if not has_node("Head/CeilingCheck"):
		var rc = RayCast3D.new()
		rc.name = "CeilingCheck"
		rc.target_position = Vector3(0, 1.0, 0)
		rc.enabled = true
		rc.collision_mask = 1
		head.add_child(rc)
		ceiling_check = rc
	else:
		ceiling_check = get_node("Head/CeilingCheck")
	weapon = weapons[weapon_index]
	initiate_change_weapon(weapon_index)
func _ensure_input_actions():
	if not InputMap.has_action("sprint"):
		InputMap.add_action("sprint")
		var ev = InputEventKey.new()
		ev.physical_keycode = KEY_SHIFT
		InputMap.action_add_event("sprint", ev)
		var joy = InputEventJoypadButton.new()
		joy.button_index = JOY_BUTTON_LEFT_STICK
		InputMap.action_add_event("sprint", joy)
	if not InputMap.has_action("crouch"):
		InputMap.add_action("crouch")
		var ev2 = InputEventKey.new()
		ev2.physical_keycode = KEY_CTRL
		InputMap.action_add_event("crouch", ev2)
		var ev3 = InputEventKey.new()
		ev3.physical_keycode = KEY_C
		InputMap.action_add_event("crouch", ev3)
		var joy2 = InputEventJoypadButton.new()
		joy2.button_index = JOY_BUTTON_B
		InputMap.action_add_event("crouch", joy2)
	if not InputMap.has_action("weapon_1"):
		InputMap.add_action("weapon_1")
		var w1 = InputEventKey.new()
		w1.physical_keycode = KEY_1
		InputMap.action_add_event("weapon_1", w1)
	if not InputMap.has_action("weapon_2"):
		InputMap.add_action("weapon_2")
		var w2 = InputEventKey.new()
		w2.physical_keycode = KEY_2
		InputMap.action_add_event("weapon_2", w2)
func _process(delta):
	handle_controls(delta)
	handle_gravity(delta)
	handle_crouch_sprint(delta)
	var applied_velocity: Vector3
	movement_velocity = transform.basis * movement_velocity
	applied_velocity = velocity.lerp(movement_velocity, delta * 10)
	applied_velocity.y = - gravity
	velocity = applied_velocity
	move_and_slide()
	var effective_crouch = is_crouching or is_sliding
	var target_container = container_offset_crouch if effective_crouch else container_offset
	container.position = lerp(container.position, target_container - (basis.inverse() * applied_velocity / 30), delta * 10)
	sound_footsteps.stream_paused = true
	if is_on_floor():
		if abs(velocity.x) > 1 or abs(velocity.z) > 1:
			sound_footsteps.stream_paused = false
	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	if is_on_floor() and gravity > 1 and !previously_floored:
		Audio.play("sounds/land.ogg")
		camera.position.y = -0.1
	previously_floored = is_on_floor()
	if position.y < -10:
		get_tree().reload_current_scene()
func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		input_mouse = event.relative / mouse_sensitivity
		handle_rotation(event.relative.x, event.relative.y, false)
func handle_controls(delta):
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true
	if Input.is_action_just_pressed("mouse_capture_exit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false
		input_mouse = Vector2.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wants_crouch_hold = Input.is_action_pressed("crouch")
	var wants_sprint_hold = Input.is_action_pressed("sprint")
	if is_sliding:
		slide_timer += delta
		if not wants_crouch_hold or not is_on_floor() or slide_timer >= slide_duration or velocity.length() < 1.0:
			is_sliding = false
			if wants_crouch_hold:
				is_crouching = true
			else:
				if ceiling_check and ceiling_check.is_colliding():
					is_crouching = true
				else:
					is_crouching = false
			is_sprinting = false
		else:
			is_crouching = true
			is_sprinting = false
	else:
		if Input.is_action_just_pressed("crouch") and is_sprinting and is_on_floor() and input.y < -0.1 and velocity.length() > 4.0:
			is_sliding = true
			slide_timer = 0.0
			is_crouching = true
			is_sprinting = false
		else:
			var wants_crouch = wants_crouch_hold
			if is_crouching and not wants_crouch:
				if ceiling_check and ceiling_check.is_colliding():
					wants_crouch = true
			is_crouching = wants_crouch
			var wants_sprint = wants_sprint_hold and not is_crouching and not is_sliding and is_on_floor() and input.y < -0.1
			is_sprinting = wants_sprint
	var current_speed = movement_speed
	if is_sliding:
		var t = slide_timer / slide_duration
		current_speed = lerp(slide_speed, crouch_speed, t * 0.7)
	elif is_crouching:
		current_speed = crouch_speed
	elif is_sprinting:
		current_speed = sprint_speed
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * current_speed
	if is_sliding and input.length() < 0.1:
		movement_velocity = -transform.basis.z * current_speed
	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	if rotation_input:
		handle_rotation(rotation_input.x, rotation_input.y, true, delta)
	action_shoot()
	if is_sliding and Input.is_action_just_pressed("jump"):
		is_sliding = false
		if ceiling_check and ceiling_check.is_colliding():
			is_crouching = true
		else:
			is_crouching = false
	if Input.is_action_just_pressed("jump"):
		if jumps_remaining and not is_crouching:
			action_jump()
		elif jumps_remaining and is_crouching:
			action_jump()
	action_weapon_select()
func handle_rotation(xRot: float, yRot: float, isController: bool, delta: float = 0.0):
	if isController:
		rotation_target -= Vector3(-yRot, -xRot, 0).limit_length(1.0) * gamepad_sensitivity
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
		rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)
	else:
		rotation_target += (Vector3(-yRot, -xRot, 0) / mouse_sensitivity)
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = rotation_target.x;
		rotation.y = rotation_target.y;
func handle_gravity(delta):
	gravity += 20 * delta
	if gravity < 0 and is_on_ceiling():
		gravity = 0
	if gravity > 0 and is_on_floor():
		jumps_remaining = number_of_jumps
		gravity = 0
func handle_crouch_sprint(delta):
	var effective_crouch = is_crouching or is_sliding
	var target_head_y = crouching_head_height if effective_crouch else standing_head_height
	head.position.y = lerp(head.position.y, target_head_y, delta * crouch_transition_speed)
	if collider and collider.shape is CapsuleShape3D:
		var cap = collider.shape as CapsuleShape3D
		var target_h = crouching_collider_height if effective_crouch else standing_collider_height
		var target_y = crouching_collider_y if effective_crouch else standing_collider_y
		cap.height = lerp(cap.height, target_h, delta * crouch_transition_speed)
		collider.position.y = lerp(collider.position.y, target_y, delta * crouch_transition_speed)
	var target_fov = 80.0
	if is_sliding:
		target_fov = 90.0
	elif is_sprinting:
		target_fov = 85.0
	elif is_crouching:
		target_fov = 75.0
	camera.fov = lerp(camera.fov, target_fov, delta * 5.0)
	if is_sliding:
		sound_footsteps.pitch_scale = 1.5
		camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(-2.0), delta * 5.0)
	elif is_sprinting:
		sound_footsteps.pitch_scale = 1.3
		camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 5.0)
	elif is_crouching:
		sound_footsteps.pitch_scale = 0.7
		camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 5.0)
	else:
		sound_footsteps.pitch_scale = 1.0
		camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 5.0)
func action_jump():
	Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg, sounds/jump_c.ogg")
	gravity = - jump_strength
	jumps_remaining -= 1
func action_shoot():
	if Input.is_action_pressed("shoot"):
		if !blaster_cooldown.is_stopped(): return
		Audio.play(weapon.sound_shoot)
		muzzle.play("default")
		muzzle.rotation_degrees.z = randf_range(-45, 45)
		muzzle.scale = Vector3.ONE * randf_range(0.40, 0.75)
		muzzle.position = container.position - weapon.muzzle_position
		blaster_cooldown.start(weapon.cooldown)
		if weapon.projectile_scene != null:
			for n in weapon.shot_count:
				var droplet = weapon.projectile_scene.instantiate()
				var base_dir = -camera.global_transform.basis.z
				var spread_x = randf_range(-weapon.spread, weapon.spread) * 0.02
				var spread_y = randf_range(-weapon.spread, weapon.spread) * 0.02
				var dir = (base_dir + camera.global_transform.basis.x * spread_x + camera.global_transform.basis.y * spread_y).normalized()
				if droplet.has_method("setup"):
					droplet.setup(dir, weapon.projectile_speed, weapon.damage)
				else:
					droplet.velocity = dir * weapon.projectile_speed
				var spawn_offset = dir * 1.0 + Vector3(0, -0.15, 0)
				var world = get_tree().current_scene
				if world:
					world.add_child(droplet)
				else:
					get_tree().root.add_child(droplet)
				droplet.global_position = camera.global_position + spawn_offset
				droplet.look_at(droplet.global_position + dir, Vector3.UP)
		else:
			for n in weapon.shot_count:
				raycast.target_position.x = randf_range(-weapon.spread, weapon.spread)
				raycast.target_position.y = randf_range(-weapon.spread, weapon.spread)
				raycast.force_raycast_update()
				if !raycast.is_colliding(): continue
				var collider = raycast.get_collider()
				if collider.has_method("damage"):
					collider.damage(weapon.damage)
				var impact = preload("res://objects/impact.tscn")
				var impact_instance = impact.instantiate()
				impact_instance.play("shot")
				get_tree().root.add_child(impact_instance)
				impact_instance.position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
				impact_instance.look_at(camera.global_transform.origin, Vector3.UP, true)
		var knockback = random_vec2(weapon.min_knockback, weapon.max_knockback)
		container.position.z += 0.25
		camera.rotation.x += knockback.x
		rotation.y += knockback.y
		rotation_target.x += knockback.x
		rotation_target.y += knockback.y
		movement_velocity += Vector3(0, 0, weapon.knockback)
func action_weapon_select():
	if Input.is_action_just_pressed("weapon_1"):
		_select_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		_select_weapon(1)
func _select_weapon(index: int):
	if index < 0 or index >= weapons.size():
		return
	if index == weapon_index:
		return
	initiate_change_weapon(index)
	Audio.play("sounds/weapon_change.ogg")
func initiate_change_weapon(index):
	weapon_index = index
	tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(container, "position", container_offset - Vector3(0, 1, 0), 0.1)
	tween.tween_callback(change_weapon)
func change_weapon():
	weapon = weapons[weapon_index]
	for n in container.get_children():
		container.remove_child(n)
	var weapon_model = weapon.model.instantiate()
	container.add_child(weapon_model)
	weapon_model.position = weapon.position
	weapon_model.rotation_degrees = weapon.rotation
	weapon_model.scale = weapon.scale
	_apply_weapon_layer(weapon_model)
	_autofit_weapon_model(weapon_model)
	raycast.target_position = Vector3(0, 0, -1) * weapon.max_distance
	crosshair.texture = weapon.crosshair
func _apply_weapon_layer(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = 2
	for child in node.get_children():
		_apply_weapon_layer(child)
func _autofit_weapon_model(root: Node3D) -> void:
	var aabb := _weapon_aabb(root)
	if aabb.size == Vector3.ZERO:
		return
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	if longest > 2.5 or longest < 0.2:
		root.scale *= 1.0 / longest
func _weapon_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has := false
	var meshes: Array[Node] = []
	_collect_meshes(root, meshes)
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local_aabb: AABB = mi.mesh.get_aabb()
		var xform: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		local_aabb = xform * local_aabb
		if has:
			result = result.merge(local_aabb)
		else:
			result = local_aabb
			has = true
	return result
func _collect_meshes(node: Node, meshes: Array[Node]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child, meshes)
func damage(amount):
	health -= amount
	health_updated.emit(health)
	if health < 0:
		get_tree().reload_current_scene()
static func random_vec2(_min: Vector2, _max: Vector2) -> Vector2:
	var _sign = -1 if randi() % 2 == 0 else 1
	return Vector2(randf_range(_min.x, _max.x), randf_range(_min.y, _max.y) * _sign)

class_name Character
extends CharacterBody3D
enum SkinColor { BLUE, YELLOW, GREEN, RED }
const NORMAL_SPEED = 6.0
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 7.5
const FALL_GRAVITY_MULTIPLIER = 1.6
const BASE_NICKNAME_HEIGHT := 2.0
const SERVER_ANIMATION_REQUESTS_PER_SECOND := 10.0
const SERVER_ANIMATION_REQUEST_BURST := 6.0
const PICKUP_ANIMATION_DELAY_MSEC := 1000
const PICKUP_ANIMATION_WINDOW_MSEC := 2500
const PICKUP_REQUEST_COOLDOWN_MSEC := 1000
const ALLOWED_ANIMATION_STATES := {
	&"Idle": true,
	&"Run": true,
	&"Sprint": true,
	&"Jump": true,
	&"Jump2": true,
	&"Fall": true,
	&"Attack1": true,
	&"holdinggun": true,
	&"Emote2": true
}
const HAT_NODES_BY_ITEM := {
	"fedora": "Fedora",
	"headphones": "Headphones",
	"pirate_hat": "PirateHat",
	"sheriff_hat": "SheriffHat",
	"sombrero": "Sombrero",
	"wizard_hat": "WizardHat"
}
const WEAPON_NODES_BY_ITEM := {"water_gun": "WaterGun"}
const DROPLET_SCENE: PackedScene = preload("res://objects/droplet.tscn")
const WATER_WEAPON_ID := "water_gun"
const MELEE_DAMAGE := 25.0
const MELEE_RANGE := 3.2
const MELEE_IMPACT_SCENE: PackedScene = preload("res://objects/impact.tscn")
const MELEE_KNOCKBACK := 1.2
const PLAYER_SEPARATION_DISTANCE := 0.9
const PLAYER_SEPARATION_HEIGHT := 1.5
const WATER_DAMAGE := 25.0
const WATER_SPEED := 22.0
const BACKPACK_NODES_BY_ITEM := {"backpack": "Backpack"}
const HOLD_GUN_ARM_POSES := {
	&"upper_arm.L": Quaternion(-0.29569894, 0.6573955, -0.36813626, 0.5872554),
	&"upper_arm.R": Quaternion(0.03442656, 0.029669516, 0.65629834, 0.7531315),
}
const HEAD_EQUIPMENT_PATH := "GodotRobot3D/RobotArmature/Skeleton3D/HeadAttach/"
const HAND_EQUIPMENT_PATH := "GodotRobot3D/RobotArmature/Skeleton3D/RightHandAttach/"
const BACK_EQUIPMENT_PATH := "GodotRobot3D/RobotArmature/Skeleton3D/BackAttach/"
const FIRST_PERSON_HIDDEN_BONES: Array[StringName] = [&"Head", &"HeadTop"]
const SKIN_TINTS := {
	0: Color(0.25, 0.5, 0.95),
	1: Color(0.95, 0.78, 0.2),
	2: Color(0.3, 0.8, 0.35),
	3: Color(0.9, 0.28, 0.28),
}
@export var skin_color: SkinColor = SkinColor.BLUE
@export_category("Nickname")
@export_range(0.0, 1.0, 0.01) var nickname_clearance: float = 0.2
@export_category("Objects")
@export var _body: Node3D = null
@export var _spring_arm_offset: SpringArmCharacter = null
@export_category("Skin Colors")
@export var blue_texture: CompressedTexture2D
@export var yellow_texture: CompressedTexture2D
@export var green_texture: CompressedTexture2D
@export var red_texture: CompressedTexture2D
var player_inventory: PlayerInventory
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var can_double_jump = true
var has_double_jumped = false
var is_attacking := false
var is_collecting := false
var shift_locked := true
signal health_updated(health)
var health: int = 100
var _current_speed: float
var _spawn_point = Vector3(0, 5, 0)
var _animation_sequence := 0
var _last_applied_animation_sequence := 0
var _last_requested_animation: StringName = &""
var _appearance_sync_requesters: Dictionary = {}
var _server_animation_request_tokens := SERVER_ANIMATION_REQUEST_BURST
var _last_server_animation_token_update_msec := 0
var _server_pickup_animation_started_msec := -1
var _last_server_pickup_request_msec := -PICKUP_REQUEST_COOLDOWN_MSEC
var _pickup_area_camera_yaw_offset := 0.0
var _equipped_hat_visual_id := ""
var _SLOPPYSLIMYSHOWDOWN_scale := Vector3.ONE
var _SLOPPYSLIMYSHOWDOWN_base := Vector3.ONE
var _SLOPPYSLIMYSHOWDOWN_rest_pos := Vector3.ZERO
var _SLOPPYSLIMYSHOWDOWN_rock := 0.0
var _SLOPPYSLIMYSHOWDOWN_hop := 0.0
var _SLOPPYSLIMYSHOWDOWN_air_time := 0.0
var _SLOPPYSLIMYSHOWDOWN_squash_time := 0.0
var _squash_node: Node3D
var _rig_root: Node3D
var _rig_skeleton: Skeleton3D
var _rig_pairs: Array = []
var _rig_active := false
@onready var nickname: Label3D = $PlayerNick/Nickname
@onready var _bottom_mesh: MeshInstance3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D/Bottom")
@onready var _chest_mesh: MeshInstance3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D/Chest")
@onready var _face_mesh: MeshInstance3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D/Face")
@onready var _limbs_head_mesh: MeshInstance3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D/LimbsAndHead")
@onready var _skeleton: Skeleton3D = get_node("GodotRobot3D/RobotArmature/Skeleton3D")
@onready var _pickup_area: Area3D = $GodotRobot3D/InfrontArea3D
@onready var _first_person_hud: CanvasLayer = $FirstPersonHUD
func _enter_tree():
	if str(name) == "Player":
		set_multiplayer_authority(1)
		if has_node("SpringArmOffset/SpringArm3D/Camera3D"):
			$SpringArmOffset/SpringArm3D/Camera3D.current = true
		return
	if not multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(1)
		if has_node("SpringArmOffset/SpringArm3D/Camera3D"):
			$SpringArmOffset/SpringArm3D/Camera3D.current = true
		return
	set_multiplayer_authority(str(name).to_int())
	$SpringArmOffset/SpringArm3D/Camera3D.current = is_multiplayer_authority()
func damage(amount):
	var was_alive := health > 0
	health -= int(amount)
	health_updated.emit(health)
	_play_hit_sound()
	if health <= 0:
		health = 100
		health_updated.emit(health)
		if was_alive:
			_play_death_sound()
		global_position = _spawn_point
		velocity = Vector3.ZERO
func _play_hit_sound() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("play"):
		audio.play("sounds/enemy_hurt.ogg")
func _play_death_sound() -> void:
	var audio := get_node_or_null("/root/Audio")
	if audio and audio.has_method("play"):
		audio.play("sounds/enemy_destroy.ogg")
@rpc("any_peer", "call_local", "reliable")
func take_pvp_hit(amount: float, attacker_id: int) -> void:
	if attacker_id == get_multiplayer_authority():
		return
	if amount <= 0.0 or amount > 100.0:
		return
	damage(amount)
func _ready():
	add_to_group("player")
	_ensure_shift_lock_action()
	_setup_SLOPPYSLIMYSHOWDOWN_rig()
	if not multiplayer.has_multiplayer_peer():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
		call_deferred("_sync_equipment_appearance")
	elif multiplayer.is_server():
		player_inventory = PlayerInventory.new()
		_add_starting_items()
		call_deferred("_sync_equipment_appearance")
		if not is_multiplayer_authority():
			call_deferred("_sync_inventory_to_owner")
	set_player_skin(skin_color)
	var animation_player := get_node_or_null("GodotRobot3D/AnimationPlayer") as AnimationPlayer
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	_body.play_animation_state(&"Idle")
	_set_nickname_height(BASE_NICKNAME_HEIGHT)
	call_deferred("_update_nickname_height")
	if not multiplayer.is_server():
		call_deferred("_request_equipment_appearance")
	if _spring_arm_offset:
		_spring_arm_offset.is_first_person = true
	if _spring_arm_offset:
		_pickup_area_camera_yaw_offset = wrapf(
			_pickup_area.global_rotation.y - _spring_arm_offset.global_rotation.y, -PI, PI
		)
		if not _spring_arm_offset.perspective_changed.is_connected(_on_camera_perspective_changed):
			_spring_arm_offset.perspective_changed.connect(_on_camera_perspective_changed)
		_on_camera_perspective_changed(true)
		nickname.visible = false
func _is_local_main_player() -> bool:
	return str(name) == "Player" or not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()
func _on_camera_perspective_changed(first_person: bool) -> void:
	if _rig_root:
		_rig_root.visible = _rig_active and not (first_person and _is_local_main_player())
	if not _is_local_main_player():
		return
	_body.visible = true
	_bottom_mesh.visible = not first_person
	_chest_mesh.visible = not first_person
	_face_mesh.visible = not first_person
	_limbs_head_mesh.visible = true
	if _rig_active:
		_bottom_mesh.visible = false
		_chest_mesh.visible = false
		_face_mesh.visible = false
		_limbs_head_mesh.visible = false
	nickname.visible = not first_person
	_first_person_hud.visible = first_person
	for bone_name in FIRST_PERSON_HIDDEN_BONES:
		var bone_index := _skeleton.find_bone(bone_name)
		if bone_index >= 0:
			_skeleton.set_bone_pose_scale(bone_index, Vector3.ZERO if first_person else Vector3.ONE)
	if first_person:
		_align_pickup_area_with_camera()
	else:
		_pickup_area.rotation = Vector3.ZERO
		call_deferred("_refresh_nickname_height_after_perspective_change")
func _setup_SLOPPYSLIMYSHOWDOWN_rig() -> void:
	_rig_skeleton = _find_rig_skeleton()
	if _rig_skeleton == null:
		_rig_root = null
		return
	_rig_pairs.clear()
	for i in range(_skeleton.get_bone_count()):
		var bone_name := _skeleton.get_bone_name(i)
		var rig_idx := _rig_skeleton.find_bone(bone_name)
		if rig_idx >= 0:
			_rig_pairs.append([i, rig_idx])
	if _rig_pairs.size() < 20:
		_rig_skeleton = null
		_rig_pairs.clear()
		_rig_root = null
		return
	_rig_active = true
	_squash_node = _rig_root
	_SLOPPYSLIMYSHOWDOWN_base = _rig_root.scale
	_SLOPPYSLIMYSHOWDOWN_rest_pos = _rig_root.position
	_SLOPPYSLIMYSHOWDOWN_scale = _SLOPPYSLIMYSHOWDOWN_base
	if not _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_sync_baked_skeleton()
func _find_rig_skeleton() -> Skeleton3D:
	_rig_root = get_node_or_null("GodotRobot3D/RobotArmature/SLOPPYSLIMYSHOWDOWN") as Node3D
	if _rig_root == null or _skeleton == null:
		return null
	var found := _rig_root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D
func _sync_baked_skeleton() -> void:
	if not _rig_active or _rig_skeleton == null or _skeleton == null:
		return
	for pair in _rig_pairs:
		var live_idx: int = pair[0]
		var rig_idx: int = pair[1]
		var pose := _skeleton.get_bone_global_pose(live_idx)
		if pose.basis.x.length() < 0.0001 or pose.basis.y.length() < 0.0001 or pose.basis.z.length() < 0.0001:
			continue
		_rig_skeleton.set_bone_global_pose(rig_idx, pose)
func _on_skeleton_updated() -> void:
	_sync_baked_skeleton()
func _update_SLOPPYSLIMYSHOWDOWN_squash() -> void:
	if _squash_node == null:
		return
	_SLOPPYSLIMYSHOWDOWN_squash_time = maxf(0.0, _SLOPPYSLIMYSHOWDOWN_squash_time - get_process_delta_time())
	var state: StringName = _body._current_state if _body else &"Idle"
	var time_seconds := Time.get_ticks_msec() / 1000.0
	var squash := Vector3.ONE
	var rock := 0.0
	var hop := 0.0
	if state == &"Jump" or state == &"Jump2":
		squash = Vector3(0.9, 1.15, 0.9)
	elif state == &"Fall":
		squash = Vector3(0.95, 1.08, 0.95)
	elif state == &"Run":
		var bounce := absf(sin(time_seconds * 9.0))
		squash = Vector3(1.0 + 0.07 * bounce, 1.0 - 0.08 * bounce, 1.0 + 0.07 * bounce)
		rock = sin(time_seconds * 9.0) * 0.09
		hop = bounce * 0.07
	elif state == &"Sprint":
		var sprint_bounce := absf(sin(time_seconds * 12.0))
		squash = Vector3(1.0 + 0.09 * sprint_bounce, 1.0 - 0.1 * sprint_bounce, 1.0 + 0.09 * sprint_bounce)
		rock = sin(time_seconds * 12.0) * 0.12
		hop = sprint_bounce * 0.1
	elif state == &"Emote2":
		squash = Vector3(1.1, 0.85, 1.1)
	else:
		var breath := sin(time_seconds * 2.0)
		squash = Vector3(1.0 - 0.012 * breath, 1.0 + 0.02 * breath, 1.0 - 0.012 * breath)
	if _SLOPPYSLIMYSHOWDOWN_squash_time > 0.0:
		squash = Vector3(1.18, 0.75, 1.18)
		rock = 0.0
		hop = 0.0
	var target := Vector3(
		_SLOPPYSLIMYSHOWDOWN_base.x * squash.x, _SLOPPYSLIMYSHOWDOWN_base.y * squash.y, _SLOPPYSLIMYSHOWDOWN_base.z * squash.z
	)
	var blend := clampf(get_process_delta_time() * 10.0, 0.0, 1.0)
	_SLOPPYSLIMYSHOWDOWN_scale = _SLOPPYSLIMYSHOWDOWN_scale.lerp(target, blend)
	_squash_node.scale = _SLOPPYSLIMYSHOWDOWN_scale
	_SLOPPYSLIMYSHOWDOWN_rock = lerpf(_SLOPPYSLIMYSHOWDOWN_rock, rock, blend)
	_SLOPPYSLIMYSHOWDOWN_hop = lerpf(_SLOPPYSLIMYSHOWDOWN_hop, hop, blend)
	_squash_node.rotation = Vector3(0.0, 0.0, _SLOPPYSLIMYSHOWDOWN_rock)
	_squash_node.position = Vector3(
		_SLOPPYSLIMYSHOWDOWN_rest_pos.x * (_SLOPPYSLIMYSHOWDOWN_scale.x / _SLOPPYSLIMYSHOWDOWN_base.x),
		_SLOPPYSLIMYSHOWDOWN_rest_pos.y * (_SLOPPYSLIMYSHOWDOWN_scale.y / _SLOPPYSLIMYSHOWDOWN_base.y) + _SLOPPYSLIMYSHOWDOWN_hop,
		_SLOPPYSLIMYSHOWDOWN_rest_pos.z * (_SLOPPYSLIMYSHOWDOWN_scale.z / _SLOPPYSLIMYSHOWDOWN_base.z)
	)
func _refresh_nickname_height_after_perspective_change() -> void:
	if not is_multiplayer_authority() or _is_local_first_person():
		return
	var height := _calculate_nickname_height(_equipped_hat_visual_id)
	_set_nickname_height(height)
	nickname.visible = true
	if multiplayer.is_server():
		_broadcast_nickname_height(height)
func _align_pickup_area_with_camera() -> void:
	var pickup_rotation := _pickup_area.global_rotation
	pickup_rotation.y = wrapf(_spring_arm_offset.global_rotation.y + _pickup_area_camera_yaw_offset, -PI, PI)
	_pickup_area.global_rotation = pickup_rotation
func _physics_process(delta):
	if str(name) == "Player":
		pass
	elif multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if not multiplayer.has_multiplayer_peer() and not is_inside_tree():
		return
	if is_on_floor():
		if _SLOPPYSLIMYSHOWDOWN_air_time > 0.25:
			_SLOPPYSLIMYSHOWDOWN_squash_time = 0.22
		_SLOPPYSLIMYSHOWDOWN_air_time = 0.0
	else:
		_SLOPPYSLIMYSHOWDOWN_air_time += delta
	var current_scene = get_tree().get_current_scene()
	var should_freeze = false
	if current_scene:
		if current_scene.has_method("is_gameplay_input_blocked") and current_scene.is_gameplay_input_blocked():
			should_freeze = true
		elif current_scene.has_method("is_chat_visible") and current_scene.is_chat_visible():
			should_freeze = true
		elif current_scene.has_method("is_inventory_visible") and current_scene.is_inventory_visible():
			should_freeze = true
	if Input.is_action_just_pressed("shift_lock"):
		shift_locked = not shift_locked
	if is_collecting:
		velocity.x = 0
		velocity.z = 0
		_apply_gravity(delta)
		move_and_slide()
		_separate_from_players()
		return
	if should_freeze:
		_freeze()
		_apply_gravity(delta)
		move_and_slide()
		_separate_from_players()
		_request_animation(_get_body_animation())
		return
	if Input.is_action_just_pressed("pickup") and is_on_floor() and _has_collectible_item_in_front():
		is_collecting = true
		_request_animation(&"Emote2", true)
		return
	if Input.is_action_just_pressed("attack"):
		_start_attack()
		return
	if is_on_floor():
		can_double_jump = true
		has_double_jumped = false
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			can_double_jump = true
			_request_animation(&"Jump", true)
	else:
		_apply_gravity(delta)
		if can_double_jump and not has_double_jumped and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
			has_double_jumped = true
			can_double_jump = false
			_request_animation(&"Jump2", true)
	_move()
	var collided = move_and_slide()
	if collided:
		_push_collided_items()
	_separate_from_players()
	_request_animation(_get_body_animation())
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var gravity_multiplier = FALL_GRAVITY_MULTIPLIER if velocity.y < 0 else 1.0
	velocity.y -= gravity * gravity_multiplier * delta
func _equipped_weapon_id() -> String:
	if player_inventory:
		return player_inventory.get_held_weapon_id()
	return ""
func _get_body_animation() -> StringName:
	var anim: StringName = _body.get_movement_animation(velocity)
	return anim
func _start_attack() -> void:
	if is_attacking or is_collecting:
		return
	if _equipped_weapon_id() == WATER_WEAPON_ID:
		_shoot_water_gun()
		_kick_held_weapon()
	else:
		is_attacking = true
		_swing_held_weapon()
		await get_tree().create_timer(0.12).timeout
		_perform_melee_attack()
		await get_tree().create_timer(0.13).timeout
		is_attacking = false
func _on_animation_finished(animation_name: StringName) -> void:
	match animation_name:
		&"Attack1":
			if _equipped_weapon_id() != WATER_WEAPON_ID:
				_perform_melee_attack()
			is_attacking = false
		&"Emote2":
			is_collecting = false
func _perform_melee_attack() -> void:
	var origin := global_position + Vector3(0, 1.0, 0)
	for node in get_tree().get_nodes_in_group("enemy"):
		if not (node is Node3D):
			continue
		var target := (node as Node3D).global_position
		if origin.distance_to(target) > MELEE_RANGE:
			continue
		if node.has_method("damage"):
			node.damage(MELEE_DAMAGE)
		_play_melee_hit(node as Node3D)
	var my_id := multiplayer.get_unique_id()
	for node in get_tree().get_nodes_in_group("player"):
		if node == self:
			continue
		if not (node is Node3D):
			continue
		if not node.has_method("take_pvp_hit"):
			continue
		var target := (node as Node3D).global_position
		if origin.distance_to(target) > MELEE_RANGE:
			continue
		node.take_pvp_hit.rpc(MELEE_DAMAGE, my_id)
		_play_melee_hit(node as Node3D)
func _play_melee_hit(target: Node3D) -> void:
	var impact := MELEE_IMPACT_SCENE.instantiate() as Node3D
	var world := get_tree().current_scene
	if world:
		world.add_child(impact)
	else:
		get_tree().root.add_child(impact)
	impact.global_position = target.global_position + Vector3(0, 0.5, 0)
	if impact.has_method("play"):
		impact.play("shot")
	var base_scale := target.scale
	var punch := create_tween()
	punch.tween_property(target, "scale", base_scale * 1.18, 0.07)
	punch.tween_property(target, "scale", base_scale, 0.12)
	var push := target.global_position - global_position
	push.y = 0.0
	if push.length() < 0.001:
		push = -global_transform.basis.z
		push.y = 0.0
	push = push.normalized() * MELEE_KNOCKBACK
	var current_target = target.get("target_position")
	if current_target is Vector3:
		target.set("target_position", current_target + push)
func _shoot_water_gun() -> void:
	var cam := get_node_or_null("SpringArmOffset/SpringArm3D/Camera3D") as Camera3D
	if cam == null:
		return
	var dir := -cam.global_transform.basis.z.normalized()
	var muzzle := _get_water_gun_muzzle(dir)
	var shot_dir := _aim_at_crosshair(cam, dir, muzzle)
	_spawn_droplet(muzzle, shot_dir)
func _aim_at_crosshair(cam: Camera3D, dir: Vector3, muzzle: Vector3) -> Vector3:
	var aim_point := cam.global_position + dir * 60.0
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, aim_point)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		aim_point = hit["position"]
	var to_aim := aim_point - muzzle
	if to_aim.length() > 0.05:
		return to_aim.normalized()
	return dir
func _spawn_droplet(muzzle: Vector3, shot_dir: Vector3) -> void:
	var droplet = DROPLET_SCENE.instantiate()
	if droplet.has_method("setup"):
		droplet.setup(shot_dir, WATER_SPEED, WATER_DAMAGE, multiplayer.get_unique_id())
	else:
		droplet.set("velocity", shot_dir * WATER_SPEED)
	var world = get_tree().current_scene
	if world:
		world.add_child(droplet)
	else:
		get_tree().root.add_child(droplet)
	droplet.global_position = muzzle
	droplet.look_at(droplet.global_position + shot_dir, Vector3.UP)
	var audio = get_node_or_null("/root/Audio")
	if audio and audio.has_method("play"):
		audio.play("sounds/blaster.ogg")
func _get_water_gun_muzzle(dir: Vector3) -> Vector3:
	var cam := get_node_or_null("SpringArmOffset/SpringArm3D/Camera3D") as Camera3D
	var fallback := global_position + Vector3(0, 1.4, 0) + dir * 0.8
	if cam:
		fallback = cam.global_position + dir * 0.8 + Vector3(0, -0.1, 0)
	var gun := get_node_or_null(HAND_EQUIPMENT_PATH + "WaterGun") as Node3D
	if gun == null or not gun.visible:
		return fallback
	var meshes := gun.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return gun.global_position + dir * 0.4
	var first := meshes[0] as MeshInstance3D
	var bounds: AABB = first.global_transform * first.get_aabb()
	for i in range(1, meshes.size()):
		var mi := meshes[i] as MeshInstance3D
		bounds = bounds.merge(mi.global_transform * mi.get_aabb())
	return bounds.get_center() + dir * (bounds.size.length() * 0.25 + 0.05)
func _kick_held_weapon() -> void:
	var weapon_id := _equipped_weapon_id()
	var node_name := str(WEAPON_NODES_BY_ITEM.get(weapon_id, "WaterGun"))
	var weapon := get_node_or_null(HAND_EQUIPMENT_PATH + node_name) as Node3D
	if weapon == null:
		return
	var rest_position := weapon.position
	var kick := create_tween()
	kick.tween_property(weapon, "position", rest_position + Vector3(0, -0.03, 0.08), 0.05)
	kick.tween_property(weapon, "position", rest_position, 0.1)
func _swing_held_weapon() -> void:
	var weapon_id := _equipped_weapon_id()
	var node_name := str(WEAPON_NODES_BY_ITEM.get(weapon_id, "WaterGun"))
	var weapon := get_node_or_null(HAND_EQUIPMENT_PATH + node_name) as Node3D
	if weapon == null:
		return
	var rest_rotation := weapon.rotation
	var swing := create_tween()
	swing.tween_property(weapon, "rotation", rest_rotation + Vector3(-0.9, 0.0, 0.4), 0.1)
	swing.tween_property(weapon, "rotation", rest_rotation, 0.15)
func _request_animation(state: StringName, restart: bool = false) -> void:
	if not ALLOWED_ANIMATION_STATES.has(state):
		return
	if state != &"Emote2" and is_collecting:
		is_collecting = false
	if not restart and _last_requested_animation == state:
		return
	_last_requested_animation = state
	_body.play_animation_state(state, restart)
	if multiplayer.is_server():
		request_animation_state(state)
	else:
		request_animation_state.rpc_id(1, state)
@rpc("any_peer", "call_local", "reliable")
func request_animation_state(state: StringName) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not ALLOWED_ANIMATION_STATES.has(state):
		return
	if not _server_consume_animation_request_token():
		return
	if state == &"Emote2":
		if not _is_grounded_on_server() or not _has_collectible_item_in_front():
			return
		_server_pickup_animation_started_msec = Time.get_ticks_msec()
	else:
		_server_pickup_animation_started_msec = -1
	_server_publish_animation(state)
func _server_consume_animation_request_token() -> bool:
	var now := Time.get_ticks_msec()
	if _last_server_animation_token_update_msec == 0:
		_last_server_animation_token_update_msec = now
	else:
		var elapsed_seconds := (now - _last_server_animation_token_update_msec) / 1000.0
		_server_animation_request_tokens = minf(
			SERVER_ANIMATION_REQUEST_BURST,
			_server_animation_request_tokens + elapsed_seconds * SERVER_ANIMATION_REQUESTS_PER_SECOND
		)
		_last_server_animation_token_update_msec = now
	if _server_animation_request_tokens < 1.0:
		return false
	_server_animation_request_tokens -= 1.0
	return true
func _server_publish_animation(state: StringName) -> void:
	if not multiplayer.is_server():
		return
	_animation_sequence += 1
	sync_animation_state.rpc(state, _animation_sequence)
	sync_animation_state(state, _animation_sequence)
@rpc("any_peer", "call_local", "reliable")
func sync_animation_state(state: StringName, sequence: int) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	if sequence <= _last_applied_animation_sequence:
		return
	_last_applied_animation_sequence = sequence
	if not ALLOWED_ANIMATION_STATES.has(state):
		return
	if is_multiplayer_authority():
		return
	_body.play_animation_state(state, true)
	_update_SLOPPYSLIMYSHOWDOWN_squash()
func _push_collided_items() -> void:
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			apply_force_to_server_object.rpc_id(1, c.get_collider().name, -c.get_normal())
func _separate_from_players() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if node == self:
			continue
		if node is Node3D:
			_push_away_from(node)
func _push_away_from(other: Node3D) -> void:
	var delta := global_position - other.global_position
	if absf(delta.y) > PLAYER_SEPARATION_HEIGHT:
		return
	delta.y = 0.0
	var distance := delta.length()
	if distance >= PLAYER_SEPARATION_DISTANCE:
		return
	if distance < 0.001:
		delta = Vector3.RIGHT
		distance = 0.001
	global_position += (delta / distance) * (PLAYER_SEPARATION_DISTANCE - distance)
func _process(_delta):
	if str(name) == "Player":
		pass
	elif multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	elif not multiplayer.has_multiplayer_peer():
		pass
	elif not is_multiplayer_authority():
		return
	var first_person := _spring_arm_offset != null and _spring_arm_offset.is_first_person
	if first_person:
		_align_pickup_area_with_camera()
	var camera_input_blocked := false
	var current_scene := get_tree().get_current_scene()
	if current_scene and current_scene.has_method("is_camera_input_blocked"):
		camera_input_blocked = current_scene.is_camera_input_blocked()
	_first_person_hud.visible = (
		first_person and not camera_input_blocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	)
	_check_out_of_bounds()
	_update_SLOPPYSLIMYSHOWDOWN_squash()
	_apply_aim_zoom(_delta)


func _apply_aim_zoom(delta: float) -> void:
	var cam := get_node_or_null("SpringArmOffset/SpringArm3D/Camera3D") as Camera3D
	if cam == null or _spring_arm_offset == null:
		return
	var blocked := false
	var current_scene := get_tree().get_current_scene()
	if current_scene and current_scene.has_method("is_camera_input_blocked"):
		blocked = current_scene.is_camera_input_blocked()
	var want_zoom := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not blocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var target_fov := 55.0 if want_zoom else (90.0 if _spring_arm_offset.is_first_person else 75.0)
	cam.fov = lerpf(cam.fov, target_fov, clampf(delta * 10.0, 0.0, 1.0))
func _freeze():
	velocity.x = 0
	velocity.z = 0
	_current_speed = 0
	_request_animation(&"Idle")
func _move() -> void:
	var input_direction: Vector2 = Vector2.ZERO
	if str(name) == "Player" or is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3
	var cam := get_node_or_null("SpringArmOffset/SpringArm3D/Camera3D") as Camera3D
	if cam:
		direction = cam.global_transform.basis * Vector3(input_direction.x, 0, input_direction.y)
		direction.y = 0.0
		if direction.length() > 0.001:
			direction = direction.normalized()
		else:
			direction = Vector3.ZERO
	else:
		direction = Vector3(input_direction.x, 0, input_direction.y)
		if _spring_arm_offset:
			direction = direction.rotated(Vector3.UP, _spring_arm_offset.global_rotation.y)
		if direction.length() > 0.001:
			direction = direction.normalized()
	_is_running()
	if direction:
		velocity.x = direction.x * _current_speed
		velocity.z = direction.z * _current_speed
		if shift_locked:
			_face_camera()
		else:
			_body.apply_rotation(velocity)
		return
	velocity.x = move_toward(velocity.x, 0, _current_speed)
	velocity.z = move_toward(velocity.z, 0, _current_speed)
	if shift_locked:
		_face_camera()
func _is_running() -> bool:
	if Input.is_action_pressed("shift"):
		_current_speed = SPRINT_SPEED
		return true
	_current_speed = NORMAL_SPEED
	return false
func _face_camera() -> void:
	var cam := get_node_or_null("SpringArmOffset/SpringArm3D/Camera3D") as Camera3D
	if cam == null:
		return
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return
	forward = forward.normalized()
	var target_yaw := atan2(forward.x, forward.z)
	_body.global_rotation.y = lerp_angle(_body.global_rotation.y, target_yaw, 0.5)
func _ensure_shift_lock_action() -> void:
	if InputMap.has_action("shift_lock"):
		return
	InputMap.add_action("shift_lock")
	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_X
	InputMap.action_add_event("shift_lock", key_event)
func _check_out_of_bounds():
	if global_transform.origin.y < -15.0:
		_reset_position_after_fall()
func _reset_position_after_fall():
	global_transform.origin = _spawn_point
	velocity = Vector3.ZERO
func _get_texture_from_name(color: SkinColor) -> CompressedTexture2D:
	match color:
		SkinColor.BLUE:
			return blue_texture
		SkinColor.GREEN:
			return green_texture
		SkinColor.RED:
			return red_texture
		SkinColor.YELLOW:
			return yellow_texture
		_:
			return blue_texture
func set_player_skin(skin_name: SkinColor) -> void:
	var texture = _get_texture_from_name(skin_name)
	_set_mesh_texture(_bottom_mesh, texture)
	_set_mesh_texture(_chest_mesh, texture)
	_set_mesh_texture(_face_mesh, texture)
	_set_mesh_texture(_limbs_head_mesh, texture)
	_tint_sloppy_rig(_get_skin_tint(skin_name))
func _set_mesh_texture(mesh_instance: MeshInstance3D, texture: CompressedTexture2D) -> void:
	if mesh_instance:
		var new_material := StandardMaterial3D.new()
		new_material.albedo_texture = texture
		mesh_instance.set_surface_override_material(0, new_material)
func _get_skin_tint(skin_name: SkinColor) -> Color:
	return SKIN_TINTS.get(int(skin_name), Color(0.25, 0.5, 0.95))
func _tint_sloppy_rig(color: Color) -> void:
	var root := _rig_root
	if root == null:
		root = get_node_or_null("GodotRobot3D/RobotArmature/SLOPPYSLIMYSHOWDOWN") as Node3D
	if root == null:
		return
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mat := StandardMaterial3D.new()
		var old_tex: Texture2D = null
		var active := mi.get_active_material(0)
		if active is StandardMaterial3D and (active as StandardMaterial3D).albedo_texture:
			old_tex = (active as StandardMaterial3D).albedo_texture
		if old_tex:
			mat.albedo_texture = old_tex
		mat.albedo_color = color
		mat.roughness = 0.55
		mi.set_surface_override_material(0, mat)
@rpc("any_peer", "call_local", "reliable")
func sync_inventory_to_owner(inventory_data: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return
	if not is_multiplayer_authority():
		return
	if not player_inventory:
		player_inventory = PlayerInventory.new()
	player_inventory.from_dict(inventory_data)
	var level_scene = get_tree().get_current_scene()
	if (
		level_scene
		and get_multiplayer_authority() == multiplayer.get_unique_id()
		and level_scene.has_method("update_local_inventory_display")
	):
		level_scene.update_local_inventory_display()
@rpc("any_peer", "call_local", "reliable")
func request_move_item(from_slot: int, to_slot: int, quantity: int = -1):
	if not multiplayer.is_server():
		return
	var requesting_client = multiplayer.get_remote_sender_id()
	if not _is_owner_request():
		push_warning(
			(
				"Client "
				+ str(requesting_client)
				+ " tried to modify inventory for player "
				+ str(get_multiplayer_authority())
			)
		)
		return
	if not player_inventory:
		return
	if not player_inventory.is_slot_active(from_slot) or not player_inventory.is_slot_active(to_slot):
		push_warning("Invalid slot indices: from=" + str(from_slot) + " to=" + str(to_slot))
		return
	if quantity != -1 and quantity <= 0:
		push_warning("Invalid move quantity: " + str(quantity))
		return
	var success = false
	if quantity == -1:
		success = player_inventory.move_item(from_slot, to_slot)
		if not success:
			success = player_inventory.swap_items(from_slot, to_slot)
	else:
		success = player_inventory.move_item(from_slot, to_slot, quantity)
	if success:
		_sync_inventory_to_owner()
@rpc("any_peer", "call_local", "reliable")
func request_add_item(item_id: String, quantity: int = 1):
	if not multiplayer.is_server():
		return
	var requesting_client = multiplayer.get_remote_sender_id()
	var is_local_server_call = requesting_client == 0 and multiplayer.get_unique_id() == 1
	if requesting_client != 1 and not is_local_server_call:
		push_warning(
			"Client " + str(requesting_client) + " tried to add items to player " + str(get_multiplayer_authority())
		)
		return
	if not player_inventory:
		return
	if quantity <= 0:
		push_warning("Invalid quantity: " + str(quantity))
		return
	var item = ItemDatabase.get_item(item_id)
	if not item:
		push_warning("Item not found: " + item_id)
		return
	var remaining = player_inventory.add_item(item, quantity)
	var added = quantity - remaining
	if added > 0:
		_sync_inventory_to_owner()
func request_add_single_item(item_id: String) -> bool:
	if not multiplayer.is_server():
		return false
	if player_inventory == null:
		return false
	var item = ItemDatabase.get_item(item_id)
	if not item:
		push_warning("Item not found: " + item_id)
		return false
	var remaining = player_inventory.add_item(item, 1)
	if remaining == 0:
		_sync_inventory_to_owner()
		return true
	return false
@rpc("any_peer", "call_local", "reliable")
func request_remove_item(item_id: String, quantity: int = 1):
	if not multiplayer.is_server():
		return
	var requesting_client = multiplayer.get_remote_sender_id()
	if not _is_owner_request():
		push_warning(
			(
				"Client "
				+ str(requesting_client)
				+ " tried to remove items from player "
				+ str(get_multiplayer_authority())
			)
		)
		return
	if not player_inventory:
		return
	if quantity <= 0:
		push_warning("Invalid quantity: " + str(quantity))
		return
	var removed = player_inventory.remove_item(item_id, quantity)
	if removed > 0:
		_sync_inventory_to_owner()
@rpc("authority", "call_local", "reliable")
func add_world_item(scene_path: String, player_position: Vector3) -> void:
	var item_container = get_node_or_null("/root/Level/Environment/ItemContainer")
	if not item_container:
		push_warning("ItemContainer not found at /root/Level/Environment/ItemContainer")
		return
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_warning("Cannot add world item: invalid scene path '" + scene_path + "'")
		return
	var packed_scene = load(scene_path) as PackedScene
	if not packed_scene:
		push_warning("Cannot add world item: scene path is not a PackedScene '" + scene_path + "'")
		return
	var instance_item := packed_scene.instantiate() as Node3D
	if not instance_item:
		push_warning("Cannot add world item: scene root is not a Node3D '" + scene_path + "'")
		return
	item_container.add_child(instance_item, true)
	instance_item.global_position = player_position
func get_inventory() -> PlayerInventory:
	return player_inventory
func _sync_inventory_to_owner() -> void:
	if not multiplayer.is_server() or not player_inventory:
		return
	var owner_id = get_multiplayer_authority()
	if owner_id == 1:
		sync_inventory_to_owner(player_inventory.to_dict())
	else:
		sync_inventory_to_owner.rpc_id(owner_id, player_inventory.to_dict())
@rpc("any_peer", "call_local", "reliable")
func request_equip_item(from_slot: int, item_type: Item.ItemType) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not player_inventory or not player_inventory.is_slot_active(from_slot):
		return
	if item_type != Item.ItemType.WEAPON and item_type != Item.ItemType.HAT and item_type != Item.ItemType.BACKPACK:
		return
	if item_type == Item.ItemType.WEAPON:
		var wield_slot := player_inventory.get_slot(from_slot)
		if wield_slot == null or wield_slot.is_empty():
			return
		var wield_item := ItemDatabase.get_item(wield_slot.item_id)
		if wield_item == null or wield_item.item_type != Item.ItemType.WEAPON:
			return
		player_inventory.wielded_weapon_slot = from_slot
		_sync_inventory_to_owner()
		_sync_equipment_appearance()
		return
	if player_inventory.equip_from_slot(from_slot, item_type):
		_sync_inventory_to_owner()
		_sync_equipment_appearance()
@rpc("any_peer", "call_local", "reliable")
func request_unequip_item(item_type: Item.ItemType, destination_slot: int = -1) -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	if not player_inventory:
		return
	if item_type != Item.ItemType.WEAPON and item_type != Item.ItemType.HAT and item_type != Item.ItemType.BACKPACK:
		return
	if item_type == Item.ItemType.WEAPON:
		player_inventory.wielded_weapon_slot = -1
		_sync_inventory_to_owner()
		_sync_equipment_appearance()
		return
	if destination_slot < -1 or destination_slot >= PlayerInventory.MAX_INVENTORY_SIZE:
		return
	if destination_slot >= 0 and not player_inventory.is_slot_active(destination_slot):
		return
	if player_inventory.unequip_to_slot(item_type, destination_slot):
		_sync_inventory_to_owner()
		_sync_equipment_appearance()
func _is_owner_request() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == get_multiplayer_authority() or (sender == 0 and multiplayer.is_server())
func _sync_equipment_appearance() -> void:
	if not player_inventory:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var weapon_id := player_inventory.get_held_weapon_id()
	if weapon_id.is_empty():
		weapon_id = WATER_WEAPON_ID
	var hat_id := player_inventory.equipped_hat.item_id
	var backpack_id := player_inventory.equipped_backpack.item_id
	var nickname_height := _calculate_nickname_height(hat_id)
	_broadcast_nickname_height(nickname_height)
	if multiplayer.has_multiplayer_peer():
		sync_equipment_appearance.rpc(weapon_id, hat_id, backpack_id)
	sync_equipment_appearance(weapon_id, hat_id, backpack_id)
func _request_equipment_appearance() -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	request_equipment_appearance.rpc_id(1)
@rpc("any_peer", "reliable")
func request_equipment_appearance() -> void:
	if not multiplayer.is_server() or not player_inventory:
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if requester_id <= 0:
		return
	if _appearance_sync_requesters.has(requester_id):
		return
	_appearance_sync_requesters[requester_id] = true
	_sync_equipment_appearance_to_peer(requester_id)
func _sync_equipment_appearance_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not player_inventory or peer_id <= 0:
		return
	var weapon_id := player_inventory.get_held_weapon_id()
	var hat_id := player_inventory.equipped_hat.item_id
	var backpack_id := player_inventory.equipped_backpack.item_id
	sync_equipment_appearance.rpc_id(peer_id, weapon_id, hat_id, backpack_id)
@rpc("any_peer", "reliable")
func sync_equipment_appearance(weapon_id: String, hat_id: String, backpack_id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1 and not (sender == 0 and multiplayer.is_server()):
		return
	_set_equipment_visibility(weapon_id, hat_id, backpack_id)
func _set_equipment_visibility(weapon_id: String, hat_id: String, backpack_id: String) -> void:
	_equipped_hat_visual_id = hat_id
	if weapon_id.is_empty():
		weapon_id = WATER_WEAPON_ID
	_set_equipment_nodes_visibility(HEAD_EQUIPMENT_PATH, HAT_NODES_BY_ITEM, hat_id)
	_set_equipment_nodes_visibility(HAND_EQUIPMENT_PATH, WEAPON_NODES_BY_ITEM, weapon_id)
	_set_equipment_nodes_visibility(BACK_EQUIPMENT_PATH, BACKPACK_NODES_BY_ITEM, backpack_id)
	if weapon_id == WATER_WEAPON_ID:
		var water_gun := get_node_or_null(HAND_EQUIPMENT_PATH + "WaterGun") as Node3D
		if water_gun:
			water_gun.visible = true
	_apply_hold_gun_pose(weapon_id == WATER_WEAPON_ID)
func _apply_hold_gun_pose(enabled: bool) -> void:
	if _skeleton == null:
		return
	if not enabled:
		_skeleton.clear_bones_global_pose_override()
		return
	for bone_name in HOLD_GUN_ARM_POSES:
		var bone_idx := _skeleton.find_bone(bone_name)
		if bone_idx < 0:
			continue
		_skeleton.set_bone_global_pose_override(bone_idx, _hold_gun_target(bone_idx), 1.0, true)
func _hold_gun_target(bone_idx: int) -> Transform3D:
	var bone_name := _skeleton.get_bone_name(bone_idx)
	var parent_global := Transform3D.IDENTITY
	var parent_idx := _skeleton.get_bone_parent(bone_idx)
	if parent_idx >= 0:
		parent_global = _skeleton.get_bone_global_rest(parent_idx)
	var rest_local: Transform3D = _skeleton.get_bone_rest(bone_idx)
	var hold_quat: Quaternion = HOLD_GUN_ARM_POSES[bone_name]
	var target_basis := Basis(hold_quat).scaled(rest_local.basis.get_scale())
	return parent_global * Transform3D(target_basis, rest_local.origin)
func _broadcast_nickname_height(height: float) -> void:
	if not multiplayer.is_server():
		return
	var level_scene := get_tree().get_current_scene()
	if level_scene and level_scene.has_method("register_player_nickname_height"):
		level_scene.register_player_nickname_height(get_multiplayer_authority(), height)
func _set_equipment_nodes_visibility(parent_path: String, nodes_by_item: Dictionary, equipped_item_id: String) -> void:
	for item_id in nodes_by_item:
		var equipment := get_node_or_null(parent_path + str(nodes_by_item[item_id])) as Node3D
		if equipment:
			equipment.visible = item_id == equipped_item_id
func _update_nickname_height(hat_id: String = "") -> void:
	if not nickname:
		return
	nickname.visible = not _is_local_first_person()
	_set_nickname_height(_calculate_nickname_height(hat_id))
func _calculate_nickname_height(hat_id: String) -> float:
	var target_height := BASE_NICKNAME_HEIGHT
	var equipped_hat := _get_hat_node(hat_id)
	if equipped_hat:
		var hat_top := _get_visual_top(equipped_hat)
		if hat_top > -INF and hat_top < INF:
			target_height = max(BASE_NICKNAME_HEIGHT, hat_top + nickname_clearance)
	return target_height
func _set_nickname_height(height: float) -> void:
	var nickname_position := nickname.position
	nickname_position.y = height
	nickname.position = nickname_position
func apply_synced_nickname_height(height: float) -> void:
	if not nickname:
		return
	nickname.visible = not _is_local_first_person()
	if height > -INF and height < INF:
		_set_nickname_height(maxf(BASE_NICKNAME_HEIGHT, height))
	else:
		_set_nickname_height(BASE_NICKNAME_HEIGHT)
func _is_local_first_person() -> bool:
	return is_multiplayer_authority() and _spring_arm_offset != null and _spring_arm_offset.is_first_person
func get_current_nickname_height() -> float:
	return nickname.position.y if nickname else BASE_NICKNAME_HEIGHT
func _get_hat_node(hat_id: String) -> Node3D:
	if HAT_NODES_BY_ITEM.has(hat_id):
		var requested_hat_path := HEAD_EQUIPMENT_PATH + str(HAT_NODES_BY_ITEM[hat_id])
		var requested_hat := get_node_or_null(requested_hat_path) as Node3D
		if requested_hat:
			return requested_hat
	return null
func _get_visual_top(root: Node3D) -> float:
	var visual_top := -INF
	if root is MeshInstance3D:
		visual_top = _get_mesh_top(root as MeshInstance3D)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance:
			visual_top = max(visual_top, _get_mesh_top(mesh_instance))
	return visual_top
func _get_mesh_top(mesh_instance: MeshInstance3D) -> float:
	var visual_top := -INF
	var mesh_bounds := mesh_instance.get_aabb()
	for endpoint_index in range(8):
		var endpoint_global := mesh_instance.to_global(mesh_bounds.get_endpoint(endpoint_index))
		visual_top = max(visual_top, to_local(endpoint_global).y)
	return visual_top
func _add_starting_items():
	if not player_inventory:
		return
	var backpack := ItemDatabase.get_item("backpack")
	if backpack:
		player_inventory.add_item(backpack, 1)
	var starting_item_ids: Array[String] = [
		"fedora",
		"headphones",
		"pirate_hat",
		"sheriff_hat",
		"sombrero",
		"wizard_hat",
		"water_gun",
		"chicken_leg",
		"bone",
		"chalice"
	]
	for item_id in starting_item_ids:
		var item = ItemDatabase.get_item(item_id)
		if item:
			player_inventory.add_item(item, 1)
	for i in player_inventory.slots.size():
		var slot = player_inventory.slots[i]
		if slot and slot.item_id == WATER_WEAPON_ID:
			player_inventory.wielded_weapon_slot = i
			break
	_sync_equipment_appearance()
func pickup() -> void:
	if multiplayer.is_server():
		request_pickup()
	else:
		request_pickup.rpc_id(1)
@rpc("any_peer", "call_local", "reliable")
func request_pickup() -> void:
	if not multiplayer.is_server() or not _is_owner_request():
		return
	var now := Time.get_ticks_msec()
	if now - _last_server_pickup_request_msec < PICKUP_REQUEST_COOLDOWN_MSEC:
		return
	_last_server_pickup_request_msec = now
	var animation_elapsed := now - _server_pickup_animation_started_msec
	if (
		_server_pickup_animation_started_msec < 0
		or animation_elapsed < PICKUP_ANIMATION_DELAY_MSEC
		or animation_elapsed > PICKUP_ANIMATION_WINDOW_MSEC
	):
		return
	if not _is_grounded_on_server():
		return
	if not _has_collectible_item_in_front():
		return
	_server_pickup_animation_started_msec = -1
	_server_pickup()
func _server_pickup() -> void:
	for item in _get_collectible_items_in_front():
		var result := request_add_single_item(item.item_id)
		if result and item.is_inside_tree():
			item.queue_free()
func _has_collectible_item_in_front() -> bool:
	return not _get_collectible_items_in_front().is_empty()
func _get_collectible_items_in_front() -> Array[ItemRigidBody3D]:
	var collectible_items: Array[ItemRigidBody3D] = []
	var pickup_area := get_node_or_null("GodotRobot3D/InfrontArea3D") as Area3D
	if not pickup_area:
		return collectible_items
	for body in pickup_area.get_overlapping_bodies():
		var item := body as ItemRigidBody3D
		if item and not item.item_id.is_empty() and ItemDatabase.get_item(item.item_id):
			collectible_items.append(item)
	return collectible_items
@rpc("any_peer", "call_local", "reliable")
func apply_force_to_server_object(object_name: String, normal: Vector3) -> void:
	var object_node = get_node_or_null("/root/Level/Environment/ItemContainer")
	if object_node:
		for n in object_node.get_children():
			if n.name == object_name and n is RigidBody3D:
				n.apply_force(normal * 100)
func _is_grounded_on_server() -> bool:
	if not multiplayer.is_server() or not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.new()
	query.from = global_position + Vector3.UP * 0.15
	query.to = global_position + Vector3.DOWN * 0.3
	query.collision_mask = 2
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

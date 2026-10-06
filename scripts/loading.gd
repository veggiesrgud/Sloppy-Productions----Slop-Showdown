extends Control
@export var next_scene: String = "res://scenes/level/level.tscn"
@export var load_time: float = 5.0
@export var min_show_time: float = 1.0
var time_left: float
var _has_switched := false
var _elapsed := 0.0
var _thread_progress := 0.0
var _queue: Array[String] = []
var _queue_index := 0
const PRELOAD_BATCH := 3
@onready var bar: ProgressBar = $ProgressBar
@onready var label: Label = $ProgressBar/Label
@onready var center_panel: Panel = $CenterPanel
@onready var logo: TextureRect = $CenterPanel/Logo
@onready var logo_shadow: TextureRect = $CenterPanel/LogoShadow
func _ready():
	if DisplayServer.get_name() == "headless":
		call_deferred("_switch_now")
		return
	time_left = load_time
	bar.max_value = 100.0
	bar.value = 0
	_build_preload_queue()
	ResourceLoader.load_threaded_request(next_scene)
	print("Loading screen ready - warming ", _queue.size(), " assets then go to ", next_scene)
	print("Bar rect on ready: ", bar.get_rect(), " visible: ", bar.visible)
	if logo.texture == null:
		logo.texture = load("res://splash-screen.png")
	if logo_shadow and logo.texture:
		logo_shadow.texture = logo.texture
	get_viewport().size_changed.connect(_fit_center_panel)
	_fit_center_panel()
	set_process_input(false)
func _fit_center_panel() -> void:
	if not center_panel:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var fit_w := (viewport_size.x - 32.0) / 640.0
	var fit_h := (viewport_size.y - 140.0) / 400.0
	var scale_factor := fit_w
	if fit_h < scale_factor:
		scale_factor = fit_h
	if scale_factor > 1.0:
		scale_factor = 1.0
	elif scale_factor < 0.3:
		scale_factor = 0.3
	center_panel.pivot_offset = center_panel.size * 0.5
	center_panel.scale = Vector2(scale_factor, scale_factor)
func _switch_now() -> void:
	if _has_switched:
		return
	_has_switched = true
	set_process(false)
	if is_inside_tree():
		get_tree().change_scene_to_file(next_scene)
func _build_preload_queue() -> void:
	_queue = [
		"res://scenes/level/player.tscn",
		"res://objects/droplet.tscn",
		"res://objects/impact.tscn",
		"res://objects/enemy.tscn",
		"res://scenes/items/hats/fedora.tscn",
		"res://scenes/items/hats/headphones.tscn",
		"res://scenes/items/hats/pirate_hat.tscn",
		"res://scenes/items/hats/sheriff_hat.tscn",
		"res://scenes/items/hats/sombrero.tscn",
		"res://scenes/items/hats/wizard_hat.tscn",
		"res://scenes/items/backpacks/backpack.tscn",
		"res://scenes/items/weapons/water_gun.tscn",
		"res://scenes/items/misc/chicken_leg.tscn",
		"res://scenes/items/misc/bone.tscn",
		"res://scenes/items/misc/chalice.tscn",
		"res://sounds/blaster.ogg",
		"res://sounds/enemy_hurt.ogg",
		"res://sounds/enemy_destroy.ogg",
		"res://sounds/enemy_attack.ogg",
		"res://sounds/land.ogg",
		"res://sounds/jump_a.ogg",
		"res://sounds/jump_b.ogg",
		"res://sounds/jump_c.ogg",
		"res://sounds/walking.ogg",
		"res://sounds/weapon_change.ogg",
	]
	_queue_index = 0


func _process(delta):
	_elapsed += delta
	for i in PRELOAD_BATCH:
		if _queue_index >= _queue.size():
			break
		var path := _queue[_queue_index]
		_queue_index += 1
		if ResourceLoader.has_cached(path):
			continue
		var res := ResourceLoader.load(path)
		if res == null:
			push_warning("Preload failed: " + path)
	var progress_arr := [0.0]
	var status := ResourceLoader.load_threaded_get_status(next_scene, progress_arr)
	_thread_progress = float(progress_arr[0])
	var queue_frac := 1.0
	if _queue.size() > 0:
		queue_frac = float(_queue_index) / float(_queue.size())
	var overall := int((_thread_progress * 0.6 + queue_frac * 0.4) * 100.0)
	bar.value = overall
	label.text = "LOADING... %d%%" % overall
	var thread_done := status == ResourceLoader.THREAD_LOAD_LOADED
	var thread_failed := status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	if _has_switched:
		return
	if (thread_done and _queue_index >= _queue.size() and _elapsed >= min_show_time) or (thread_failed and _elapsed >= min_show_time):
		_has_switched = true
		set_process(false)
		print("Loading done - switching to ", next_scene)
		await get_tree().create_timer(0.1).timeout
		if is_inside_tree():
			get_tree().change_scene_to_file(next_scene)
func _input(event):
	pass

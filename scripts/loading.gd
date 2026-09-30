extends Control

@export var next_scene: String = "res://scenes/main.tscn"
@export var load_time: float = 5.0

var time_left: float

@onready var bar: ProgressBar = $ProgressBar
@onready var label: Label = $ProgressBar/Label
@onready var center_panel: Panel = $CenterPanel
@onready var logo: TextureRect = $CenterPanel/Logo
@onready var logo_shadow: TextureRect = $CenterPanel/LogoShadow

func _ready():
	time_left = load_time
	bar.max_value = load_time
	bar.value = 0
	print("Loading screen ready - will wait ", load_time, "s then go to ", next_scene)
	print("Bar rect on ready: ", bar.get_rect(), " visible: ", bar.visible)
	if logo.texture == null:
		logo.texture = load("res://splash-screen.png")
	if logo_shadow and logo.texture:
		logo_shadow.texture = logo.texture
	get_viewport().size_changed.connect(_fit_center_panel)
	_fit_center_panel()
	# Ensure we stay full 5 seconds - no early skip
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

func _process(delta):
	time_left = max(0, time_left - delta)
	var elapsed = load_time - time_left
	bar.value = elapsed
	# Show both percentage and countdown timer as requested
	var secs_left = int(ceil(time_left))
	label.text = "LOADING... %d%%  (%ds)" % [int((elapsed / load_time) * 100), secs_left]
	if int(elapsed * 10) % 10 == 0:
		print("Loading... ", int(elapsed), "s elapsed, bar ", bar.value, "/", bar.max_value, " time_left ", time_left)
	if time_left <= 0:
		print("Loading done - switching to ", next_scene)
		# Small delay to ensure bar fills to 100% before switching
		await get_tree().create_timer(0.1).timeout
		get_tree().change_scene_to_file(next_scene)

func _input(event):
	# Block any input that would skip - must wait full 5 seconds
	pass

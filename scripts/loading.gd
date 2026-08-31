extends Control

@export var next_scene: String = "res://scenes/main.tscn"
@export var load_time: float = 5.0

var time_left: float

@onready var bar: ProgressBar = $ProgressBar
@onready var label: Label = $ProgressBar/Label
@onready var logo: TextureRect = $CenterPanel/Logo
@onready var logo_shadow: TextureRect = $CenterPanel/LogoShadow

var tween: Tween

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
	# Pulse animation for logo - subtle slop wobble
	tween = create_tween().set_loops()
	tween.tween_property(logo, "scale", Vector2(1.03, 1.03), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(logo, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Ensure we stay full 5 seconds - no early skip
	set_process_input(false)

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

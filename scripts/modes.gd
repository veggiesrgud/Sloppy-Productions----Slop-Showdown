extends Control

var _panel: VBoxContainer = null

func _ready() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.16, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var video = VideoStreamPlayer.new()
	var stream = load("res://scenes/modes_background.ogv")
	var video_ready := stream != null
	if stream:
		video.stream = stream
		video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		video.expand = true
		video.volume_db = 0.0
		add_child(video)

	var panel = VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -200
	panel.offset_top = -150
	panel.offset_right = 200
	panel.offset_bottom = 150
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.custom_minimum_size = Vector2(400, 300)
	panel.visible = false
	add_child(panel)
	_panel = panel

	var title = Label.new()
	title.text = "GAME MODES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	panel.add_child(title)

	var arena_btn = _make_button("ARENA", Color(1.0, 0.42, 0.79, 1))
	arena_btn.pressed.connect(_on_arena)
	panel.add_child(arena_btn)

	var tut_btn = _make_button("TUTORIAL", Color(0.42, 1.0, 0.32, 1))
	tut_btn.pressed.connect(_on_tutorial)
	panel.add_child(tut_btn)

	var sound = AudioStreamPlayer.new()
	var audio = load("res://scenes/modes_sound.ogg")
	if audio is AudioStreamOggVorbis:
		(audio as AudioStreamOggVorbis).loop = true
	if audio:
		sound.stream = audio
		add_child(sound)

	if video_ready:
		video.finished.connect(_on_video_finished)
		video.play()
		if audio:
			sound.play()
	else:
		_show_panel(panel)

func _make_button(text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 60)
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1, 1))
	btn.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.1, 1))
	var normal = StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_right = 12
	normal.corner_radius_bottom_left = 12
	var hover = StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.15)
	hover.corner_radius_top_left = 12
	hover.corner_radius_top_right = 12
	hover.corner_radius_bottom_right = 12
	hover.corner_radius_bottom_left = 12
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.15)
	pressed.corner_radius_top_left = 12
	pressed.corner_radius_top_right = 12
	pressed.corner_radius_bottom_right = 12
	pressed.corner_radius_bottom_left = 12
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn

func _on_video_finished() -> void:
	if _panel:
		_show_panel(_panel)

func _show_panel(panel: VBoxContainer) -> void:
	panel.visible = true
	panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 1.2)

func _on_arena() -> void:
	get_tree().change_scene_to_file("res://scenes/level/level.tscn")

func _on_tutorial() -> void:
	get_tree().change_scene_to_file("res://scenes/level/the_walk_through.tscn")
extends Control

func _ready() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.16, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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
	add_child(panel)

	var title = Label.new()
	title.text = "GAME MODES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	panel.add_child(title)

	var arena_btn = Button.new()
	arena_btn.text = "ARENA"
	arena_btn.custom_minimum_size = Vector2(300, 60)
	arena_btn.pressed.connect(_on_arena)
	panel.add_child(arena_btn)

	var tut_btn = Button.new()
	tut_btn.text = "TUTORIAL"
	tut_btn.custom_minimum_size = Vector2(300, 60)
	tut_btn.pressed.connect(_on_tutorial)
	panel.add_child(tut_btn)

func _on_arena() -> void:
	get_tree().change_scene_to_file("res://scenes/level/level.tscn")

func _on_tutorial() -> void:
	get_tree().change_scene_to_file("res://scenes/level/the_walk_through.tscn")
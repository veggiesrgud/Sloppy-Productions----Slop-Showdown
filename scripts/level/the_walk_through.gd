extends Node3D

var _inventory_visible := false

@onready var _inventory_ui = get_node_or_null("InventoryUI")
@onready var _hotbar_ui = get_node_or_null("HotbarUI")
@onready var _pause_menu = get_node_or_null("PauseMenuUI")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _inventory_ui:
		_inventory_ui.close_inventory()
		_inventory_ui.visible = false
	if _pause_menu:
		_pause_menu.resume_pressed.connect(_on_pause_resume_pressed)
		_pause_menu.main_menu_pressed.connect(_on_pause_main_menu_pressed)
		_pause_menu.quit_pressed.connect(_on_pause_quit_pressed)
		var main_menu_btn = get_node_or_null("PauseMenuUI/Overlay/Panel/MarginContainer/Buttons/MainMenu")
		if main_menu_btn:
			main_menu_btn.text = "MODES SCREEN"
		_pause_menu.hide_menu()
	var player = get_node_or_null("Player")
	if player:
		if _inventory_ui:
			_inventory_ui.current_player = player
			_inventory_ui.inventory_closed.connect(_on_inventory_closed)
		if _hotbar_ui:
			_hotbar_ui.set_player(player)
			_hotbar_ui.refresh()
	var map = get_node_or_null("TheWalkThrough")
	if map:
		_add_trimesh(map)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_handle_pause_action()
		return
	if event.is_action_pressed("inventory"):
		_toggle_inventory()

func _toggle_inventory() -> void:
	var player = get_node_or_null("Player")
	if not player:
		return
	_inventory_visible = not _inventory_visible
	if _inventory_ui:
		if _inventory_visible:
			_inventory_ui.open_inventory(player)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_inventory_ui.close_inventory()
		_inventory_ui.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _hotbar_ui:
			_hotbar_ui.refresh()

func _on_inventory_closed() -> void:
	_inventory_visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _hotbar_ui:
		_hotbar_ui.refresh()

func _handle_pause_action() -> void:
	if _inventory_visible:
		_close_inventory()
		return
	if _pause_menu and _pause_menu.is_menu_visible():
		_hide_pause_menu()
		return
	if _pause_menu:
		_pause_menu.show_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_inventory() -> void:
	if _inventory_ui:
		_inventory_ui.close_inventory()
		_inventory_ui.visible = false
	_inventory_visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _hotbar_ui:
		_hotbar_ui.refresh()

func _hide_pause_menu() -> void:
	if _pause_menu:
		_pause_menu.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_pause_resume_pressed() -> void:
	_hide_pause_menu()

func _on_pause_main_menu_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/modes.tscn")

func _on_pause_quit_pressed() -> void:
	get_tree().quit()

func is_gameplay_input_blocked() -> bool:
	return _pause_menu != null and _pause_menu.is_menu_visible()

func is_camera_input_blocked() -> bool:
	return is_gameplay_input_blocked() or _inventory_visible

func _add_trimesh(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh = (child as MeshInstance3D).mesh
			if mesh:
				var body = StaticBody3D.new()
				var shape = CollisionShape3D.new()
				var concave = mesh.create_trimesh_shape()
				if concave:
					shape.shape = concave
					body.add_child(shape)
					child.add_child(body)
		_add_trimesh(child)

extends Node3D

var _inventory_visible := false
var _pending_exit := false

@onready var _inventory_ui = get_node_or_null("InventoryUI")
@onready var _hotbar_ui = get_node_or_null("HotbarUI")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# wire the return box to go back to the modes screen
	var return_box = get_node_or_null("ReturnBox")
	if return_box:
		return_box.body_entered.connect(_on_player_entered_return_box)
	# wire the inventory and hotbar to the player
	var player = get_node_or_null("Player")
	if player:
		if _inventory_ui:
			_inventory_ui.current_player = player
			_inventory_ui.inventory_closed.connect(_on_inventory_closed)
		if _hotbar_ui:
			_hotbar_ui.set_player(player)
			_hotbar_ui.refresh()
	# add trimesh collision to the map meshes
	var map = get_node_or_null("TheWalkThrough")
	if map:
		_add_trimesh(map)

func _process(_delta: float) -> void:
	if _pending_exit:
		_pending_exit = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/modes.tscn")

func _input(event: InputEvent) -> void:
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
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _hotbar_ui:
			_hotbar_ui.refresh()

func _on_inventory_closed() -> void:
	_inventory_visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _hotbar_ui:
		_hotbar_ui.refresh()

func _on_player_entered_return_box(body: Node3D) -> void:
	_pending_exit = true

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

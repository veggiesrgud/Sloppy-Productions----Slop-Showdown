extends Node3D

@onready var inventory_ui: InventoryUI = get_node_or_null("InventoryUI")
@onready var chat_ui: MultiplayerChatUI = get_node_or_null("MultiplayerChatUI")

var inventory_visible := false

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if inventory_ui:
		inventory_ui.close_inventory()
		inventory_ui.inventory_closed.connect(_on_inventory_closed)
	var chat = get_node_or_null("MultiplayerChatUI")
	if chat and chat.has_method("close_chat"):
		chat.close_chat()
	# Hide menu UIs - single-player direct play, no host/join needed
	for n in ["MainMenuUI", "PlayerListUI", "PauseMenuUI"]:
		var ui = get_node_or_null(n)
		if ui:
			ui.visible = false
	# Ensure player has inventory even offline
	call_deferred("_setup_player")

func _setup_player():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player = get_node_or_null("Player") as Character
	if not player:
		return
	if not player.player_inventory:
		player.player_inventory = PlayerInventory.new()
		player._add_starting_items()
		player.call_deferred("_sync_equipment_appearance")
	# Force first-person FPS view like old slop player
	var spring = player.get_node_or_null("SpringArmOffset")
	if spring:
		spring.is_first_person = true
		spring.call_deferred("_apply_perspective")
	# Click to recapture mouse if user pressed Esc
	if not Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	# Click to recapture mouse for FPS look
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not inventory_visible and not (chat_ui and chat_ui.is_chat_visible()):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("inventory"):
		toggle_inventory()
	elif event.is_action_pressed("toggle_chat"):
		if chat_ui:
			chat_ui.toggle_chat()

func toggle_inventory():
	var player = get_node_or_null("Player") as Character
	if not player:
		return
	if not inventory_ui:
		return
	inventory_visible = !inventory_visible
	if inventory_visible:
		inventory_ui.open_inventory(player)
	else:
		inventory_ui.close_inventory()
	_update_mouse()

func is_inventory_visible() -> bool:
	return inventory_visible

func is_chat_visible() -> bool:
	return chat_ui and chat_ui.is_chat_visible()

func is_gameplay_input_blocked() -> bool:
	return inventory_visible or (chat_ui and chat_ui.is_chat_visible())

func is_camera_input_blocked() -> bool:
	return is_gameplay_input_blocked()

func _on_inventory_closed():
	inventory_visible = false
	_update_mouse()

func _update_mouse():
	if inventory_visible or (chat_ui and chat_ui.is_chat_visible()):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func update_local_inventory_display():
	if inventory_ui:
		inventory_ui.refresh_display()

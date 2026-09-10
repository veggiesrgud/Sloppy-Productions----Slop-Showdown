extends Node3D

@onready var inventory_ui: InventoryUI = get_node_or_null("InventoryUI")
@onready var chat_ui: MultiplayerChatUI = get_node_or_null("MultiplayerChatUI")
@onready var main_menu: MainMenuUI = get_node_or_null("MainMenuUI")

var inventory_visible := false

func _ready():
	if inventory_ui:
		inventory_ui.close_inventory()
		inventory_ui.inventory_closed.connect(_on_inventory_closed)
	var chat = get_node_or_null("MultiplayerChatUI")
	if chat and chat.has_method("close_chat"):
		chat.close_chat()
	# Show main menu right after loading (Host / Join / Quit)
	if main_menu:
		main_menu.show_menu()
		if not main_menu.host_pressed.is_connected(_on_host_pressed):
			main_menu.host_pressed.connect(_on_host_pressed)
		if not main_menu.join_pressed.is_connected(_on_join_pressed):
			main_menu.join_pressed.connect(_on_join_pressed)
		if not main_menu.quit_pressed.is_connected(_on_quit_pressed):
			main_menu.quit_pressed.connect(_on_quit_pressed)
		_prefill_address()
	# Freeze the whole world (enemies, timers, droplets, player) until Host/Join
	get_tree().paused = true
	_update_mouse()
	# Ensure player has inventory even offline
	call_deferred("_setup_player")

func _prefill_address():
	if main_menu == null:
		return
	var addr = main_menu.get_node_or_null("MainContainer/MainMenu/Option3/AddressInput") as LineEdit
	if addr and addr.text.strip_edges().is_empty():
		addr.text = "127.0.0.1"

func _setup_player():
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
	_update_mouse()

func _apply_profile(nickname: String, skin: String):
	var player = get_node_or_null("Player") as Character
	if not player:
		return
	var net = get_node_or_null("/root/Network")
	var nick := nickname.strip_edges()
	var skin_enum = 0
	if net:
		nick = net.sanitize_nickname(nickname, "Player")
		skin_enum = net.sanitize_skin_value(skin)
	player.set_player_skin(skin_enum)
	if player.get("nickname"):
		player.nickname.text = nick

func _on_host_pressed(nickname: String, skin: String) -> void:
	var net = get_node_or_null("/root/Network")
	if net == null:
		return
	var error = net.start_host(nickname, skin)
	if error:
		push_warning("Failed to host game. Error: " + str(error))
		return
	_apply_profile(nickname, skin)
	if main_menu:
		main_menu.hide_menu()
	get_tree().paused = false
	_update_mouse()

func _on_join_pressed(nickname: String, skin: String, address: String) -> void:
	var net = get_node_or_null("/root/Network")
	if net == null:
		return
	var error = net.join_game(nickname, skin, address)
	if error:
		push_warning("Failed to join game. Error: " + str(error))
		return
	_apply_profile(nickname, skin)
	if main_menu:
		main_menu.hide_menu()
	get_tree().paused = false
	_update_mouse()

func _on_quit_pressed() -> void:
	var net = get_node_or_null("/root/Network")
	if net and net.has_method("leave_game"):
		net.leave_game()
	get_tree().paused = false
	get_tree().quit()

func _menu_visible() -> bool:
	return main_menu and main_menu.is_menu_visible()

func _input(event):
	# Esc re-opens the menu before a session starts (re-freezes the world)
	if event.is_action_pressed("pause"):
		if main_menu and not main_menu.is_menu_visible() and not multiplayer.has_multiplayer_peer():
			main_menu.show_menu()
			get_tree().paused = true
			_update_mouse()
		return
	if _menu_visible():
		return
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
	return _menu_visible() or inventory_visible or (chat_ui and chat_ui.is_chat_visible())

func is_camera_input_blocked() -> bool:
	return is_gameplay_input_blocked()

func _on_inventory_closed():
	inventory_visible = false
	_update_mouse()

func _update_mouse():
	if _menu_visible() or inventory_visible or (chat_ui and chat_ui.is_chat_visible()):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func update_local_inventory_display():
	if inventory_ui:
		inventory_ui.refresh_display()

class_name HotbarUI
extends Control

# Minecraft-style hotbar: weapons only, scroll wheel or 1-9 to select.
# Selecting a weapon wields it (held in hand) without shuffling the rest.

const HOTBAR_SIZE := 9
const SLOT_PIXELS := 56.0
const NAME_SHOW_MSEC := 2000

const SELECTED_TINT := Color(1.0, 0.85, 0.3)
const NORMAL_TINT := Color.WHITE

var current_player: Character
var selected_index := 0

# Hotbar cell -> real inventory slot. Rebuilt on every refresh so wearables
# (hats/backpacks) never take a cell; only weapons and plain items list here.
var _slot_map: Array[int] = []

var _slot_uis: Array[InventorySlotUI] = []
var _name_hide_at_msec := 0

@onready var _bar: HBoxContainer = $Bar
@onready var _name_label: Label = $ItemName


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot_scene := preload("res://scenes/ui/inventory_slot_ui.tscn") as PackedScene
	for i in range(HOTBAR_SIZE):
		var cell := VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 0)
		var key_label := Label.new()
		key_label.text = str(i + 1)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.modulate = Color(1, 1, 1, 0.6)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slot := slot_scene.instantiate() as InventorySlotUI
		slot.custom_minimum_size = Vector2(SLOT_PIXELS, SLOT_PIXELS)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(key_label)
		cell.add_child(slot)
		_bar.add_child(cell)
		_slot_uis.append(slot)
	_name_label.visible = false
	visible = false


func set_player(player: Character) -> void:
	current_player = player
	if current_player:
		refresh()
	else:
		visible = false


func refresh() -> void:
	if current_player == null or not is_instance_valid(current_player):
		return
	var inventory := current_player.get_inventory()
	if inventory == null:
		return
	_rebuild_slot_map()
	for i in range(HOTBAR_SIZE):
		if i < _slot_map.size():
			_slot_uis[i].set_slot_data(inventory.get_slot(_slot_map[i]), _slot_map[i])
		else:
			_slot_uis[i].set_slot_data(null, i)
	_update_selection_visual()


# Collect the first HOTBAR_SIZE weapons in inventory order. The hotbar is
# weapons-only: plain items stay inventory-only, wearables stay worn.
func _rebuild_slot_map() -> void:
	_slot_map.clear()
	if current_player == null or not is_instance_valid(current_player):
		return
	var inventory := current_player.get_inventory()
	if inventory == null:
		return
	var active_count := inventory.get_active_slot_count()
	for i in range(active_count):
		if _slot_map.size() >= HOTBAR_SIZE:
			break
		var slot := inventory.get_slot(i)
		if slot == null or slot.is_empty():
			continue
		var item := ItemDatabase.get_item(slot.item_id)
		if item == null:
			continue
		if item.item_type != Item.ItemType.WEAPON:
			continue
		_slot_map.append(i)


func select_index(index: int) -> void:
	if current_player == null or not is_instance_valid(current_player):
		return
	selected_index = clampi(index, 0, HOTBAR_SIZE - 1)
	_update_selection_visual()
	_show_selected_name()
	_equip_selected_weapon()


func cycle_selection(direction: int) -> void:
	if current_player == null or not is_instance_valid(current_player):
		return
	select_index(posmod(selected_index + direction, HOTBAR_SIZE))


func _process(_delta: float) -> void:
	# Stays visible while playing, including with inventory/chat open - only
	# the selection input is blocked then. Hides for main/pause menus.
	var show_bar := current_player != null and is_instance_valid(current_player) and not _is_menu_open()
	visible = show_bar
	if not show_bar:
		return
	if _name_label.visible and Time.get_ticks_msec() >= _name_hide_at_msec:
		_name_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if current_player == null or not is_instance_valid(current_player):
		return
	if _is_ui_blocked():
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_selection(-1)
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_selection(1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_9:
			select_index(int(key_event.keycode - KEY_1))
			get_viewport().set_input_as_handled()


# Same call the inventory UI uses for double-click equip, so behavior matches
# in every mode (host, client, offline).
func _equip_selected_weapon() -> void:
	if current_player == null or not is_instance_valid(current_player):
		return
	var inventory := current_player.get_inventory()
	if inventory == null:
		return
	if selected_index < 0 or selected_index >= _slot_map.size():
		return
	var real_index := _slot_map[selected_index]
	if not inventory.is_slot_active(real_index):
		return
	var slot := inventory.get_slot(real_index)
	if slot == null or slot.is_empty():
		return
	var item := ItemDatabase.get_item(slot.item_id)
	if item == null:
		return
	if item.item_type != Item.ItemType.WEAPON:
		return
	# Single idempotent RPC: wielding only records the slot, nothing moves,
	# so rapid scrolling can never shuffle the inventory.
	current_player.request_equip_item.rpc_id(1, real_index, item.item_type)


func _update_selection_visual() -> void:
	for i in range(_slot_uis.size()):
		var background := _slot_uis[i].get_node_or_null("Background") as Panel
		if background:
			background.modulate = SELECTED_TINT if i == selected_index else NORMAL_TINT


func _show_selected_name() -> void:
	if current_player == null or not is_instance_valid(current_player):
		return
	var inventory := current_player.get_inventory()
	if inventory == null:
		return
	if selected_index < 0 or selected_index >= _slot_map.size():
		return
	var slot := inventory.get_slot(_slot_map[selected_index])
	if slot == null or slot.is_empty():
		return
	var item := ItemDatabase.get_item(slot.item_id)
	if item == null:
		return
	_name_label.text = item.name
	_name_label.visible = true
	_name_hide_at_msec = Time.get_ticks_msec() + NAME_SHOW_MSEC


# Full-screen menus that hide the bar entirely.
func _is_menu_open() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	var main_menu := scene.get_node_or_null("MainMenuUI")
	if main_menu and main_menu.has_method("is_menu_visible") and main_menu.is_menu_visible():
		return true
	var pause_menu := scene.get_node_or_null("PauseMenuUI")
	if pause_menu and pause_menu.has_method("is_menu_visible") and pause_menu.is_menu_visible():
		return true
	return false


# Blocked while chatting, inventory/pause/main menu open - same moments the
# camera and gameplay input are blocked.
func _is_ui_blocked() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	if scene.has_method("is_gameplay_input_blocked") and scene.is_gameplay_input_blocked():
		return true
	var main_menu := scene.get_node_or_null("MainMenuUI")
	if main_menu and main_menu.has_method("is_menu_visible") and main_menu.is_menu_visible():
		return true
	var pause_menu := scene.get_node_or_null("PauseMenuUI")
	if pause_menu and pause_menu.has_method("is_menu_visible") and pause_menu.is_menu_visible():
		return true
	return false

class_name MainMenuUI
extends Control
signal host_pressed(nickname: String, skin: String)
signal join_pressed(nickname: String, skin: String, address: String)
signal quit_pressed
signal refresh_servers_pressed
signal add_server_pressed(address: String)
signal remove_server_pressed(address: String)
const SKIN_OPTIONS: Array[String] = ["Blue", "Yellow", "Green", "Red"]
const SAFE_AREA_MARGIN := 24.0
@onready var skin_input: OptionButton = $MainContainer/MainMenu/Option2/SkinInput
@onready var nick_input: LineEdit = $MainContainer/MainMenu/Option1/NickInput
@onready var address_input: LineEdit = $MainContainer/MainMenu/Option3/AddressInput
@onready var main_container: VBoxContainer = $MainContainer
@onready var server_list: ItemList = $MainContainer/MainMenu/ServerSection/ServerList
var _server_entries: Array = []
func _ready() -> void:
	skin_input.clear()
	for skin_name in SKIN_OPTIONS:
		skin_input.add_item(skin_name)
	skin_input.select(0)
	resized.connect(_update_responsive_layout)
	call_deferred("_update_responsive_layout")
func _on_host_pressed() -> void:
	var nickname = nick_input.text.strip_edges()
	var skin = get_skin()
	host_pressed.emit(nickname, skin)
func _on_join_pressed() -> void:
	var nickname = nick_input.text.strip_edges()
	var skin = get_skin()
	var address = get_join_address()
	join_pressed.emit(nickname, skin, address)
func _on_quit_pressed():
	quit_pressed.emit()
func _on_refresh_pressed() -> void:
	refresh_servers_pressed.emit()
func _on_add_server_pressed() -> void:
	add_server_pressed.emit(address_input.text.strip_edges())
func _on_remove_server_pressed() -> void:
	var addr := get_selected_address()
	if addr.is_empty() and address_input:
		addr = address_input.text.strip_edges()
	remove_server_pressed.emit(addr)
func _on_server_selected(index: int) -> void:
	if index < 0 or index >= _server_entries.size():
		return
	var addr := str(_server_entries[index].get("address", ""))
	if not addr.is_empty() and address_input:
		address_input.text = addr
func get_join_address() -> String:
	var selected := get_selected_address()
	if not selected.is_empty():
		return selected
	return address_input.text.strip_edges() if address_input else ""
func get_selected_address() -> String:
	if server_list == null:
		return address_input.text.strip_edges() if address_input else ""
	var sel := server_list.get_selected_items()
	if sel.is_empty():
		return ""
	var idx: int = sel[0]
	if idx < 0 or idx >= _server_entries.size():
		return ""
	return str(_server_entries[idx].get("address", ""))
func set_server_list(entries: Array) -> void:
	if server_list == null:
		_server_entries = entries
		return
	var prev_addr := ""
	var sel := server_list.get_selected_items()
	if not sel.is_empty() and int(sel[0]) >= 0 and int(sel[0]) < _server_entries.size():
		prev_addr = str(_server_entries[int(sel[0])].get("address", ""))
	_server_entries = entries
	server_list.clear()
	for e in entries:
		var label := ""
		var players_info: String = ""
		if int(e.get("players", -1)) >= 0:
			players_info = " (%d/%d)" % [int(e.get("players", 0)), int(e.get("max_players", 0))]
		var tag := "[LAN]" if str(e.get("source", "")) == "lan" else "[SAVED]"
		label = "%s %s - %s%s" % [tag, str(e.get("name", "")), str(e.get("address", "")), players_info]
		server_list.add_item(label)
	for i in range(_server_entries.size()):
		if str(_server_entries[i].get("address", "")) == prev_addr:
			server_list.select(i)
			break
func show_menu():
	show()
	call_deferred("_update_responsive_layout")
func hide_menu():
	hide()
func is_menu_visible() -> bool:
	return visible
func _update_responsive_layout() -> void:
	if not main_container:
		return
	var available_size := Vector2(
		maxf(1.0, size.x - SAFE_AREA_MARGIN * 2.0), maxf(1.0, size.y - SAFE_AREA_MARGIN * 2.0)
	)
	var content_size := main_container.get_combined_minimum_size()
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		return
	var scale_factor := minf(1.0, minf(available_size.x / content_size.x, available_size.y / content_size.y))
	main_container.pivot_offset = main_container.size * 0.5
	main_container.scale = Vector2.ONE * scale_factor
func get_skin() -> String:
	return skin_input.get_item_text(skin_input.selected).to_lower()

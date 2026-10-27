# menu stuff hosting joining and server list stuff
class_name MainMenuUI
extends Control
signal host_pressed(nickname: String, skin: String, is_public: bool, custom_code: String)
signal join_pressed(nickname: String, skin: String, address: String)
signal join_by_code_pressed(nickname: String, skin: String, join_code: String)
signal quit_pressed
signal refresh_servers_pressed
signal add_server_pressed(address: String)
signal remove_server_pressed(address: String)
const SKIN_OPTIONS: Array[String] = ["Blue", "Yellow", "Green", "Red"]
const SAFE_AREA_MARGIN := 24.0
@onready var skin_input: OptionButton = $MainContainer/MainMenu/Option2/SkinInput
@onready var nick_input: LineEdit = $MainContainer/MainMenu/Option1/NickInput
@onready var host_code_input: LineEdit = $MainContainer/MainMenu/Option3/HostCodeInput
@onready var join_code_input: LineEdit = $MainContainer/MainMenu/Option4/JoinCodeInput
@onready var public_toggle: CheckButton = $MainContainer/MainMenu/Option5/PublicToggle
@onready var main_container: VBoxContainer = $MainContainer
@onready var server_list: ItemList = $MainContainer/MainMenu/ServerSection/ServerList
@onready var status_label: Label = $MainContainer/MainMenu/StatusLabel
var _server_entries: Array = []
func _ready() -> void:
	skin_input.clear()
	for skin_name in SKIN_OPTIONS:
		skin_input.add_item(skin_name)
	skin_input.select(0)
	public_toggle.button_pressed = true
	resized.connect(_update_responsive_layout)
	call_deferred("_update_responsive_layout")
func _on_host_pressed() -> void:
	var nickname = nick_input.text.strip_edges()
	var skin = get_skin()
	var is_public = public_toggle.button_pressed
	var custom_code = host_code_input.text.strip_edges()
	host_pressed.emit(nickname, skin, is_public, custom_code)
func _on_join_pressed() -> void:
	var nickname = nick_input.text.strip_edges()
	var skin = get_skin()
	var address = get_join_address()
	join_pressed.emit(nickname, skin, address)
func _on_join_code_pressed() -> void:
	var nickname = nick_input.text.strip_edges()
	var skin = get_skin()
	var join_code = join_code_input.text.strip_edges()
	join_by_code_pressed.emit(nickname, skin, join_code)
func _on_quit_pressed():
	quit_pressed.emit()
func _on_refresh_pressed() -> void:
	refresh_servers_pressed.emit()
func _on_add_server_pressed() -> void:
	# Server list disabled - using lobby codes only
	pass
func _on_remove_server_pressed() -> void:
	# Server list disabled - using lobby codes only
	pass
func _on_server_selected(index: int) -> void:
	pass
func get_join_address() -> String:
	# Using lobby join code, not direct IP
	return ""
func get_selected_address() -> String:
	return ""
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
func set_status(text: String) -> void:
	if status_label:
		status_label.text = text


class_name MainMenuUI
extends Control
signal host_pressed(nickname: String, skin: String, is_public: bool, custom_code: String)
signal quick_play_matched
signal join_pressed(nickname: String, skin: String, address: String)
signal join_by_code_pressed(nickname: String, skin: String, join_code: String)
signal quit_pressed
signal back_pressed
signal refresh_servers_pressed
signal add_server_pressed(address: String)
signal remove_server_pressed(address: String)
const SKIN_OPTIONS: Array[String] = ["Blue", "Yellow", "Green", "Red"]
const SAFE_AREA_MARGIN := 24.0
@onready var skin_input: OptionButton = $Option2/SkinInput
@onready var nick_input: LineEdit = $Option1/NickInput
@onready var code_input: LineEdit = $Option3/CodeInput
@onready var public_toggle: CheckButton = $Option5/PublicToggle
@onready var main_container: VBoxContainer = $MainContainer
@onready var server_list: ItemList = $ServerSection/ServerList
@onready var status_label: Label = $MainContainer/MainMenu/StatusLabel
var _server_entries: Array = []
var _quick_play_intent := false
func _ready() -> void:
	_wire_gdsync()
	skin_input.clear()
	for skin_name in SKIN_OPTIONS:
		skin_input.add_item(skin_name)
	skin_input.select(0)
	public_toggle.button_pressed = true
	code_input.text_changed.connect(_on_code_input_changed)
	resized.connect(_update_responsive_layout)
	call_deferred("_update_responsive_layout")
func _on_back_pressed() -> void:
	back_pressed.emit()

func _wire_gdsync() -> void:
	var gd = get_node_or_null("/root/GDSync")
	if gd:
		if not gd.connected.is_connected(_on_gdsync_connected):
			gd.connected.connect(_on_gdsync_connected)
		if not gd.connection_failed.is_connected(_on_gdsync_failed):
			gd.connection_failed.connect(_on_gdsync_failed)
		if not gd.lobby_joined.is_connected(_on_gdsync_lobby_joined):
			gd.lobby_joined.connect(_on_gdsync_lobby_joined)
		if not gd.lobby_join_failed.is_connected(_on_gdsync_lobby_join_failed):
			gd.lobby_join_failed.connect(_on_gdsync_lobby_join_failed)
		if not gd.matchmaking_failed.is_connected(_on_gdsync_matchmaking_failed):
			gd.matchmaking_failed.connect(_on_gdsync_matchmaking_failed)

func _on_quick_play_pressed() -> void:
	_quick_play_intent = true
	var gd = get_node_or_null("/root/GDSync")
	if gd:
		var nick := nick_input.text.strip_edges()
		var skin := get_skin()
		if not nick.is_empty():
			gd.player_set_data("nick", nick)
		gd.player_set_data("skin", skin)
	set_status("searching for a match...")
	if gd:
		if gd.is_active():
			_start_matchmaking()
		else:
			gd.start_multiplayer()

func _start_matchmaking() -> void:
	var req := MatchmakingRequest.new(4)
	req.set_min_players(2)
	GDSync.matchmaking_start(req)

func _on_gdsync_connected() -> void:
	if _quick_play_intent:
		_start_matchmaking()

func _on_gdsync_failed(err: int) -> void:
	if err == 0:
		set_status("GD-Sync: invalid key")
	elif err == 1:
		set_status("GD-Sync: timeout")
	else:
		set_status("GD-Sync: port in use")

func _on_gdsync_lobby_joined(_lobby_name: String) -> void:
	set_status("match found! entering the arena...")
	quick_play_matched.emit()

func _on_gdsync_lobby_join_failed(_lobby_name: String, error: int) -> void:
	set_status("join failed: " + str(error))

func _on_gdsync_matchmaking_failed(error: int) -> void:
	set_status("matchmaking failed: " + str(error))
func _on_host_pressed() -> void:
	var nickname = nick_input.text.strip_edges()
	var skin = get_skin()
	var is_public = public_toggle.button_pressed
	var custom_code = code_input.text.strip_edges()
	host_pressed.emit(nickname, skin, is_public, custom_code)
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
	pass
func _on_remove_server_pressed() -> void:
	pass
func _on_server_selected(index: int) -> void:
	if index >= 0 and index < _server_entries.size():
		var entry = _server_entries[index]
		code_input.text = Network.ip_to_code(str(entry.get("address", "")))
		_on_join_pressed()
	pass
func get_join_address() -> String:
	var typed = code_input.text.strip_edges()
	var decoded = Network.code_to_ip(typed)
	if not decoded.is_empty():
		return decoded
	return typed

func _on_code_input_changed(_text: String) -> void:
	var typed = code_input.text.strip_edges()
	var decoded = Network.code_to_ip(typed)
	if not decoded.is_empty():
		set_status("Server found with this code")
	elif typed.is_empty():
		set_status("")
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
		var code_text := Network.ip_to_code(str(e.get("address", "")))
		label = "%s %s - code: %s%s" % [tag, str(e.get("name", "")), code_text, players_info]
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

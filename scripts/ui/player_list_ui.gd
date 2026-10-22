class_name PlayerListUI
extends Control

const PLAYER_ROW_HEIGHT := 28.0
const MAX_VISIBLE_ROWS := 8
const RESERVED_VERTICAL_SPACE := 190.0
const SAFE_AREA_MARGIN := 16.0

var _player_count := 0

@onready var panel: PanelContainer = $SafeArea/PositionContainer/Panel
@onready var count_label: Label = $SafeArea/PositionContainer/Panel/MarginContainer/Content/Count
@onready var player_scroll: ScrollContainer = $SafeArea/PositionContainer/Panel/MarginContainer/Content/PlayerScroll
@onready
var players_label: RichTextLabel = $SafeArea/PositionContainer/Panel/MarginContainer/Content/PlayerScroll/Players


func _ready() -> void:
	resized.connect(_update_layout)
	_update_layout()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		player_scroll.scroll_vertical -= int(PLAYER_ROW_HEIGHT)
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		player_scroll.scroll_vertical += int(PLAYER_ROW_HEIGHT)


func show_players(players: Dictionary, local_peer_id: int) -> void:
	refresh_players(players, local_peer_id)
	player_scroll.scroll_vertical = 0
	show()
	call_deferred("_apply_panel_scale")


func hide_players() -> void:
	hide()


func refresh_players(players: Dictionary, local_peer_id: int) -> void:
	var entries: Array = []
	for peer_id_value in players:
		var peer_id := int(peer_id_value)
		if peer_id <= 0:
			continue
		var player_info: Dictionary = players.get(peer_id, {})
		entries.append(
			{
				"id": peer_id,
				"nick": Network.sanitize_nickname(
					str(player_info.get("nick", "")), "Player_" + str(peer_id)
				),
				"kills": int(player_info.get("kills", 0)),
			}
		)
	# sort by kills, highest first
	entries.sort_custom(
		func(a, b):
			var a_kills := int(a["kills"])
			var b_kills := int(b["kills"])
			if a_kills != b_kills:
				return a_kills > b_kills
			return int(a["id"]) < int(b["id"])
	)
	_player_count = entries.size()

	count_label.text = "%d players" % _player_count
	players_label.clear()
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var local_marker := (
			" [color=#c7ccd4](you)[/color]" if int(entry["id"]) == local_peer_id else ""
		)
		var kills := int(entry["kills"])
		var kill_text := "1 kill" if kills == 1 else "%d kills" % kills
		players_label.append_text(
			(
				"[color=#a8adb5]#%d[/color] [b]%s[/b]%s [color=#ffd166]%s[/color]"
				% [index + 1, _escape_bbcode(str(entry["nick"])), local_marker, kill_text]
			)
		)
		if index < entries.size() - 1:
			players_label.append_text("\n")
	_update_layout()


func _update_layout() -> void:
	if not panel or not player_scroll:
		return
	var panel_minimum_size := panel.custom_minimum_size
	panel_minimum_size.x = maxf(0.0, minf(420.0, size.x - 32.0))
	panel.custom_minimum_size = panel_minimum_size

	var visible_rows := maxi(1, mini(_player_count, MAX_VISIBLE_ROWS))
	var desired_height := float(visible_rows) * PLAYER_ROW_HEIGHT
	var viewport_limit := maxf(30.0, size.y - RESERVED_VERTICAL_SPACE)
	var scroll_minimum_size := player_scroll.custom_minimum_size
	scroll_minimum_size.y = minf(desired_height, viewport_limit)
	player_scroll.custom_minimum_size = scroll_minimum_size

	var players_minimum_size := players_label.custom_minimum_size
	players_minimum_size.y = float(maxi(1, _player_count)) * PLAYER_ROW_HEIGHT
	players_label.custom_minimum_size = players_minimum_size
	call_deferred("_apply_panel_scale")


func _apply_panel_scale() -> void:
	if not panel:
		return
	var available_size := Vector2(
		maxf(1.0, size.x - SAFE_AREA_MARGIN * 2.0), maxf(1.0, size.y - SAFE_AREA_MARGIN * 2.0)
	)
	var panel_size := panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	var scale_factor := minf(1.0, minf(available_size.x / panel_size.x, available_size.y / panel_size.y))
	panel.pivot_offset = panel_size * 0.5
	panel.scale = Vector2.ONE * scale_factor


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")

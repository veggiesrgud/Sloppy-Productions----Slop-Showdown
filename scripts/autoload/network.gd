extends Node

signal player_connected(peer_id, player_info)
signal server_disconnected
signal lan_servers_changed(servers: Array)

const SERVER_ADDRESS: String = "127.0.0.1"
const SERVER_PORT: int = 8080
const MAX_PLAYERS: int = 10
const MAX_NICK_LENGTH := 24
const MAX_ADDRESS_LENGTH := 253
const DISCOVERY_PORT: int = 8081
const DISCOVERY_MAGIC: String = "SLOP1"
const DISCOVERY_INTERVAL: float = 1.0
const DISCOVERY_EXPIRE: float = 6.0
const SERVERS_CONFIG: String = "user://slop_servers.cfg"

var players = {}
var player_info = {"nick": "host", "skin": Character.SkinColor.BLUE}
var lan_servers: Array = []
var _session_active := false
var _discovery_socket: PacketPeerUDP = null
var _broadcast_socket: PacketPeerUDP = null
var _discovery_active := false
var _broadcast_active := false
var _broadcast_timer := 0.0
var _server_display_name := ""
var _lan_seen: Dictionary = {}


func _ready() -> void:
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.connected_to_server.connect(_on_connected_ok)


func _process(delta: float) -> void:
	if _broadcast_active and multiplayer.is_server():
		_broadcast_timer += delta
		if _broadcast_timer >= DISCOVERY_INTERVAL:
			_broadcast_timer = 0.0
			_send_lan_broadcast()
	if _discovery_active and _discovery_socket:
		_poll_lan_discovery()
		_expire_lan_servers(delta)


func start_host(nickname: String, skin_color_str: String):
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(SERVER_PORT, MAX_PLAYERS)
	if error:
		return error

	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_session_active = true

	player_info["nick"] = sanitize_nickname(nickname, "Host_" + str(multiplayer.get_unique_id()))
	player_info["skin"] = skin_str_to_e(skin_color_str)

	if DisplayServer.get_name() == "headless":
		start_lan_broadcast(str(player_info["nick"]))
		return

	players[1] = player_info
	player_connected.emit(1, player_info)
	start_lan_broadcast(str(player_info["nick"]))


func join_game(nickname: String, skin_color_str: String, address: String = SERVER_ADDRESS):
	address = sanitize_address(address)
	if address.is_empty():
		return ERR_INVALID_PARAMETER

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, SERVER_PORT)
	if error:
		return error

	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_session_active = true

	player_info["nick"] = sanitize_nickname(nickname, "Player_" + str(multiplayer.get_unique_id()))
	player_info["skin"] = skin_str_to_e(skin_color_str)


func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	players[peer_id] = player_info
	player_connected.emit(peer_id, player_info)
	_register_player.rpc_id(1, player_info)


func _on_player_connected(id):
	if not multiplayer.is_server():
		return
	for peer_id in players:
		_sync_registered_player.rpc_id(id, peer_id, players[peer_id])


@rpc("any_peer", "reliable")
func _register_player(new_player_info):
	if not multiplayer.is_server():
		return
	if not (new_player_info is Dictionary):
		return
	var new_player_id = multiplayer.get_remote_sender_id()
	if new_player_id == 0:
		return
	if players.has(new_player_id):
		return
	var sanitized_info = sanitize_player_info(new_player_info, "Player_" + str(new_player_id))
	players[new_player_id] = sanitized_info
	player_connected.emit(new_player_id, sanitized_info)
	_sync_registered_player.rpc(new_player_id, sanitized_info)


func _on_player_disconnected(id):
	players.erase(id)


func _on_connection_failed():
	_finish_session()


func _on_server_disconnected():
	_finish_session()


func leave_game() -> void:
	stop_lan_broadcast()
	stop_lan_discovery()
	var peer := multiplayer.multiplayer_peer
	if peer:
		peer.close()
	_finish_session()


func _finish_session() -> void:
	var had_session := _session_active or multiplayer.multiplayer_peer != null or not players.is_empty()
	_session_active = false
	multiplayer.multiplayer_peer = null
	players.clear()
	if had_session:
		server_disconnected.emit()


func skin_str_to_e(s):
	match str(s).strip_edges().to_lower():
		"blue":
			return Character.SkinColor.BLUE
		"yellow":
			return Character.SkinColor.YELLOW
		"green":
			return Character.SkinColor.GREEN
		"red":
			return Character.SkinColor.RED
		_:
			return Character.SkinColor.BLUE


@rpc("authority", "reliable")
func _sync_registered_player(peer_id: int, registered_player_info: Dictionary):
	if multiplayer.is_server():
		return
	if players.has(peer_id):
		return
	var sanitized_info = sanitize_player_info(registered_player_info, "Player_" + str(peer_id))
	players[peer_id] = sanitized_info
	player_connected.emit(peer_id, sanitized_info)


func sanitize_player_info(info: Dictionary, fallback_nick: String) -> Dictionary:
	return {
		"nick": sanitize_nickname(str(info.get("nick", "")), fallback_nick),
		"skin": sanitize_skin_value(info.get("skin", Character.SkinColor.BLUE))
	}


func sanitize_nickname(nickname: String, fallback: String) -> String:
	var clean := ""
	var last_was_space := false
	for i in range(nickname.length()):
		var codepoint := nickname.unicode_at(i)
		if codepoint <= 31 or codepoint == 127:
			if not last_was_space:
				clean += " "
				last_was_space = true
			continue

		var character := nickname.substr(i, 1)
		if character == " ":
			if last_was_space:
				continue
			last_was_space = true
		else:
			last_was_space = false
		clean += character

	clean = clean.strip_edges()
	if clean.is_empty():
		clean = fallback.strip_edges()
	if clean.length() > MAX_NICK_LENGTH:
		clean = clean.substr(0, MAX_NICK_LENGTH).strip_edges()
	if clean.is_empty():
		clean = "Player"
	return clean


func sanitize_address(address: String) -> String:
	var clean = address.strip_edges()
	if clean.is_empty():
		return SERVER_ADDRESS
	if clean.length() > MAX_ADDRESS_LENGTH:
		return ""
	if clean.contains("://") or clean.contains("/") or clean.contains("\\") or clean.contains(":"):
		return ""
	return clean


func sanitize_skin_value(value) -> Character.SkinColor:
	if value is int:
		match value:
			Character.SkinColor.BLUE, Character.SkinColor.YELLOW, Character.SkinColor.GREEN, Character.SkinColor.RED:
				return value
			_:
				return Character.SkinColor.BLUE
	return skin_str_to_e(str(value))


func start_lan_broadcast(server_name: String = "") -> void:
	_server_display_name = sanitize_nickname(server_name, "Slop Server")
	_broadcast_timer = DISCOVERY_INTERVAL
	_broadcast_active = true
	if _broadcast_socket == null:
		_broadcast_socket = PacketPeerUDP.new()
		_broadcast_socket.set_broadcast_enabled(true)
		_broadcast_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)


func stop_lan_broadcast() -> void:
	_broadcast_active = false
	if _broadcast_socket:
		_broadcast_socket.close()
		_broadcast_socket = null


func start_lan_discovery() -> void:
	_discovery_active = true
	_lan_seen.clear()
	if _discovery_socket == null:
		_discovery_socket = PacketPeerUDP.new()
		var err := _discovery_socket.bind(DISCOVERY_PORT)
		if err != OK:
			push_warning("Server browser: cannot listen on UDP %d (another instance running?)" % DISCOVERY_PORT)
			_discovery_socket = null
			return


func stop_lan_discovery() -> void:
	_discovery_active = false
	if _discovery_socket:
		_discovery_socket.close()
		_discovery_socket = null


func refresh_lan_discovery() -> void:
	_lan_seen.clear()
	lan_servers.clear()
	lan_servers_changed.emit(lan_servers)


func get_server_list() -> Array:
	var combined: Array = []
	var seen_addrs := {}
	for s in lan_servers:
		var key := str(s.get("address", "")) + ":" + str(s.get("port", SERVER_PORT))
		if not seen_addrs.has(key):
			seen_addrs[key] = true
			combined.append({"source": "lan", "name": s.get("name", key), "address": s.get("address", ""), "players": s.get("players", 0), "max_players": s.get("max_players", MAX_PLAYERS), "port": s.get("port", SERVER_PORT)})
	for s in get_saved_servers():
		var key := str(s.get("address", "")) + ":" + str(s.get("port", SERVER_PORT))
		if not seen_addrs.has(key):
			seen_addrs[key] = true
			combined.append({"source": "saved", "name": s.get("name", key), "address": s.get("address", ""), "players": -1, "max_players": -1, "port": s.get("port", SERVER_PORT)})
	return combined


func _local_lan_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			if "." in ip and not ip.contains(":"):
				return ip
	for ip in IP.get_local_addresses():
		if "." in ip and not ip.contains(":") and not ip.begins_with("127."):
			return ip
	return SERVER_ADDRESS


func _send_lan_broadcast() -> void:
	if _broadcast_socket == null:
		return
	var payload := "|".join([
		DISCOVERY_MAGIC,
		_server_display_name,
		_local_lan_ip(),
		str(players.size()),
		str(MAX_PLAYERS),
		str(SERVER_PORT),
	])
	_broadcast_socket.put_packet(payload.to_utf8_buffer())


func _poll_lan_discovery() -> void:
	var changed := false
	while _discovery_socket and _discovery_socket.get_available_packet_count() > 0:
		var data := _discovery_socket.get_packet()
		var text := data.get_string_from_utf8()
		var parts := text.split("|")
		if parts.size() < 6 or parts[0] != DISCOVERY_MAGIC:
			continue
		var entry := {
			"name": sanitize_nickname(parts[1], "Slop Server"),
			"address": sanitize_address(parts[2]),
			"players": int(parts[3]),
			"max_players": int(parts[4]),
			"port": int(parts[5]),
			"age": 0.0,
		}
		if str(entry["address"]).is_empty():
			continue
		var key := str(entry["address"]) + ":" + str(entry["port"])
		_lan_seen[key] = entry
		changed = true
	if changed:
		_rebuild_lan_list()


func _expire_lan_servers(delta: float) -> void:
	var changed := false
	var expired: Array = []
	for key in _lan_seen:
		_lan_seen[key]["age"] = float(_lan_seen[key].get("age", 0.0)) + delta
		if float(_lan_seen[key]["age"]) > DISCOVERY_EXPIRE:
			expired.append(key)
	for key in expired:
		_lan_seen.erase(key)
		changed = true
	if changed:
		_rebuild_lan_list()


func _rebuild_lan_list() -> void:
	lan_servers.clear()
	for key in _lan_seen:
		lan_servers.append(_lan_seen[key])
	lan_servers_changed.emit(lan_servers)


func get_saved_servers() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SERVERS_CONFIG) != OK:
		return []
	var out: Array = []
	for section in cfg.get_sections():
		if not section.begins_with("server_"):
			continue
		out.append({
			"name": str(cfg.get_value(section, "name", section)),
			"address": sanitize_address(str(cfg.get_value(section, "address", ""))),
			"port": int(cfg.get_value(section, "port", SERVER_PORT)),
		})
	return out


func save_server(server_name: String, address: String, port: int = SERVER_PORT) -> void:
	address = sanitize_address(address)
	if address.is_empty():
		return
	server_name = sanitize_nickname(server_name, address)
	var cfg := ConfigFile.new()
	cfg.load(SERVERS_CONFIG)
	var idx := 0
	while cfg.has_section("server_%d" % idx):
		if str(cfg.get_value("server_%d" % idx, "address", "")) == address:
			cfg.set_value("server_%d" % idx, "name", server_name)
			cfg.save(SERVERS_CONFIG)
			return
		idx += 1
	cfg.set_value("server_%d" % idx, "name", server_name)
	cfg.set_value("server_%d" % idx, "address", address)
	cfg.set_value("server_%d" % idx, "port", port)
	cfg.save(SERVERS_CONFIG)


func remove_server(address: String) -> void:
	address = sanitize_address(address)
	var cfg := ConfigFile.new()
	if cfg.load(SERVERS_CONFIG) != OK:
		return
	for section in cfg.get_sections():
		if section.begins_with("server_") and str(cfg.get_value(section, "address", "")) == address:
			cfg.erase_section(section)
	cfg.save(SERVERS_CONFIG)

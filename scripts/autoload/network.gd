# network stuff lobby and multiplayer and kills tracking
extends Node

signal player_connected(peer_id, player_info)
signal server_disconnected
signal connection_failed
signal lan_servers_changed(servers: Array)
signal leaderboard_changed
# new lobby signals
signal lobby_game_created(game_id: String, join_code: String, is_public: bool)
signal lobby_game_joined(game_id: String, join_code: String, peer_id: int, host_address: String, host_port: int, is_public: bool, max_players: int)
signal lobby_peer_connected(peer_id: int)
signal lobby_peer_disconnected(peer_id: int)
signal lobby_error(message: String)

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
# lobby server change this to your deployed url
const LOBBY_URL: String = "http://localhost:8080"
const LOBBY_HEARTBEAT_INTERVAL: float = 10.0
const LOBBY_GAME_TIMEOUT: float = 30.0

var players = {}
var player_info = {"nick": "host", "skin": Character.SkinColor.BLUE, "kills": 0}
var lan_servers: Array = []
var _session_active := false
var _discovery_socket: PacketPeerUDP = null
var _broadcast_socket: PacketPeerUDP = null
var _discovery_active := false
var _broadcast_active := false
var _broadcast_timer := 0.0
var _server_display_name := ""
var _lan_seen: Dictionary = {}
# lobby state
var _lobby_game_id: String = ""
var _lobby_join_code: String = ""
var _lobby_is_public := false
var _lobby_peer_id: int = 0
var _lobby_max_players: int = 0
var _lobby_heartbeat_timer := 0.0
var _lobby_http: HTTPRequest = null
var _lobby_pending_requests: Dictionary = {}


func _ready() -> void:
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.connected_to_server.connect(_on_connected_ok)

	# setup lobby HTTP client
	_lobby_http = HTTPRequest.new()
	add_child(_lobby_http)
	_lobby_http.request_completed.connect(_on_lobby_response)


func _process(delta: float) -> void:
	if _broadcast_active and multiplayer.is_server():
		_broadcast_timer += delta
		if _broadcast_timer >= DISCOVERY_INTERVAL:
			_broadcast_timer = 0.0
			_send_lan_broadcast()
	if _discovery_active and _discovery_socket:
		_poll_lan_discovery()
		_expire_lan_servers(delta)

	# lobby heartbeat
	if _lobby_game_id and multiplayer.is_server():
		_lobby_heartbeat_timer -= delta
		if _lobby_heartbeat_timer <= 0:
			_lobby_heartbeat_timer = LOBBY_HEARTBEAT_INTERVAL
			_lobby_send_heartbeat()


# host stuff creates server and lobby entry
func start_host(nickname: String, skin_color_str: String, is_public: bool = true, custom_code: String = ""):
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

	# register with lobby server
	_lobby_is_public = is_public
	_lobby_create_game(str(player_info["nick"]), is_public, custom_code)
	# report our local address so clients can connect directly
	var lan_ip := _local_lan_ip()
	if not lan_ip.is_empty() and lan_ip != SERVER_ADDRESS:
		_lobby_report_address(lan_ip, SERVER_PORT)


# join stuff connects client to host by ip or lobby
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
	# new players start at zero
	sanitized_info["kills"] = 0
	players[new_player_id] = sanitized_info
	player_connected.emit(new_player_id, sanitized_info)
	_sync_registered_player.rpc(new_player_id, sanitized_info)


# server tracks kills so clients can't change them
# kill tracking stuff only server changes kills
func register_kill(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id <= 0 or not players.has(peer_id):
		return
	var info: Dictionary = players[peer_id]
	info["kills"] = int(info.get("kills", 0)) + 1
	players[peer_id] = info
	sync_player_kills.rpc(peer_id, info["kills"])
	leaderboard_changed.emit()


@rpc("any_peer", "reliable")
func sync_player_kills(peer_id: int, kills: int) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		return
	if not players.has(peer_id):
		return
	var info: Dictionary = players[peer_id]
	info["kills"] = maxi(0, kills)
	players[peer_id] = info
	leaderboard_changed.emit()


func _on_player_disconnected(id):
	players.erase(id)


func _on_connection_failed():
	_finish_session()
	connection_failed.emit()


func _on_server_disconnected():
	_finish_session()


func leave_game() -> void:
	stop_lan_broadcast()
	stop_lan_discovery()
	var peer := multiplayer.multiplayer_peer
	if peer:
		peer.close()
	_finish_session()


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


func _finish_session() -> void:
	var had_session := _session_active or multiplayer.multiplayer_peer != null or not players.is_empty()
	_session_active = false
	multiplayer.multiplayer_peer = null
	players.clear()
	_lobby_game_id = ""
	_lobby_join_code = ""
	_lobby_is_public = false
	_lobby_peer_id = 0
	_lobby_max_players = 0
	if had_session:
		server_disconnected.emit()


# 
# lobby server integration
# 

func _lobby_create_game(host_name: String, is_public: bool, custom_code: String = "") -> void:
	var data = {
		"name": host_name,
		"host_name": host_name,
		"is_public": is_public,
		"max_players": MAX_PLAYERS,
		"host_port": SERVER_PORT,
	}
	if not custom_code.is_empty():
		data["custom_join_code"] = custom_code.strip_edges().to_upper()
	_lobby_post("/api/games", data, "create_game")


func join_by_code(join_code: String, nickname: String, skin_color_str: String) -> void:
	join_code = join_code.strip_edges().to_upper()
	if join_code.is_empty():
		connection_failed.emit()
		lobby_error.emit("Invalid join code")
		return

	var data = {
		"join_code": join_code,
		"player_name": sanitize_nickname(nickname, "Player"),
	}
	_lobby_post("/api/games/join", data, "join_game", {"skin": skin_color_str, "nickname": nickname})


func _lobby_join_game(skin_color_str: String, nickname: String, host_address: String = "", host_port: int = SERVER_PORT) -> void:
	# direct ENet connection to host (relay disabled for reliability)
	var target_address = host_address.strip_edges()
	if target_address.is_empty():
		target_address = SERVER_ADDRESS  # fallback to localhost for LAN
	var target_port = host_port if host_port > 0 else SERVER_PORT

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(target_address, target_port)
	if error:
		push_error("Failed to connect to host at %s:%d - error: %s" % [target_address, target_port, error])
		connection_failed.emit()
		lobby_error.emit("Failed to connect to host")
		return

	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	_session_active = true

	player_info["nick"] = sanitize_nickname(nickname, "Player_" + str(_lobby_peer_id))
	player_info["skin"] = skin_str_to_e(skin_color_str)


func _lobby_post(path: String, data: Dictionary, action: String, extra: Dictionary = {}) -> void:
	if not _lobby_http:
		return
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify(data)
	var request_id = str(Time.get_unix_time_from_system()) + "_" + str(randi())
	_lobby_pending_requests[request_id] = {"action": action, "extra": extra}
	_lobby_http.request(LOBBY_URL + path, headers, HTTPClient.METHOD_POST, body)


func _on_lobby_response(request_id: int, response_code: int, headers: Array, body: PackedByteArray) -> void:
	var key = str(request_id)
	if not _lobby_pending_requests.has(key):
		return
	var pending = _lobby_pending_requests[key]
	_lobby_pending_requests.erase(key)

	var response_text = body.get_string_from_utf8()
	var response: Dictionary = JSON.parse_string(response_text)
	if response_code < 200 or response_code >= 300:
		var msg = response.get("detail", "Request failed")
		connection_failed.emit()
		lobby_error.emit("%s: %s" % [pending.action, msg])
		return

	match pending.action:
		"create_game":
			_lobby_game_id = str(response.get("game_id", ""))
			_lobby_join_code = str(response.get("join_code", ""))
			_lobby_is_public = bool(response.get("is_public", false))
			_lobby_peer_id = 1
			_lobby_max_players = MAX_PLAYERS
			lobby_game_created.emit(_lobby_game_id, _lobby_join_code, _lobby_is_public)
			# start heartbeat
			_lobby_heartbeat_timer = LOBBY_HEARTBEAT_INTERVAL

		"join_game":
			_lobby_game_id = str(response.get("game_id", ""))
			_lobby_join_code = str(response.get("join_code", ""))
			_lobby_peer_id = int(response.get("peer_id", 0))
			var host_address = str(response.get("host_address", ""))
			var host_port = int(response.get("host_port", SERVER_PORT))
			var is_public = bool(response.get("is_public", false))
			var max_players = int(response.get("max_players", MAX_PLAYERS))
			_lobby_max_players = max_players
			_lobby_is_public = is_public

			# start join with lobby info (direct ENet to host)
			_lobby_join_game(str(pending.extra.get("skin", "blue")), str(pending.extra.get("nickname", "Player")), host_address, host_port)
			lobby_game_joined.emit(_lobby_game_id, _lobby_join_code, _lobby_peer_id, host_address, host_port, is_public, max_players)


func _lobby_send_heartbeat() -> void:
	if _lobby_game_id.is_empty() or not multiplayer.is_server():
		return
	var data = {"game_id": _lobby_game_id, "current_players": players.size()}
	_lobby_post("/api/games/heartbeat", data, "heartbeat")


func _lobby_report_address(address: String, port: int) -> void:
	if _lobby_game_id.is_empty():
		return
	var data = {"address": address, "port": port}
	_lobby_post("/api/games/%s/address" % _lobby_game_id, data, "report_address")


@rpc("any_peer", "reliable")
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
		"skin": sanitize_skin_value(info.get("skin", Character.SkinColor.BLUE)),
		"kills": maxi(0, int(info.get("kills", 0)))
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

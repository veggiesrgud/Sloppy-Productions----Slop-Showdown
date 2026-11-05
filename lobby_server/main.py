# lobby server - pure python no packages needed
# tracks hosted games so players can join by code
import json
import os
import random
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# games expire if host stops heartbeating (host sends every 10 sec)
GAMES_EXPIRE_SECONDS = 45.0
# join codes use these chars only (no confusing ones like O/0/I/1)
CODE_CHARS = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
CODE_LENGTH = 6
MAX_PLAYERS_LIMIT = 10

_games = {}
_lock = threading.Lock()
_peer_counter = 0


def make_code(length):
    chars = []
    for _ in range(length):
        chars.append(random.choice(CODE_CHARS))
    return "".join(chars)


def clean_custom_code(raw):
    # custom codes become uppercase letters and numbers
    code = str(raw).strip().upper()
    if not code:
        return ""
    allowed = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    clean = ""
    for ch in code:
        if ch in allowed:
            clean += ch
    if len(clean) < 3 or len(clean) > 8:
        return ""
    return clean


def find_game(game_id=None, join_code=None):
    # must be called with the lock held
    now = time.monotonic()
    for game_id_to_check in list(_games):
        if now - _games[game_id_to_check]["last_seen"] > GAMES_EXPIRE_SECONDS:
            del _games[game_id_to_check]
    if game_id:
        return _games.get(game_id)
    if join_code:
        code = str(join_code).strip().upper()
        for game in _games.values():
            if game["join_code"] == code:
                return game
    return None


class Handler(BaseHTTPRequestHandler):
    server_version = "SlopLobby/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        # quiet logs
        return

    def send_json(self, status, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        raw_len = self.headers.get("Content-Length", 0)
        try:
            raw_len = int(raw_len)
        except (TypeError, ValueError):
            raw_len = 0
        if raw_len <= 0:
            return {}
        raw = self.rfile.read(raw_len)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}
        return data if isinstance(data, dict) else {}

    # ---- pages ----

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/" or path == "":
            self.send_json(200, {"ok": True, "service": "slop lobby"})
            return
        if path == "/favicon.ico":
            self.send_json(200, {"ok": True})
            return
        if path == "/api/games":
            self.list_games()
            return
        self.send_json(404, {"detail": "Not found"})

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/games":
            self.create_game()
            return
        if path == "/api/games/join":
            self.join_game()
            return
        if path == "/api/games/heartbeat":
            self.heartbeat(parsed)
            return
        # /api/games/{game_id}/address
        if path.startswith("/api/games/") and path.endswith("/address"):
            game_id = path[len("/api/games/"):-len("/address")]
            self.report_address(urllib.parse.unquote(game_id))
            return
        if path.startswith("/ws/relay/"):
            # relay disabled game clients connect direct to host
            self.send_json(400, {"detail": "Relay disabled, clients connect direct"})
            return
        self.send_json(404, {"detail": "Not found"})

    # ---- endpoints ----

    def list_games(self):
        with _lock:
            now = time.monotonic()
            for game_id in list(_games):
                if now - _games[game_id]["last_seen"] > GAMES_EXPIRE_SECONDS:
                    del _games[game_id]
            out = []
            for game in _games.values():
                if not game["is_public"]:
                    continue
                out.append({
                    "name": game["name"],
                    "join_code": game["join_code"],
                    "players": game["current_players"],
                    "max_players": game["max_players"],
                })
        self.send_json(200, {"games": out})

    def create_game(self):
        data = self.read_json()
        is_public = bool(data.get("is_public", True))
        try:
            max_players = int(data.get("max_players", MAX_PLAYERS_LIMIT))
        except (TypeError, ValueError):
            max_players = MAX_PLAYERS_LIMIT
        max_players = max(1, min(max_players, MAX_PLAYERS_LIMIT))
        try:
            host_port = int(data.get("host_port", 8080))
        except (TypeError, ValueError):
            host_port = 8080
        host_address = str(data.get("host_address", "")).strip()[:253]
        name = str(data.get("name", "")).strip()[:24] or "Slop Server"

        with _lock:
            # custom code wins if free otherwise generate one
            code = clean_custom_code(data.get("custom_join_code", ""))
            if code:
                for game in _games.values():
                    if game["join_code"] == code:
                        self.send_json(409, {"detail": "Code already in use"})
                        return
            else:
                code = make_code(CODE_LENGTH)
                while any(g["join_code"] == code for g in _games.values()):
                    code = make_code(CODE_LENGTH)

            game_id = "%d" % (time.monotonic_ns())
            _games[game_id] = {
                "game_id": game_id,
                "name": name,
                "join_code": code,
                "is_public": is_public,
                "max_players": max_players,
                "host_port": host_port,
                "address": host_address,
                "current_players": 1,
                "last_seen": time.monotonic(),
            }
            response = {
                "game_id": game_id,
                "join_code": code,
                "is_public": is_public,
            }
        self.send_json(200, response)

    def join_game(self):
        global _peer_counter
        data = self.read_json()
        join_code = str(data.get("join_code", ""))
        with _lock:
            game = find_game(join_code=join_code)
            if game is None:
                self.send_json(404, {"detail": "Game not found"})
                return
            if game["current_players"] >= game["max_players"]:
                self.send_json(400, {"detail": "Game full"})
                return
            _peer_counter += 1
            peer_id = 1000 + _peer_counter
            game["current_players"] += 1
            game["last_seen"] = time.monotonic()
            response = {
                "game_id": game["game_id"],
                "join_code": game["join_code"],
                "peer_id": peer_id,
                "host_address": game["address"],
                "host_port": game["host_port"],
                "is_public": game["is_public"],
                "max_players": game["max_players"],
            }
        self.send_json(200, response)

    def heartbeat(self, parsed):
        data = self.read_json()
        game_id = str(data.get("game_id", "") or urllib.parse.parse_qs(parsed.query).get("game_id", [""])[0])
        try:
            current_players = int(data.get("current_players", -1))
        except (TypeError, ValueError):
            current_players = -1
        with _lock:
            if game_id:
                game = find_game(game_id=game_id)
                if game is not None:
                    game["last_seen"] = time.monotonic()
                    if current_players >= 0:
                        game["current_players"] = current_players
            # no game_id still ok so client never errors
        self.send_json(200, {"ok": True})

    def report_address(self, game_id):
        data = self.read_json()
        address = str(data.get("address", "")).strip()[:253]
        try:
            port = int(data.get("port", 8080))
        except (TypeError, ValueError):
            port = 8080
        with _lock:
            game = find_game(game_id=game_id)
            if game is None:
                self.send_json(404, {"detail": "Game not found"})
                return
            game["address"] = address
            game["host_port"] = port
            game["last_seen"] = time.monotonic()
        self.send_json(200, {"ok": True})


def main():
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print("lobby server running on port %d" % port)
    print("open http://localhost:%d in a browser to check it lives" % port)
    print("ctrl+c to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("lobby server stopped")


if __name__ == "__main__":
    main()

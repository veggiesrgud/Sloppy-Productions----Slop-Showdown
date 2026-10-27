"""
Sloppy Showdown Lobby Server
FastAPI + WebSocket relay for internet multiplayer.
Deploy to Railway, Render, Fly.io, or any Python host.
"""

import asyncio
import json
import random
import string
import time
import uuid
from collections import defaultdict
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field


# =============================================================================
# Data Models
# =============================================================================

@dataclass
class GameInfo:
    game_id: str
    join_code: str
    name: str
    host_name: str
    host_peer_id: int
    is_public: bool
    max_players: int
    current_players: int = 1
    created_at: float = field(default_factory=time.time)
    last_heartbeat: float = field(default_factory=time.time)
    # For relay mode: map of peer_id -> WebSocket
    peer_connections: Dict[int, WebSocket] = field(default_factory=dict)
    # For direct mode: host's public IP/port (if known)
    host_address: Optional[str] = None
    host_port: int = 8080


@dataclass
class PeerConnection:
    game_id: str
    peer_id: int
    websocket: WebSocket
    is_host: bool = False


class CreateGameRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=50)
    host_name: str = Field(..., min_length=1, max_length=24)
    is_public: bool = True
    max_players: int = Field(10, ge=2, max=16)
    host_port: int = Field(8080, ge=1, le=65535)
    custom_join_code: Optional[str] = Field(None, min_length=3, max_length=12, pattern=r"^[A-Z0-9]+$")


class CreateGameResponse(BaseModel):
    game_id: str
    join_code: str
    is_public: bool


class JoinGameRequest(BaseModel):
    join_code: str
    player_name: str = Field(..., min_length=1, max_length=24)


class GameListResponse(BaseModel):
    games: List[dict]


class HeartbeatRequest(BaseModel):
    game_id: str
    current_players: int


# =============================================================================
# Global State
# =============================================================================

games: Dict[str, GameInfo] = {}  # game_id -> GameInfo
join_code_to_game: Dict[str, str] = {}  # join_code -> game_id
peer_connections: Dict[str, PeerConnection] = {}  # connection_id -> PeerConnection
# For relay: connection_id is "game_id:peer_id"


def generate_join_code() -> str:
    """Generate a 6-character join code (uppercase alphanumeric, no ambiguous chars)."""
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    return "".join(random.choices(alphabet, k=6))


def generate_game_id() -> str:
    return uuid.uuid4().hex[:12]


def cleanup_expired_games():
    """Remove games that haven't sent heartbeat in 30 seconds."""
    now = time.time()
    expired = [
        gid for gid, g in games.items()
        if now - g.last_heartbeat > 30
    ]
    for gid in expired:
        g = games.pop(gid, None)
        if g and g.join_code in join_code_to_game:
            join_code_to_game.pop(g.join_code, None)
        # Clean up peer connections
        to_remove = [cid for cid, pc in peer_connections.items() if pc.game_id == gid]
        for cid in to_remove:
            peer_connections.pop(cid, None)


# =============================================================================
# FastAPI App
# =============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: periodic cleanup
    async def cleanup_loop():
        while True:
            await asyncio.sleep(10)
            cleanup_expired_games()
    task = asyncio.create_task(cleanup_loop())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


app = FastAPI(title="Sloppy Showdown Lobby", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# =============================================================================
# REST Endpoints
# =============================================================================

@app.get("/health")
async def health():
    return {"status": "ok", "games": len(games), "connections": len(peer_connections)}


@app.post("/api/games", response_model=CreateGameResponse)
async def create_game(req: CreateGameRequest, request: Request):
    game_id = generate_game_id()
    
    # Use custom join code if provided, otherwise generate one
    if req.custom_join_code:
        join_code = req.custom_join_code.upper()
        if join_code in join_code_to_game:
            raise HTTPException(status_code=400, detail="Join code already in use")
    else:
        join_code = generate_join_code()
        while join_code in join_code_to_game:
            join_code = generate_join_code()

    game = GameInfo(
        game_id=game_id,
        join_code=join_code,
        name=req.name[:50],
        host_name=req.host_name[:24],
        host_peer_id=1,
        is_public=req.is_public,
        max_players=req.max_players,
        host_port=req.host_port,
    )
    games[game_id] = game
    join_code_to_game[join_code] = game_id

    return CreateGameResponse(game_id=game_id, join_code=join_code, is_public=req.is_public)


@app.post("/api/games/join")
async def join_game(req: JoinGameRequest):
    game_id = join_code_to_game.get(req.join_code.upper())
    if not game_id or game_id not in games:
        raise HTTPException(status_code=404, detail="Game not found")

    game = games[game_id]
    if game.current_players >= game.max_players:
        raise HTTPException(status_code=400, detail="Game is full")

    # Assign next available peer ID
    peer_id = game.current_players + 1
    game.current_players = peer_id

    return {
        "game_id": game.game_id,
        "join_code": game.join_code,
        "peer_id": peer_id,
        "host_name": game.host_name,
        "host_address": game.host_address,
        "host_port": game.host_port,
        "is_public": game.is_public,
        "max_players": game.max_players,
        "relay_url": f"/ws/relay/{game_id}/{peer_id}",
    }


@app.get("/api/games", response_model=GameListResponse)
async def list_games():
    cleanup_expired_games()
    public_games = [
        {
            "game_id": g.game_id,
            "join_code": g.join_code,
            "name": g.name,
            "host_name": g.host_name,
            "current_players": g.current_players,
            "max_players": g.max_players,
            "is_public": g.is_public,
        }
        for g in games.values()
        if g.is_public
    ]
    return GameListResponse(games=public_games)


@app.post("/api/games/heartbeat")
async def heartbeat(req: HeartbeatRequest):
    game = games.get(req.game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    game.last_heartbeat = time.time()
    game.current_players = req.current_players
    return {"ok": True}


@app.post("/api/games/{game_id}/address")
async def update_host_address(game_id: str, request: Request):
    """Host reports its public address for direct connect fallback."""
    game = games.get(game_id)
    if not game:
        raise HTTPException(status_code=404, detail="Game not found")
    data = await request.json()
    game.host_address = data.get("address")
    game.host_port = data.get("port", 8080)
    return {"ok": True}


# =============================================================================
# WebSocket Relay
# =============================================================================

@app.websocket("/ws/relay/{game_id}/{peer_id}")
async def relay_websocket(websocket: WebSocket, game_id: str, peer_id: int):
    await websocket.accept()

    game = games.get(game_id)
    if not game:
        await websocket.close(code=4004, reason="Game not found")
        return

    if peer_id > game.max_players:
        await websocket.close(code=4003, reason="Invalid peer ID")
        return

    connection_id = f"{game_id}:{peer_id}"
    is_host = (peer_id == 1)

    # Register connection
    peer_conn = PeerConnection(
        game_id=game_id,
        peer_id=peer_id,
        websocket=websocket,
        is_host=is_host,
    )
    peer_connections[connection_id] = peer_conn
    game.peer_connections[peer_id] = websocket

    # Notify others in game
    await broadcast_to_game(game_id, {
        "type": "peer_connected",
        "peer_id": peer_id,
        "is_host": is_host,
    }, exclude=peer_id)

    # Send current peer list to new connection
    peers_info = [
        {"peer_id": pid, "is_host": pid == 1}
        for pid in game.peer_connections.keys()
    ]
    await websocket.send_json({
        "type": "peers_list",
        "peers": peers_info,
        "your_peer_id": peer_id,
    })

    try:
        while True:
            data = await websocket.receive_bytes()
            # Relay to all other peers in the game
            await broadcast_to_game(game_id, data, exclude=peer_id, binary=True)
    except WebSocketDisconnect:
        pass
    finally:
        # Cleanup
        peer_connections.pop(connection_id, None)
        game.peer_connections.pop(peer_id, None)

        # Notify others
        await broadcast_to_game(game_id, {
            "type": "peer_disconnected",
            "peer_id": peer_id,
        })

        # If host left, clean up game after a delay
        if is_host:
            await asyncio.sleep(5)
            if game_id in games:
                g = games[game_id]
                if not g.peer_connections:  # No one else connected
                    games.pop(game_id, None)
                    join_code_to_game.pop(g.join_code, None)


async def broadcast_to_game(game_id: str, message, exclude: int = None, binary: bool = False):
    game = games.get(game_id)
    if not game:
        return
    for pid, ws in list(game.peer_connections.items()):
        if pid == exclude:
            continue
        try:
            if binary:
                await ws.send_bytes(message)
            else:
                await ws.send_json(message)
        except Exception:
            # Connection likely dead, will be cleaned up on disconnect
            pass


# =============================================================================
# Run
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
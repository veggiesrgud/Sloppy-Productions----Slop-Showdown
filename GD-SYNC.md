gd-sync is installed and enabled

what's done
- plugin installed at addons/GD-Sync (from github.com/GD-Sync/GD-Sync v1.0.2)
- plugin enabled in project.godot ([editor_plugins] enabled=PackedStringArray("GD-Sync"))
- GDSync autoload registered in project.godot (res://addons/GD-Sync/MultiplayerClient.gd)
- game connects to GDSync on the modes screen and shows a small status label ("GD-Sync: connecting..." / "online" / "offline") - it does not crash if no keys are set
- ENUMS and all GD-Sync classes are registered in global_script_class_cache.cfg

what you still need to do for online features
1. go to https://www.gd-sync.com/app/create-database
2. create a database (plain letters name)
3. go to API Keys -> generate a public key and a private key
4. open the godot editor -> project -> tools -> GD-Sync -> paste both keys
5. run the game - it will say "GD-Sync: online" in the corner

local mode (no keys)
you can call GDSync.start_local_multiplayer() instead of start_multiplayer() to test lobbies on the same network without any account.

for internet multiplayer
install the plugin (done), configure keys, and then either:
- keep your direct LAN ENet networking as-is (works without gd-sync), or
- rebuild lobbies/matchmaking on top of GDSync.lobbies + GDSync.remote_call

note: GD-Sync is peer-to-peer, gameplay runs locally/on host, so casual games are fine but competitive PvP should use an authoritative server.
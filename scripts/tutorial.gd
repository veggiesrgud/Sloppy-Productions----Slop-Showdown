extends "res://scripts/level/level.gd"

func _ready() -> void:
	super._ready()
	# add trimesh collision to the tutorial map meshes
	var map = get_node_or_null("Environment/Map")
	if map:
		_add_trimesh(map)
	# auto host so the player spawns right away
	Network.start_host("Player", "blue")

func get_spawn_point(_id: int) -> Vector3:
	# spawn above the map so gravity lands the player on it
	return Vector3(0, 27, 7)

func _add_trimesh(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh = (child as MeshInstance3D).mesh
			if mesh:
				var body = StaticBody3D.new()
				var shape = CollisionShape3D.new()
				var concave = mesh.create_trimesh_shape()
				if concave:
					shape.shape = concave
					body.add_child(shape)
					child.add_child(body)
		_add_trimesh(child)
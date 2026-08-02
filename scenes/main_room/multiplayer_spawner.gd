extends MultiplayerSpawner

@export var network_player: PackedScene

func _ready() -> void:
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		# Spawn host (id = 1)
		_spawn_player_for_id(1)

func _on_peer_connected(id: int) -> void:
	_spawn_player_for_id(id)

func _spawn_player_for_id(id: int) -> void:
	if not multiplayer.is_server():
		return

	# Chờ 1 frame để Map/Lobby load hoàn tất trên SceneContainer
	await get_tree().process_frame

	# 1. Host chọn trước vị trí Spawn từ Marker2D
	var spawn_pos := _get_random_spawn_position()

	# 2. Tạo Player trên Host
	var player = network_player.instantiate()
	player.name = str(id)

	var target_node = get_node_or_null(spawn_path)
	if target_node:
		target_node.add_child(player, true)
		player.global_position = spawn_pos
		player.set_multiplayer_authority(id)
		PlayerManager.register_player_node(id, player)

		# 3. Đồng bộ tọa độ chính xác này sang cho toàn bộ Client
		rpc("set_player_position", str(id), spawn_pos)

@rpc("call_local", "reliable")
func set_player_position(player_name: String, pos: Vector2) -> void:
	var target_node = get_node_or_null(spawn_path)
	if target_node:
		var player_node = target_node.get_node_or_null(player_name)
		if player_node:
			player_node.global_position = pos

## Lấy ngẫu nhiên vị trí Marker2D trong Lobby/Gameplay Scene
func _get_random_spawn_position() -> Vector2:
	var scene_container = get_node_or_null("../World/SceneContainer")
	if not scene_container or scene_container.get_child_count() == 0:
		return Vector2.ZERO
		
	var current_map = scene_container.get_child(0)
	var spawn_points: Array[Marker2D] = []
	
	_find_markers_recursive(current_map, spawn_points)
	
	if spawn_points.size() > 0:
		var random_marker = spawn_points.pick_random()
		return random_marker.global_position
		
	return Vector2.ZERO

func _find_markers_recursive(node: Node, result: Array[Marker2D]) -> void:
	if node is Marker2D:
		result.append(node)
	for child in node.get_children():
		_find_markers_recursive(child, result)

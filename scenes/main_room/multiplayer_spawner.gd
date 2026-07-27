extends MultiplayerSpawner

@export var network_player: PackedScene

func _ready():
	multiplayer.peer_connected.connect(spawn_player)
	if multiplayer.is_server():
		spawn_player(1)

func spawn_player(id: int):
	if not multiplayer.is_server():
		return
	var player = network_player.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id) #assigns ID
	
	get_node(spawn_path).call_deferred("add_child", player)
	PlayerManager.register_player_node(id, player) #Track to despawn players

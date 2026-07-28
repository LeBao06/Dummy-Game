extends Node

# Signals for UI (Lobby/Gameplay) to listen to
signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal connection_failed
signal connection_succeeded


func _ready() -> void:
	# Connect Godot's built-in multiplayer connection events
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ==========================================
# --- NETWORK SETUP ---
# ==========================================

## Hosts a new game server
func create_game(p_room_name: String = "Default Room") -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(Constants.PORT, Constants.MAX_CONNECTIONS)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	
	RoomDiscoveryManager.start_broadcasting(p_room_name)
	
	# Since the Host is also a player, register the host locally immediately
	PlayerManager.register_player(Constants.HOST_ID, PlayerManager.get_local_network_data())
	player_connected.emit(Constants.HOST_ID, PlayerManager.get_local_network_data())
	return OK

## Joins an existing game server using an IP address
func join_game(address: String = "") -> Error:
	if address.is_empty():
		address = Constants.DEFAULT_SERVER_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, Constants.PORT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	RoomDiscoveryManager.stop_searching()
	return OK

## Cleans up the network peer and resets managers
func remove_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	PlayerManager.reset_manager()
	RoomDiscoveryManager.reset()


# ==========================================
# --- RPC DATA SYNCHRONIZATION ---
# ==========================================

## RPC function used by clients to send their own data to everyone else
@rpc("any_peer", "reliable")
func _register_player_rpc(player_info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	PlayerManager.register_player(sender_id, player_info)
	player_connected.emit(sender_id, player_info)
	
	# Relay the new player to every other already-connected client
	for id in PlayerManager.players_state.keys():
		if id == sender_id or id == 1:
			continue
		_sync_existing_player_rpc.rpc_id(id, sender_id, player_info)

## RPC function used ONLY by the Server to introduce an existing player
## to a newly-connected peer (sender_id can't be trusted here, so we pass the id explicitly)
@rpc("authority", "call_remote", "reliable")
func _sync_existing_player_rpc(peer_id: int, player_info: Dictionary) -> void:
	PlayerManager.register_player(peer_id, player_info)
	player_connected.emit(peer_id, player_info)


# ==========================================
# --- SYSTEM MULTIPLAYER CALLBACKS ---
# ==========================================

## Triggered on EVERY machine when a new peer successfully connects
func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	
	for existing_id in PlayerManager.players_state.keys():
		if existing_id == id:
			continue
		var existing_data = PlayerManager.players_state[existing_id]
		_sync_existing_player_rpc.rpc_id(id, existing_id, existing_data)

## Triggered when a peer disconnects from the session
func _on_peer_disconnected(id: int) -> void:
	PlayerManager.unregister_player(id)
	player_disconnected.emit(id)

## Triggered ONLY on the CLIENT when successfully connected to the Server
func _on_connected_ok() -> void:
	var local_id = multiplayer.get_unique_id()
	var my_data = PlayerManager.get_local_network_data()
	
	# Register self locally
	PlayerManager.register_player(local_id, my_data)
	player_connected.emit(local_id, my_data)
	
	# Send self data to the Server and other peers
	_register_player_rpc.rpc(my_data)
	
	connection_succeeded.emit()

## Triggered ONLY on the CLIENT when connection attempt fails
func _on_connected_fail() -> void:
	remove_multiplayer_peer()
	connection_failed.emit()

## Triggered ONLY on the CLIENT when the SERVER disconnects or shuts down
func _on_server_disconnected() -> void:
	remove_multiplayer_peer()
	server_disconnected.emit()

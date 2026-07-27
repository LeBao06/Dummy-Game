extends Node
@warning_ignore("UNUSED_SIGNAL")
signal role_assigned(role: Enums.Role)
signal players_state_updated


# Local player's data (the player sitting in front of this screen)
var local_player_data: Dictionary = {
	"name": "Player",
	"role": Enums.Role.CREWMATE, # Default role, will be assigned when the game starts
	"is_alive": true,
	"assigned_tasks": [],
	"done_tasks": []
}

# Dictionary storing the game state/metadata of all players in the lobby/game
# Structure: { peer_id (int): player_data (Dictionary) }
var players_state: Dictionary = {}

# Dictionary tracking the actual spawned in-game node per player, so we can
# clean it up on disconnect. Structure: { peer_id (int): Node }
var players_nodes: Dictionary = {}

## Returns the clean data package of the local player to be sent over the network
func get_local_network_data() -> Dictionary:
	return {
		"name": local_player_data["name"],
		"role": local_player_data["role"],
		"is_alive": local_player_data["is_alive"],
		"assigned_tasks": local_player_data["assigned_tasks"],
		"done_tasks": local_player_data["done_tasks"]
	}

## Registers or updates a player's data in the global state
func register_player(peer_id: int, player_data: Dictionary) -> void:
	players_state[peer_id] = player_data

## Deletes the disconnected player's node from the scene tree, if it exists
func despawn_player_node(peer_id: int) -> void:
	if players_nodes.has(peer_id):
		var node = players_nodes[peer_id]
		if is_instance_valid(node):
			node.queue_free()
		players_nodes.erase(peer_id)

## Removes a player from the active state (e.g., when they disconnect)
func unregister_player(peer_id: int) -> void:
	if players_state.has(peer_id):
		players_state.erase(peer_id)
	despawn_player_node(peer_id)
	players_state_updated.emit()

## Call this wherever you instantiate a player's in-game scene (player.tscn)
## so player_manager knows which node belongs to which peer.
func register_player_node(peer_id: int, node: Node) -> void:
	players_nodes[peer_id] = node
	
## Sets the ready flag for a given peer in players_state. Pure data write —
## no networking. Server calls this directly; RPCs handle replication separately.
func set_ready_state(peer_id: int, is_ready: bool) -> void:
	if players_state.has(peer_id):
		players_state[peer_id]["ready"] = is_ready

## Resets all player states to default (useful when leaving a game)
func reset_manager() -> void:
	players_state.clear()
	local_player_data["role"] = Enums.Role.CREWMATE
	local_player_data["is_alive"] = true
	local_player_data["assigned_tasks"] = []
	local_player_data["done_tasks"] = []

func get_player_count() -> int:
	return players_state.size()

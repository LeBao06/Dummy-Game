extends Node

# ==========================================
# PLAYER MANAGER
# Single source of truth for players_state. Other managers should not
# write to players_state[id][...] directly — use the setters below so
# state changes stay in one place and can be extended (validation,
# signals, etc.) without hunting through every manager that touches data.
# ==========================================

signal role_assigned(role: Enums.Role)
signal players_state_updated


# Local player's data (the player sitting in front of this screen)
var local_player_data: Dictionary = {
	"name": "Player",
	"role": Enums.Role.CREWMATE, # Default role, will be assigned when the game starts
	"is_alive": true,
	"is_ready": false,
	"assigned_tasks": [],
	"done_tasks": []
}

# Dictionary storing the game state/metadata of all players in the lobby/game
# Structure: { peer_id (int): player_data (Dictionary) }
var players_state: Dictionary = {}

# Dictionary tracking the actual spawned in-game node per player, so we can
# clean it up on disconnect. Structure: { peer_id (int): Node }
var players_nodes: Dictionary = {}


## Registers or updates a player's data in the global state
func register_player(peer_id: int, player_data: Dictionary) -> void:
	players_state[peer_id] = player_data
	players_state_updated.emit()


## Call this wherever you instantiate a player's in-game scene (player.tscn)
## so player_manager knows which node belongs to which peer.
func register_player_node(peer_id: int, node: Node) -> void:
	players_nodes[peer_id] = node


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


## Full reset — clears the entire roster. Use only when actually leaving
## a game (returning to main menu, host shutting down). Do NOT use this
## to reset per-round data at the start of a new match — that would wipe
## every connected player, not just their match state. Use
## reset_players_for_new_round() for that instead.
func reset_manager() -> void:
	players_state.clear()
	local_player_data["role"] = Enums.Role.CREWMATE
	local_player_data["is_alive"] = true
	local_player_data["is_ready"] = false
	local_player_data["assigned_tasks"] = []
	local_player_data["done_tasks"] = []


## Resets per-round fields (is_alive, assigned_tasks, done_tasks) for every
## currently connected player, WITHOUT removing them from players_state.
## Call this at the start of a new match instead of reset_manager(), so
## connected players don't get erased right before roles/tasks are assigned.
func reset_players_for_new_round() -> void:
	for id in players_state.keys():
		players_state[id]["is_alive"] = true
		players_state[id]["assigned_tasks"] = []
		players_state[id]["done_tasks"] = []
	players_state_updated.emit()


func all_players_ready() -> bool:
	return players_state.size() > 0 and players_state.values().all(
		func(p): return p.get("is_ready", false)
	);


# ==========================================
# --- SETTERS ---
# All writes to a player's entry in players_state should go through
# here instead of managers reaching into players_state[id][...] directly.
# ==========================================

## Sets the ready flag for a given peer in players_state. Pure data write —
## no networking. Server calls this directly; RPCs handle replication separately.
func set_ready_state(peer_id: int, is_ready: bool) -> void:
	if players_state.has(peer_id):
		players_state[peer_id]["is_ready"] = is_ready
		players_state_updated.emit()


## Sets a player's role (CREWMATE / IMPOSTOR). Server-authoritative call only.
func set_role(peer_id: int, role: Enums.Role) -> void:
	if players_state.has(peer_id):
		players_state[peer_id]["role"] = role
		role_assigned.emit()


## Sets a player's alive/dead flag (ejection, kill, etc.).
func set_alive(peer_id: int, is_alive: bool) -> void:
	if players_state.has(peer_id):
		players_state[peer_id]["is_alive"] = is_alive
		players_state_updated.emit()


## Overwrites a player's full assigned task list (used at match start).
func set_assigned_tasks(peer_id: int, task_ids: Array) -> void:
	if players_state.has(peer_id):
		players_state[peer_id]["assigned_tasks"] = task_ids
		players_state_updated.emit()


## Marks a single task as done for a player, avoiding duplicate entries.
## Returns false if the peer doesn't exist or the task was already done,
## so callers (e.g. ServerManager) can skip re-broadcasting completion.
func add_done_task(peer_id: int, task_id: String) -> bool:
	if not players_state.has(peer_id):
		return false
	var done: Array = players_state[peer_id].get("done_tasks", [])
	if task_id in done:
		return false
	done.append(task_id)
	players_state[peer_id]["done_tasks"] = done
	players_state_updated.emit()
	return true


# ==========================================
# --- GETTERS ---
# ==========================================

## Returns the clean data package of the local player to be sent over the network
func get_local_network_data() -> Dictionary:
	return {
		"name": local_player_data["name"],
		"role": local_player_data["role"],
		"is_alive": local_player_data["is_alive"],
		"is_ready": local_player_data["is_ready"],
		"assigned_tasks": local_player_data["assigned_tasks"],
		"done_tasks": local_player_data["done_tasks"]
	}


func get_player_count() -> int:
	return players_state.size()


## Returns a player's full data dict, or an empty dict if they don't exist.
## Prefer this (or a more specific getter below) over reaching into
## players_state directly from other managers.
func get_player_data(peer_id: int) -> Dictionary:
	return players_state.get(peer_id, {})


func get_role(peer_id: int) -> Enums.Role:
	return players_state.get(peer_id, {}).get("role", Enums.Role.CREWMATE)


func is_player_alive(peer_id: int) -> bool:
	return players_state.get(peer_id, {}).get("is_alive", false)

func is_player_ready(peer_id: int) -> bool:
	return players_state.get(peer_id, {}).get("is_ready", false)

func get_assigned_tasks(peer_id: int) -> Array:
	return players_state.get(peer_id, {}).get("assigned_tasks", [])


func get_done_tasks(peer_id: int) -> Array:
	return players_state.get(peer_id, {}).get("done_tasks", [])


# ==========================================
# --- ALIVE / ROLE QUERY HELPERS ---
# Centralized here so VoteManager and GameManager don't each maintain
# their own copy of this counting logic (previously duplicated in
# VoteManager as _get_alive_player_ids / _count_alive_impostors /
# _count_alive_crewmates).
# ==========================================

func get_alive_player_ids() -> Array:
	var alive: Array = []
	for id in players_state.keys():
		if players_state[id].get("is_alive", false):
			alive.append(id)
	return alive


## Counts alive players with a given role. Pass Enums.Role.IMPOSTOR or
## Enums.Role.CREWMATE to get the counts VoteManager/GameManager need
## for win-condition checks.
func count_alive_by_role(role: Enums.Role) -> int:
	var count := 0
	for id in players_state.keys():
		var data = players_state[id]
		if data.get("is_alive", false) and data.get("role") == role:
			count += 1
	return count

extends Node

# Number of Impostors (configurable by the Host in the Lobby)
var num_impostors: int = 1
# Number of tasks assigned to each Crewmate per match
var tasks_per_crewmate: int = 2

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	PlayerManager.unregister_player(peer_id)
	_sync_players_state(PlayerManager.players_state)

# Emits signal whenever a player left, run _on_peer_disconnected
func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# ==========================================
# READY STATE (LOBBY)
# ==========================================

##
func request_local_ready(is_ready:bool) -> void:
	var my_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		_apply_ready(my_id, is_ready)
	else:
		_request_set_ready.rpc_id(1, my_id, is_ready)
# ==========================================
# MATCH (MAIN LOOP)
# ==========================================

func start_match() -> void:
	if not multiplayer.is_server():
		return
	
	var player_ids = PlayerManager.players_state.keys()
	
	# Guard: need at least 2 players, and impostors can't outnumber/match crewmates
	if player_ids.size() < 2:
		push_warning("[ServerManager] Not enough players to start a match.")
		return
	num_impostors = clamp(num_impostors, 1, player_ids.size() - 1)
	
	_reset_match_state(player_ids)
	assign_roles(player_ids)
	assign_tasks(player_ids)
	
## Clears any leftover per-player match data from a previous round
func _reset_match_state(player_ids: Array) -> void:
	for id in player_ids:
		PlayerManager.players_state[id]["assigned_tasks"] = []
		PlayerManager.players_state[id]["done_tasks"] = []
		PlayerManager.players_state[id]["is_alive"] = true
	# Delegate to TaskManager's own reset instead of reaching into its fields
	# directly, so this stays in sync if TaskManager's reset logic ever changes.
	TaskManager.reset_manager()


# ==========================================
# ROLE ASSIGNMENT LOGIC (using Enums & network optimization)
# ==========================================

func assign_roles(player_ids: Array = PlayerManager.players_state.keys()) -> void:
	player_ids.shuffle() # Shuffle the player list
	
	for i in range(player_ids.size()):
		var id = player_ids[i]
		# Use an Enum instead of a raw String
		var assigned_role: Enums.Role = Enums.Role.CREWMATE
		
		if i < num_impostors:
			assigned_role = Enums.Role.IMPOSTOR
		
		# 1. Update the state on the Server
		PlayerManager.players_state[id]["role"] = assigned_role
		
		# 2. Send the Role to the Client. The Host handles it directly,
		#    no need for an RPC to itself.
		if id == Constants.HOST_ID:
			receive_role(assigned_role)
		else:
			rpc_id(id, "receive_role", assigned_role)


# ==========================================
# TASK ASSIGNMENT LOGIC (integrated with TaskManager, only sends Task IDs)
# ==========================================

func assign_tasks(player_ids: Array = PlayerManager.players_state.keys()) -> void:
	var crewmate_count := 0
	for id in player_ids:
		if PlayerManager.players_state[id]["role"] == Enums.Role.CREWMATE:
			crewmate_count += 1
		
	# Total number of tasks to complete this match (used for the progress bar)
	TaskManager.total_tasks_count = crewmate_count * tasks_per_crewmate

	for id in player_ids:
		var role = PlayerManager.players_state[id]["role"]
		var assigned_task_ids: Array[String] = []
		
		if role == Enums.Role.CREWMATE:
			# Pick random task IDs from TaskManager
			assigned_task_ids = TaskManager.get_random_task_ids(tasks_per_crewmate)
		else:
			# Impostors get fake task IDs (or their own dedicated fake task list)
			assigned_task_ids = ["fake_task_1"]
		
		# Update the player's task list in ServerManager's authoritative state
		PlayerManager.players_state[id]["assigned_tasks"] = assigned_task_ids
		
		# ONLY SEND THE ID LIST OVER THE NETWORK (great bandwidth optimization!)
		if id == Constants.HOST_ID:
			receive_task_list(assigned_task_ids)
		else:
			rpc_id(id, "receive_task_list", assigned_task_ids)


# ==========================================
# CLIENT -> SERVER: TASK COMPLETION
# ==========================================

## Called by a client (any_peer) requesting to mark one of ITS tasks as done.
## Server validates ownership + prevents duplicate completion before trusting it.
@rpc("any_peer", "call_remote", "reliable")
func request_complete_task(task_id: String) -> void:
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	_try_complete_task(sender_id, task_id)


## Host-local equivalent of request_complete_task, call this directly from
## host-side gameplay code instead of RPC-ing to itself.
func complete_task_as_host(task_id: String) -> void:
	if not multiplayer.is_server():
		return
	_try_complete_task(Constants.HOST_ID, task_id)


func _try_complete_task(player_id: int, task_id: String) -> void:
	if not PlayerManager.players_state.has(player_id):
		return
	
	var player_data: Dictionary = PlayerManager.players_state[player_id]
	var assigned: Array = player_data.get("assigned_tasks", [])
	var done: Array = player_data.get("done_tasks", [])
	
	if not task_id in assigned:
		push_warning("[ServerManager] Player %d tried to complete unassigned task: %s" % [player_id, task_id])
		return
	if task_id in done:
		return # Already completed, ignore silently
	
	done.append(task_id)
	player_data["done_tasks"] = done
	
	TaskManager.complete_task(player_id, task_id)


# ==========================================
# CLIENT-SIDE RPC HANDLERS
# ==========================================

@rpc("authority", "call_remote", "reliable")
func receive_role(assigned_role: Enums.Role) -> void:
	PlayerManager.local_player_data["role"] = assigned_role
	print("[Peer %d] My role is: " % multiplayer.get_unique_id(), Enums.Role.keys()[assigned_role])
	
	# Emit a signal so the UI / GameManager can handle the role reveal screen
	PlayerManager.role_assigned.emit(assigned_role)

@rpc("authority", "call_remote", "reliable")
func receive_task_list(task_ids: Array) -> void:
	print("[Peer %d] Received Task ID list from Server: " % multiplayer.get_unique_id(), task_ids)

	# The client resolves full task info from the IDs itself, for rendering the UI
	var task_resources: Array = []
	for id in task_ids:
		var task_res = TaskManager.get_task_info(id)
		if task_res:
			task_resources.append(task_res)
	
	# Store the resolved data on the local player
	PlayerManager.local_player_data["tasks"] = task_resources
	
	# Emit a signal so the HUD / Task UI can refresh
	TaskManager.client_tasks_updated.emit(task_resources)
	
@rpc("authority", "call_local", "reliable")
func _sync_players_state(updated_state: Dictionary) -> void:
	PlayerManager.players_state = updated_state
	PlayerManager.players_state_updated.emit()
		
func all_players_ready() -> bool:
	return PlayerManager.players_state.size() > 0 and PlayerManager.players_state.values().all(
		func(p): return p.get("ready", false)
	)
	
@rpc("any_peer", "reliable")
func _request_set_ready(peer_id: int, is_ready: bool) -> void:
		if not multiplayer.is_server():
			return
		_apply_ready(peer_id, is_ready)
	
func _apply_ready(peer_id: int, is_ready:bool) -> void:
	PlayerManager.set_ready_state(peer_id, is_ready)
	_sync_players_state(PlayerManager.players_state)
	

extends Node

# ==========================================
# SERVER MANAGER — CHANGES IN THIS PASS
# 1. _reset_match_state() no longer calls PlayerManager.reset_manager() in a
#    loop (that wiped the ENTIRE players_state dict right before
#    assign_roles/assign_tasks needed it — would crash on match start).
#    Now calls PlayerManager.reset_players_for_new_round() once, which only
#    resets per-round fields and keeps the roster intact.
# 2. Removed the _ready() subscription to NetworkManager.player_disconnected.
#    It was connected directly to _sync_players_state(Dictionary), but the
#    signal emits an int (peer_id) — type mismatch, would break on any
#    disconnect. Per our ownership split, ServerManager doesn't own
#    disconnect-triggered sync anyway (that's NetworkManager's job, next pass).
# 3. _sync_players_state was being called directly instead of via .rpc(),
#    so the @rpc annotation was a no-op and ready-state changes never
#    actually reached other clients — only the server's own local copy
#    updated. Now calls _sync_players_state.rpc(...).
# 4. All direct players_state[id][...] writes replaced with PlayerManager
#    setters (set_role, set_assigned_tasks, add_done_task) per the
#    "PlayerManager owns all writes" decision.
# ==========================================

# Number of Impostors (configurable by the Host in the Lobby)
var num_impostors: int = 1
# Number of tasks assigned to each Crewmate per match
var tasks_per_crewmate: int = 2


# ==========================================
# READY STATE (LOBBY)
# ==========================================

func request_local_ready(is_ready:bool) -> void:
	var my_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		_apply_ready(my_id, is_ready)
	else:
		_request_set_ready.rpc_id(Constants.HOST_ID, my_id, is_ready)

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
	
	_reset_match_state()
	assign_roles(player_ids)
	assign_tasks(player_ids)
	
## Clears any leftover per-player match data (is_alive, assigned_tasks,
## done_tasks) from a previous round WITHOUT touching the connected
## roster itself — that stays intact so assign_roles/assign_tasks below
## still have players to work with.
func _reset_match_state() -> void:
	PlayerManager.reset_players_for_new_round()
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
		
		# 1. Update the state on the Server (via PlayerManager, not a direct write)
		PlayerManager.set_role(id, assigned_role) 
		
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
		if PlayerManager.get_role(id) == Enums.Role.CREWMATE:
			crewmate_count += 1
	
	#Get all tasks
	var fixed_task_ids: Array[String] = TaskManager.get_all_task_ids()
	# Total number of tasks to complete this match (used for the progress bar)
	TaskManager.total_tasks_count = crewmate_count * tasks_per_crewmate

	for id in player_ids:
		var role = PlayerManager.get_role(id)
		var assigned_task_ids: Array[String] = []
		
		if role == Enums.Role.CREWMATE:
			## Pick random task IDs from TaskManager
			#assigned_task_ids = TaskManager.get_random_task_ids(tasks_per_crewmate)
			assigned_task_ids = fixed_task_ids
		else:
			# Impostors get fake task IDs (or their own dedicated fake task list)
			assigned_task_ids = ["fake_task_1"]
		
		# Update the player's task list via PlayerManager (not a direct write)
		# PlayerManager.set_assigned_tasks(id, assigned_task_ids)
		
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
	
	var assigned: Array = PlayerManager.get_assigned_tasks(player_id)
	if not task_id in assigned:
		push_warning("[ServerManager] Player %d tried to complete unassigned task: %s" % [player_id, task_id])
		return
	
	# add_done_task() returns false if already completed (or invalid peer),
	# so we skip re-broadcasting a completion that already happened.
	if not PlayerManager.add_done_task(player_id, task_id):
		return
	
	TaskManager.complete_task(player_id, task_id)


# ==========================================
# CLIENT-SIDE RPC HANDLERS
# ==========================================

@rpc("authority", "call_remote", "reliable")
func receive_role(assigned_role: Enums.Role) -> void:
	var my_id = multiplayer.get_unique_id()
	PlayerManager.set_role(my_id, assigned_role)
	print("[Peer %d] My role is: " % my_id, Enums.Role.keys()[assigned_role])


@rpc("authority", "call_remote", "reliable")
func receive_task_list(task_ids: Array) -> void:
	var my_id = multiplayer.get_unique_id()
	print("[Peer %d] Received Task ID list from Server: " % my_id, task_ids)

	## The client resolves full task info from the IDs itself, for rendering the UI
	#var task_resources: Array = [] - TaskManager.get_task_info handled it
	#for id in task_ids:
		#var task_res = TaskManager.get_task_info(id)
		#if task_res:
			#task_resources.append(task_res)
	
	# Store the resolved data on the local player
	PlayerManager.set_assigned_tasks(my_id, task_ids)

@rpc("authority", "call_local", "reliable")
func _sync_players_state(updated_state: Dictionary) -> void:
	PlayerManager.players_state = updated_state
	PlayerManager.players_state_updated.emit()

@rpc("any_peer", "reliable")
func _request_set_ready(peer_id: int, is_ready: bool) -> void:
		if not multiplayer.is_server():
			return
		_apply_ready(peer_id, is_ready)
	
func _apply_ready(peer_id: int, is_ready:bool) -> void:
	PlayerManager.set_ready_state(peer_id, is_ready)
	# Must go through .rpc() — calling _sync_players_state directly would
	# only run it locally on the server and never reach other clients,
	# even though it's annotated @rpc.
	_sync_players_state.rpc(PlayerManager.players_state)

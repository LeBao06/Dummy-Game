extends Node

# ==========================================
# GAME MANAGER
# Server-authoritative owner of the match state machine:
#   LOBBY -> PLAYING -> (MEETING -> VOTING -> PLAYING)* -> GAME_OVER -> LOBBY
#
# This does NOT duplicate role/task logic (that stays in ServerManager /
# TaskManager). GameManager's job is purely: know what phase the match is
# in, decide when a match ends and who won (Enums.GameResult), and keep
# every client's copy of that state in sync.
#
# MEETING / VOTING are exposed as enter_meeting() / enter_voting() stubs.
# There's no vote_manager.gd yet, so nothing calls them today — they're
# here so that script can just call GameManager instead of GameManager
# needing a rewrite once voting exists.
# ==========================================

signal state_changed(new_state: Enums.GameState)
signal match_ended(result: Enums.GameResult)

var current_state: Enums.GameState = Enums.GameState.LOBBY


func _ready() -> void:
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	TaskManager.all_tasks_completed.connect(_on_all_tasks_completed)
	state_changed.connect(_on_state_changed_debug_print)
	
func _on_state_changed_debug_print(new_state: Enums.GameState) -> void:
	print("[GameManager] Peer %d — state changed to: %s" % [multiplayer.get_unique_id(), Enums.GameState.keys()[new_state]])
# ==========================================
# --- SERVER-AUTHORITATIVE STATE CONTROL ---
# ==========================================

## Called by the Host's Lobby UI ("Start Game" button).
func request_start_match() -> void:
	if not multiplayer.is_server():
		return
	if current_state != Enums.GameState.LOBBY:
		push_warning("[GameManager] Cannot start match, current state is not LOBBY.")
		return

	ServerManager.start_match() ## Assigns roles/tasks
	_set_state(Enums.GameState.PLAYING) ## triggers scene change


## Called when an emergency meeting / report is triggered.
func enter_meeting() -> void:
	if not multiplayer.is_server():
		return
	if current_state != Enums.GameState.PLAYING:
		return
	_set_state(Enums.GameState.MEETING)


## Called once discussion time ends and voting UI should open.
func enter_voting() -> void:
	if not multiplayer.is_server():
		return
	if current_state != Enums.GameState.MEETING:
		return
	_set_state(Enums.GameState.VOTING)


## Called once a vote resolves with no ejection (or a tie), sending the
## match back to normal gameplay instead of ending it.
func resume_after_vote() -> void:
	if not multiplayer.is_server():
		return
	if current_state != Enums.GameState.VOTING:
		return
	_set_state(Enums.GameState.PLAYING)


## Central place to end a match. Call this instead of resolving win/lose
## logic inline elsewhere — ServerManager, VoteManager, kill abilities,
## sabotage timers, etc. should all just call this with the right result.
func end_match(result: Enums.GameResult) -> void:
	if not multiplayer.is_server():
		return
	if current_state == Enums.GameState.LOBBY or current_state == Enums.GameState.GAME_OVER:
		return # No match in progress, or already ended — ignore duplicate calls

	_broadcast_match_ended(result)
	_set_state(Enums.GameState.GAME_OVER)


## Sends everyone back to the Lobby state and clears per-match data,
## ready for another round.
func return_to_lobby() -> void:
	if not multiplayer.is_server():
		return

	PlayerManager.reset_manager()
	TaskManager.reset_manager()
	_set_state(Enums.GameState.LOBBY)


# ==========================================
# --- WIN CONDITION RESOLUTION ---
# ==========================================

func _crewmates_won(result: Enums.GameResult) -> bool:
	match result:
		Enums.GameResult.CREWMATE_VICTORY_TASKS, Enums.GameResult.CREWMATE_VICTORY_EJECT:
			return true
		Enums.GameResult.IMPOSTOR_VICTORY_KILLS, Enums.GameResult.IMPOSTOR_VICTORY_SABOTAGE:
			return false
		_:
			push_warning("[GameManager] Unknown GameResult: %s" % result)
			return false


func _on_all_tasks_completed() -> void:
	if not multiplayer.is_server():
		return
	end_match(Enums.GameResult.CREWMATE_VICTORY_TASKS)


## Very defensive placeholder: if a match is in progress and the lobby
## drops below 2 players, there's no valid game left to play. Extend this
## once impostor-count / alive-count tracking exists (that's really what
## should drive IMPOSTOR_VICTORY_KILLS / CREWMATE_VICTORY_EJECT).
func _on_player_disconnected(_id: int) -> void:
	if not multiplayer.is_server():
		return
	if current_state == Enums.GameState.LOBBY or current_state == Enums.GameState.GAME_OVER:
		return
	if PlayerManager.get_player_count() < 2:
		push_warning("[GameManager] Not enough players remaining, aborting match.")
		return_to_lobby()

# ==========================================
# --- SCENE TRANSISTION --- 
# ==========================================


## Maps a GameState to the scene that should be loaded for it, if any.
## Returns "" for states that don't involve a scene change (MEETING/VOTING/
## GAME_OVER might just show an overlay on top of gameplay.tscn instead).

func _scene_for_state(state: Enums.GameState) -> String:
	match state:
		Enums.GameState.LOBBY:
			return Constants.WAITING_ROOM
		Enums.GameState.PLAYING:
			return Constants.GAMEPLAY_SCENE
		_:
			return "" # MEETING, VOTING, GAME_OVER: handled as overlays, no scene swap
			
			
## Called on every peer (host included) whenever state changes, right
## after state_changed is emitted. Keeps this in one place so neither
## _set_state nor _receive_state need to duplicate the scene logic.
func _apply_scene_for_state(state: Enums.GameState) -> void:
	var target_scene := _scene_for_state(state)
	if target_scene != "":
		get_tree().change_scene_to_file(target_scene)

# ==========================================
# --- NETWORK SYNC (state + result broadcast to clients) ---
# ==========================================

func _set_state(new_state: Enums.GameState) -> void:
	current_state = new_state
	state_changed.emit(new_state)
	_apply_scene_for_state(new_state)
	
	if not multiplayer.is_server():
		return

	for id in PlayerManager.players_state.keys():
		if id == Constants.HOST_ID:
			continue
		rpc_id(id, "_receive_state", new_state)


func _broadcast_match_ended(result: Enums.GameResult) -> void:
	match_ended.emit(result)

	if not multiplayer.is_server():
		return

	for id in PlayerManager.players_state.keys():
		if id == Constants.HOST_ID:
			continue
		rpc_id(id, "_receive_match_ended", result)


@rpc("authority", "call_remote", "reliable")
func _receive_state(new_state: Enums.GameState) -> void:
	current_state = new_state
	state_changed.emit(new_state)
	_apply_scene_for_state(new_state)


@rpc("authority", "call_remote", "reliable")
func _receive_match_ended(result: Enums.GameResult) -> void:
	match_ended.emit(result)

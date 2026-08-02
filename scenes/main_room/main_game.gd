extends Node2D

@onready var ready_button: Button = $LobbyUI/Container/ReadyButton
@onready var start_button: Button = $LobbyUI/Container/StartButton
@onready var player_list_container: VBoxContainer = $LobbyUI/Container/PlayerListContainer
@onready var scene_container: Node2D = $SceneContainer

const LOBBY_SCENE := preload("res://scenes/waiting_room/lobby_scene.tscn")
## const GAMEPLAY_SCENE := preload("res://scenes/gameplay_room/gameplay.tscn") 

func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)

	start_button.visible = multiplayer.is_server()
	start_button.disabled = true

	PlayerManager.players_state_updated.connect(_update_ui)

	_update_ui()
	GameManager.state_changed.connect(_on_state_changed)
	load_scene(LOBBY_SCENE)   # start in the lobby


#swap lobby and gameplay
func load_scene(packed_scene: PackedScene) -> void:
	for child in scene_container.get_children():
		child.queue_free()
	var instance = packed_scene.instantiate()
	scene_container.add_child(instance)
	print("[Main] Peer %d — loaded scene: %s" % [multiplayer.get_unique_id(), packed_scene.resource_path])


func _on_state_changed(new_state: Enums.GameState) -> void:
	match new_state:
		Enums.GameState.LOBBY:
			load_scene(LOBBY_SCENE)
##		Enums.GameState.PLAYING:
##			load_scene(GAMEPLAY_SCENE)
func _on_ready_pressed() -> void:
	ready_button.disabled = true
	ServerManager.request_local_ready(true)


func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	GameManager.request_start_match()


func _update_ui() -> void:
	for child in player_list_container.get_children():
		child.queue_free()

	for id in PlayerManager.players_state:
		var label := Label.new()
		var status := "✅ Ready" if PlayerManager.is_player_ready(id) else "⏳ Not Ready"
		var display_name: String = "Player ID: %d" % id
		label.text = "%s - %s" % [display_name, status]
		player_list_container.add_child(label)

	if multiplayer.is_server():
		start_button.disabled = not PlayerManager.all_players_ready()

extends Node2D

@onready var ready_button: Button = $UI/LobbyUI/Control/PanelContainer/VBoxContainer/ReadyButton
@onready var start_button: Button = $UI/LobbyUI/Control/PanelContainer/VBoxContainer/StartButton
@onready var player_list_container: VBoxContainer = $UI/LobbyUI/Control/PanelContainer/VBoxContainer/PlayerListContainer
@onready var scene_container: Node2D = $World/SceneContainer
@onready var lobby_ui: CanvasLayer = $UI/LobbyUI
@onready var gameplay_ui: CanvasLayer = $UI/GameplayUI

const LOBBY_SCENE := preload("res://scenes/waiting_room/lobby_scene.tscn")
const GAMEPLAY_SCENE := preload("res://scenes/gameplay_room/gameplay.tscn") 

func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)

	start_button.visible = multiplayer.is_server()
	start_button.disabled = true

	PlayerManager.players_state_updated.connect(_update_ui)
	GameManager.state_changed.connect(_on_state_changed)

	_update_ui()
	load_scene(LOBBY_SCENE)   # start in the lobby


#swap lobby and gameplay
func load_scene(packed_scene: PackedScene) -> void:
	for child in scene_container.get_children():
		child.queue_free()
	
	if packed_scene:
		var instance = packed_scene.instantiate()
		scene_container.add_child(instance)
		print("[Main] Peer %d — loaded scene: %s" % [multiplayer.get_unique_id(), packed_scene.resource_path])

func _on_state_changed(new_state: Enums.GameState) -> void:
	match new_state:
		Enums.GameState.LOBBY:
			lobby_ui.visible = true
			gameplay_ui.visible = false
			load_scene(LOBBY_SCENE)
		Enums.GameState.PLAYING:
			lobby_ui.visible = false
			gameplay_ui.visible = true
			load_scene(GAMEPLAY_SCENE)
		Enums.GameState.MEETING, Enums.GameState.VOTING:
			# Các state này chỉ hiện UI Overlay, không swap scene
			pass


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

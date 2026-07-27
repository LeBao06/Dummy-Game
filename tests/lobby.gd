extends Node2D

# UI References
@onready var start_game_button: Button = $CanvasLayer/Control/StartGameButton
@onready var leave_button: Button = $CanvasLayer/Control/LeaveButton
@onready var room_code_label: Label = $CanvasLayer/Control/RoomCodeLabel

# Spawn References
@onready var spawn_points: Node2D = $SpawnPoints
@onready var multiplayer_spawner: MultiplayerSpawner = $MultiplayerSpawner

# Preload file Scene của Player (Thay đúng đường dẫn file Player 2D của bạn)
const PLAYER_SCENE = preload("res://entities/player/player.tscn") 


func _ready() -> void:
	# 1. Connect UI Buttons
	leave_button.pressed.connect(_on_leave_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	
	# 2. Only HOST can see and click "Start Game" button
	start_game_button.visible = multiplayer.is_server()
	
	# 3. Connect Network Signals from NetworkManager
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

# Handle "Leave Room" button
func _on_leave_button_pressed() -> void:
	print("[LOBBY] Player clicked Leave Room.")
	NetworkManager.remove_multiplayer_peer()
	get_tree().change_scene_to_file("res://scenes/lobby_menu/lobby_menu.tscn")


# Handle Host clicking "Start Game" button
func _on_start_game_button_pressed() -> void:
	if not multiplayer.is_server():
		return
		
	print("[LOBBY] Host started the game!")
	# Tạm thời in log, bài sau mình sẽ gọi GameManager.start_game() để chuyển map gameplay!


# Triggered on Client when Host closes the server
func _on_server_disconnected() -> void:
	print("[LOBBY] Server disconnected! Returning to main menu.")
	get_tree().change_scene_to_file("res://scenes/lobby_menu/lobby_menu.tscn")

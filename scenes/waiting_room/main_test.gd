extends Node2D

@onready var ready_button: Button = $HUD/Container/ReadyButton
@onready var start_button: Button = $HUD/Container/StartButton
@onready var player_list_container: VBoxContainer = $HUD/Container/PlayerListContainer


func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)

	start_button.visible = multiplayer.is_server()
	start_button.disabled = true

	PlayerManager.players_state_updated.connect(_update_ui)

	_update_ui()


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
		var data: Dictionary = PlayerManager.players_state[id]
		var label := Label.new()
		var status := "✅ Ready" if data.get("ready", false) else "⏳ Not Ready"
		var display_name: String = data.get("name", "Player %d" % id)
		label.text = "%s - %s" % [display_name, status]
		player_list_container.add_child(label)

	if multiplayer.is_server():
		start_button.disabled = not ServerManager.all_players_ready()

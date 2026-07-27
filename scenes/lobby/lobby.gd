extends Control

@onready var join_button : Button = $JoinButton
@onready var create_button : Button = $CreateButton
@onready var refresh_button : Button = $ServerPanel/Container/RefreshButton
@onready var name_input : LineEdit = $LobbyName
@onready var room_list: ItemList = $ServerPanel/ScrollBar/RoomList

var room_ips: Array[String] = [] #index = row
var is_joining: bool = false


func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	
	RoomDiscoveryManager.room_list_updated.connect(_on_room_list_updated)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _on_room_list_updated(rooms: Dictionary) -> void:
	room_list.clear()
	room_ips.clear()
	for ip in rooms.keys():
		var info = rooms[ip]
		room_list.add_item("%s (%d players)" % [info.name, info.players])
		room_ips.append(ip)
		
func _on_create_pressed() -> void:
	print("CREATE BUTTON PRESSED")
	var room_name = name_input.text if not name_input.text.is_empty() else "Default Room"
	var err := NetworkManager.create_game(room_name)
	if err == OK:
		get_tree().change_scene_to_file("res://scenes/waiting_room/main_test.tscn")

func _on_join_pressed() -> void:
	var selected := room_list.get_selected_items()
	if selected.is_empty():
		return
	var ip := room_ips[selected[0]]
	var err := NetworkManager.join_game(ip)
	if err != OK:
		# Failed to even create the client peer (e.g. bad address) - nothing to wait on
		push_warning("JoinGame: failed to create client peer (%s)" % err)
		return
	
	is_joining = true
	join_button.disabled = true

func _on_refresh_pressed() -> void:
	room_list.clear()
	room_ips.clear()
	RoomDiscoveryManager.search_for_rooms()

func _on_connection_succeeded() -> void:
	if not is_joining:
		return
	is_joining = false
	join_button.disabled = false
	get_tree().change_scene_to_file(Constants.WAITING_ROOM)

func _on_connection_failed() -> void:
	if not is_joining:
		return
	is_joining = false
	join_button.disabled = false
	push_warning("JoinGame: connection to server failed or timed out")
	# TODO: surface this to the player once there's an error/status label in the lobby scene

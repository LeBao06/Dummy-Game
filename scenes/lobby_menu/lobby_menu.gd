extends Control

# UI Node References (using Unique Names)
@onready var host_button: Button = %HostButton
@onready var room_name_edit: LineEdit = %RoomNameEdit

@onready var join_button: Button = %JoinButton
@onready var ip_edit: LineEdit = %IPEdit

@onready var refresh_button: Button = %RefreshButton
@onready var room_list: ItemList = %RoomList
@onready var status_label: Label = %StatusLabel

# Stores IP addresses corresponding to each row index in ItemList
var _room_ips: Array[String] = []


func _ready() -> void:
	# Connect UI button signals
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	room_list.item_activated.connect(_on_room_item_double_clicked)
	
	# Connect network manager callbacks
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	
	# Connect LAN room discovery signals
	RoomDiscoveryManager.room_list_updated.connect(_on_room_list_updated)
	
	# Start searching for LAN rooms automatically on startup
	_start_searching_rooms()


# ==========================================
# --- HOST GAME HANDLERS ---
# ==========================================

func _on_host_button_pressed() -> void:
	var room_name := room_name_edit.text.strip_edges()
	if room_name.is_empty():
		room_name = "Default Room"
		
	status_label.text = "Đang khởi tạo phòng..."
	
	var error := NetworkManager.create_game(room_name)
	if error == OK:
		status_label.text = "Tạo phòng thành công!"
		print("[HOST SUCCESS] Room created: %s" % room_name)
		
		# change to lobby scene (for HOST)
		_change_to_room_lobby()
	else:
		status_label.text = "Tạo phòng thất bại! Mã lỗi: %d" % error
		print("[HOST FAILED] Could not create server, error code: %d" % error)


# ==========================================
# --- DIRECT JOIN HANDLERS ---
# ==========================================

func _on_join_button_pressed() -> void:
	var target_ip := ip_edit.text.strip_edges()
	status_label.text = "Đang kết nối tới %s..." % (target_ip if not target_ip.is_empty() else "Server Mặc định")
	
	var error := NetworkManager.join_game(target_ip)
	if error != OK:
		status_label.text = "Lỗi khởi tạo kết nối! Mã lỗi: %d" % error
		print("[JOIN FAILED] Could not initiate client connection, error code: %d" % error)


# Triggered on the CLIENT when connection succeeds
func _on_connection_succeeded() -> void:
	status_label.text = "Kết nối thành công!"
	print("[JOIN SUCCESS] Successfully connected to server!")
	
	# change to lobby scene (for CLIENT)
	_change_to_room_lobby()


# Triggered on the CLIENT when connection fails
func _on_connection_failed() -> void:
	status_label.text = "Kết nối thất bại! Hãy kiểm tra lại IP hoặc phòng chưa mở."
	print("[JOIN FAILED] Failed to connect to server.")


# ==========================================
# --- LAN ROOM DISCOVERY HANDLERS ---
# ==========================================

func _start_searching_rooms() -> void:
	status_label.text = "Đang quét danh sách phòng LAN..."
	room_list.clear()
	_room_ips.clear()
	RoomDiscoveryManager.search_for_rooms()


func _on_refresh_pressed() -> void:
	_start_searching_rooms()


# Triggered whenever RoomDiscoveryManager receives updated LAN room data
func _on_room_list_updated(rooms: Dictionary) -> void:
	room_list.clear()
	_room_ips.clear()
	
	if rooms.is_empty():
		status_label.text = "Không tìm thấy phòng nào trong LAN."
		return
		
	status_label.text = "Đã tìm thấy %d phòng!" % rooms.size()
	
	for ip in rooms.keys():
		var room_info: Dictionary = rooms[ip]
		var display_text := "%s  |  IP: %s  |  (%d người)" % [room_info["name"], ip, room_info["players"]]
		
		room_list.add_item(display_text)
		_room_ips.append(ip)


# Triggered when double-clicking an item in the room list
func _on_room_item_double_clicked(index: int) -> void:
	if index < _room_ips.size():
		var target_ip := _room_ips[index]
		status_label.text = "Đang vào phòng: %s..." % target_ip
		NetworkManager.join_game(target_ip)


# Cleanup discovery socket when leaving the menu scene
func _exit_tree() -> void:
	RoomDiscoveryManager.stop_searching()

# Helper function to switch to the Room Lobby scene
func _change_to_room_lobby() -> void:
	# Stop searching for rooms before changing scene
	RoomDiscoveryManager.stop_searching()
	
	# Change scene to your Room Lobby file
	# (Change the path below to match your actual RoomLobby.tscn location)
	get_tree().change_scene_to_file("res://scenes/main_room/main_game.tscn")

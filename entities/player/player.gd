extends CharacterBody2D

# Movement speed of the player
@export var SPEED = 200.0

# References to child nodes
@onready var camera = $Camera2D
@onready var animation = $AnimatedSprite2D

# Array store interactable object list near by Player
var interactables_in_range: Array[Area2D] = []

func _ready():
	# If this player character belongs to the local machine, turn on the camera.
	# If it belongs to another player on the network, keep the camera off.
	if is_multiplayer_authority():
		camera.make_current()

func _enter_tree():
	var id = name.to_int()
	# Guarantee for standalone test
	if id == 0:
		id = 1
	
	# Set authority for Player with this Peer ID
	set_multiplayer_authority(id)
	$MultiplayerSynchronizer.set_multiplayer_authority(id)

func _physics_process(_delta):
	# 1. Only Authority of this Player can handle Movement
	if is_multiplayer_authority():
		var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_direction != Vector2.ZERO:
			velocity = input_direction * SPEED
		else:
			velocity = Vector2.ZERO
		move_and_slide()
	
	# 2. Both machines (Local + Remote) auto update ANIMATION based on VELOCITY
	_update_animation()

func _update_animation():
	if velocity.length_squared() > 1.0:
		# Handle walking
		if animation.animation != "walk" or not animation.is_playing():
			animation.animation = "walk"
			animation.play()
			animation.frame = 1
		
		# Handle flipping
		animation.flip_v = false
		if velocity.x != 0:
			animation.flip_h = velocity.x > 0
	else:
		# Stop animation
		if animation.is_playing():
			animation.stop()
		animation.frame = 0

func _unhandled_input(event: InputEvent) -> void:
	# Kiểm tra khi người chơi bấm nút Tương tác (ví dụ phím E hoặc nút Use)
	if event.is_action_pressed("interact"):
		execute_interaction()

func execute_interaction() -> void:
	if interactables_in_range.is_empty():
		return
	
	# Lấy vật thể gần nhất trong danh sách (hoặc vật thể đầu tiên)
	var target = interactables_in_range.back()
	
	# Gọi hàm tương tác trên vật thể đó (nếu vật thể có định nghĩa hàm interact)
	if target.has_method("interact"):
		target.interact(self) # Truyền bản thân Player vào nếu cần xử lý logic

# Signal khi đi vào vùng tương tác của Task/Vent/...
func _on_interaction_detector_area_entered(area: Area2D) -> void:
	if not interactables_in_range.has(area):
		interactables_in_range.append(area)
		# Gợi ý: Tại đây bạn có thể bật sáng nút "Use" hoặc hiện viền cho vật thể!

# Signal khi đi ra khỏi vùng tương tác
func _on_interaction_detector_area_exited(area: Area2D) -> void:
	interactables_in_range.erase(area)
	# Gợi ý: Tắt nút "Use" nếu danh sách interactables_in_range bị rỗng

extends Area2D

var can_interact = false

func _input(event):
	# "ui_accept" thường là phím Enter hoặc Space mặc định của Godot
	if can_interact and event.is_action_pressed("ui_accept"):
		print("Đã tương tác với tủ quần áo! Sẵn sàng làm nhiệm vụ.")
		# logic mở mini-game hoặc giao diện task sẽ được gọi ở đây

func _on_body_entered(body):
	# Giả sử nhân vật của bạn có tên node là "Player"
	if body.name == "Player":
		can_interact = true
		print("Đứng gần tủ đồ! Nhấn Space/Enter để tương tác.")

func _on_body_exited(body):
	if body.name == "Player":
		can_interact = false
		print("Đã đi ra xa khỏi tủ đồ.")
